#!/usr/bin/env bash
# Regression test for the pinned GhosttyKit artifact verification helper.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/download-prebuilt-ghosttykit.sh"
TAG_SCRIPT="$ROOT_DIR/scripts/ghosttykit-release-tag.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

WORKFLOWS=(
  "$ROOT_DIR/.github/workflows/ci.yml"
  "$ROOT_DIR/.github/workflows/nightly.yml"
  "$ROOT_DIR/.github/workflows/release.yml"
)

FIXTURE_SHA="7dd589824d4c9bda8265355718800cccaf7189a0"
EXPECTED_FIXTURE_TAG="xcframework-$FIXTURE_SHA-sentry-off-crashsubdir-zerocmux-crash-v1"
FIXTURE_DIR="$TMP_DIR/fixture"
SUCCESS_DIR="$TMP_DIR/success"
FALLBACK_DIR="$TMP_DIR/fallback"
MISMATCH_DIR="$TMP_DIR/mismatch"
MISSING_ENTRY_DIR="$TMP_DIR/missing-entry"
NATIVE_SENTRY_DIR="$TMP_DIR/native-sentry"
BIN_DIR="$TMP_DIR/bin"
CHECKSUMS_FILE="$TMP_DIR/ghosttykit-checksums.txt"
SUCCESS_LOG="$TMP_DIR/curl-success.log"
FALLBACK_LOG="$TMP_DIR/curl-fallback.log"
FALLBACK_OUTPUT="$TMP_DIR/fallback.out"
MISMATCH_LOG="$TMP_DIR/curl-mismatch.log"
MISMATCH_OUTPUT="$TMP_DIR/mismatch.out"
MISSING_ENTRY_OUTPUT="$TMP_DIR/missing-entry.out"
NATIVE_SENTRY_OUTPUT="$TMP_DIR/native-sentry.out"

if [ "$("$TAG_SCRIPT" "$FIXTURE_SHA")" != "$EXPECTED_FIXTURE_TAG" ]; then
  echo "FAIL: GhosttyKit release tag helper did not emit the current flavor-suffixed tag"
  exit 1
fi

if [ "$(GHOSTTYKIT_CRASH_REPORT_SUBDIR="custom/crash" "$TAG_SCRIPT" "$FIXTURE_SHA")" != "xcframework-$FIXTURE_SHA-sentry-off-crashsubdir-custom-crash-v1" ]; then
  echo "FAIL: GhosttyKit release tag helper did not honor the crash report subdir"
  exit 1
fi

mkdir -p \
  "$FIXTURE_DIR/GhosttyKit.xcframework" \
  "$SUCCESS_DIR" \
  "$FALLBACK_DIR" \
  "$MISMATCH_DIR" \
  "$MISSING_ENTRY_DIR" \
  "$NATIVE_SENTRY_DIR/GhosttyKit.xcframework/macos-arm64_x86_64" \
  "$BIN_DIR"
printf 'fixture\n' > "$FIXTURE_DIR/GhosttyKit.xcframework/marker.txt"
(cd "$FIXTURE_DIR" && COPYFILE_DISABLE=1 tar czf "$TMP_DIR/GhosttyKit.xcframework.tar.gz" GhosttyKit.xcframework)
ACTUAL_SHA256="$(shasum -a 256 "$TMP_DIR/GhosttyKit.xcframework.tar.gz" | awk '{print $1}')"
printf '%s %s\n' "$FIXTURE_SHA" "$ACTUAL_SHA256" > "$CHECKSUMS_FILE"

printf 'object data containing sentry_options_new\n' \
  > "$NATIVE_SENTRY_DIR/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a"
(cd "$NATIVE_SENTRY_DIR" && COPYFILE_DISABLE=1 tar czf "$TMP_DIR/GhosttyKit-native-sentry.tar.gz" GhosttyKit.xcframework)

if python3 "$ROOT_DIR/scripts/validate-xcframework-archive.py" \
  "$TMP_DIR/GhosttyKit-native-sentry.tar.gz" >"$NATIVE_SENTRY_OUTPUT" 2>&1; then
  echo "FAIL: archive validator accepted a macOS GhosttyKit with native Sentry"
  exit 1
fi

if ! grep -Fq "embedded macOS GhosttyKit contains native Sentry marker" "$NATIVE_SENTRY_OUTPUT"; then
  echo "FAIL: archive validator did not report embedded native Sentry"
  exit 1
fi

for workflow in "${WORKFLOWS[@]}"; do
  if ! grep -Fq './scripts/download-prebuilt-ghosttykit.sh' "$workflow"; then
    echo "FAIL: $workflow must call download-prebuilt-ghosttykit.sh"
    exit 1
  fi
done

cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${TEST_CURL_LOG:?}"
FIXTURE_ARCHIVE="${TEST_FIXTURE_ARCHIVE:?}"
OUTPUT=""
URL=""
HEAD=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --head|-I)
      HEAD=1
      printf '%s\n' "$1" >> "$LOG_FILE"
      shift
      ;;
    -o)
      OUTPUT="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    -w|--write-out)
      shift 2
      ;;
    *)
      URL="$1"
      printf '%s\n' "$1" >> "$LOG_FILE"
      shift
      ;;
  esac
done

if [ "$HEAD" -eq 1 ]; then
  if [ -n "${TEST_HEAD_404_CONTAINS:-}" ] && [[ "$URL" == *"$TEST_HEAD_404_CONTAINS"* ]]; then
    printf '404'
  else
    printf '200'
  fi
  exit 0
fi

if [ -z "$OUTPUT" ]; then
  echo "curl stub missing -o output path" >&2
  exit 1
fi

if [ -n "${TEST_FAIL_DOWNLOAD_CONTAINS:-}" ] && [[ "$URL" == *"$TEST_FAIL_DOWNLOAD_CONTAINS"* ]]; then
  echo "forced curl failure for $URL" >&2
  exit 22
fi

cp "$FIXTURE_ARCHIVE" "$OUTPUT"
EOF
chmod +x "$BIN_DIR/curl"

(
  cd "$SUCCESS_DIR"
  PATH="$BIN_DIR:$PATH" \
  TEST_CURL_LOG="$SUCCESS_LOG" \
  TEST_FIXTURE_ARCHIVE="$TMP_DIR/GhosttyKit.xcframework.tar.gz" \
  GHOSTTY_SHA="$FIXTURE_SHA" \
  GHOSTTYKIT_CHECKSUMS_FILE="$CHECKSUMS_FILE" \
  "$SCRIPT"
)

if [ ! -f "$SUCCESS_DIR/GhosttyKit.xcframework/marker.txt" ]; then
  echo "FAIL: verification helper did not extract GhosttyKit.xcframework"
  exit 1
fi

if [ -f "$SUCCESS_DIR/GhosttyKit.xcframework.tar.gz" ]; then
  echo "FAIL: verification helper did not clean up the downloaded archive"
  exit 1
fi

for expected_arg in --retry --retry-delay --retry-all-errors; do
  if ! grep -Fxq -- "$expected_arg" "$SUCCESS_LOG"; then
    echo "FAIL: curl invocation missing $expected_arg"
    exit 1
  fi
done

if ! (
  cd "$FALLBACK_DIR"
  PATH="$BIN_DIR:$PATH" \
  TEST_CURL_LOG="$FALLBACK_LOG" \
  TEST_FIXTURE_ARCHIVE="$TMP_DIR/GhosttyKit.xcframework.tar.gz" \
  TEST_HEAD_404_CONTAINS="$EXPECTED_FIXTURE_TAG" \
  TEST_FAIL_DOWNLOAD_CONTAINS="$EXPECTED_FIXTURE_TAG" \
  GHOSTTY_SHA="$FIXTURE_SHA" \
  GHOSTTYKIT_CHECKSUMS_FILE="$CHECKSUMS_FILE" \
  "$SCRIPT"
) >"$FALLBACK_OUTPUT" 2>&1; then
  echo "FAIL: verification helper did not fall back to the legacy GhosttyKit release tag"
  cat "$FALLBACK_OUTPUT"
  exit 1
fi

if [ ! -f "$FALLBACK_DIR/GhosttyKit.xcframework/marker.txt" ]; then
  echo "FAIL: verification helper did not extract GhosttyKit.xcframework after fallback"
  exit 1
fi

if ! grep -Fq "$EXPECTED_FIXTURE_TAG/GhosttyKit.xcframework.tar.gz" "$FALLBACK_LOG"; then
  echo "FAIL: fallback test did not attempt the current flavor-suffixed tag"
  exit 1
fi

if ! grep -Fq "xcframework-$FIXTURE_SHA/GhosttyKit.xcframework.tar.gz" "$FALLBACK_LOG"; then
  echo "FAIL: fallback test did not attempt the legacy GhosttyKit release tag"
  exit 1
fi

printf '%s %s\n' "$FIXTURE_SHA" "0000000000000000000000000000000000000000000000000000000000000000" > "$CHECKSUMS_FILE"

if (
  cd "$MISMATCH_DIR"
  PATH="$BIN_DIR:$PATH" \
  TEST_CURL_LOG="$MISMATCH_LOG" \
  TEST_FIXTURE_ARCHIVE="$TMP_DIR/GhosttyKit.xcframework.tar.gz" \
  GHOSTTY_SHA="$FIXTURE_SHA" \
  GHOSTTYKIT_CHECKSUMS_FILE="$CHECKSUMS_FILE" \
  "$SCRIPT"
) >"$MISMATCH_OUTPUT" 2>&1; then
  echo "FAIL: verification helper succeeded with an invalid pinned checksum"
  exit 1
fi

if ! grep -Fq "GhosttyKit.xcframework.tar.gz checksum mismatch" "$MISMATCH_OUTPUT"; then
  echo "FAIL: verification helper did not report checksum mismatch"
  exit 1
fi

printf '%s %s\n' "0000000000000000000000000000000000000000" "$ACTUAL_SHA256" > "$CHECKSUMS_FILE"

if (
  cd "$MISSING_ENTRY_DIR"
  PATH="$BIN_DIR:$PATH" \
  TEST_CURL_LOG="$MISMATCH_LOG" \
  TEST_FIXTURE_ARCHIVE="$TMP_DIR/GhosttyKit.xcframework.tar.gz" \
  GHOSTTY_SHA="$FIXTURE_SHA" \
  GHOSTTYKIT_CHECKSUMS_FILE="$CHECKSUMS_FILE" \
  "$SCRIPT"
) >"$MISSING_ENTRY_OUTPUT" 2>&1; then
  echo "FAIL: verification helper succeeded without a pinned checksum entry"
  exit 1
fi

if ! grep -Fq "Missing pinned GhosttyKit checksum for ghostty $FIXTURE_SHA" "$MISSING_ENTRY_OUTPUT"; then
  echo "FAIL: verification helper did not report a missing pinned checksum entry"
  exit 1
fi

echo "PASS: GhosttyKit verification enforces pinned checksums and excludes native Sentry"
