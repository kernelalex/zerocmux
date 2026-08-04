#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/xcodebuild" <<'SH'
#!/usr/bin/env bash
printf 'Test run with %s tests in 1 suite passed\n' "$CMUX_FAKE_SWIFT_TEST_COUNT"
SH
chmod +x "$TMP_DIR/xcodebuild"

run_wrapper() {
  local test_count="$1"
  local output_path="$2"
  set +e
  PATH="$TMP_DIR:$PATH" \
  RUNNER_TEMP="$TMP_DIR" \
  CMUX_APP_HOST_XCODEBUILD_ATTEMPTS=1 \
  CMUX_APP_HOST_MIN_SWIFT_TESTS=3 \
  CMUX_FAKE_SWIFT_TEST_COUNT="$test_count" \
    bash "$ROOT_DIR/scripts/ci/run-app-host-xcodebuild.sh" test >"$output_path" 2>&1
  local status=$?
  set -e
  return "$status"
}

if run_wrapper 0 "$TMP_DIR/zero.log"; then
  cat "$TMP_DIR/zero.log"
  echo "FAIL: app-host wrapper accepted a zero-test Swift Testing run"
  exit 1
fi

if ! grep -Fq "app-host xcodebuild ran 0 Swift tests; expected at least 3" "$TMP_DIR/zero.log"; then
  cat "$TMP_DIR/zero.log"
  echo "FAIL: app-host wrapper did not explain the Swift test-count failure"
  exit 1
fi

if ! run_wrapper 3 "$TMP_DIR/three.log"; then
  cat "$TMP_DIR/three.log"
  echo "FAIL: app-host wrapper rejected the required Swift test count"
  exit 1
fi

echo "PASS: app-host xcodebuild wrapper enforces focused Swift test counts"
