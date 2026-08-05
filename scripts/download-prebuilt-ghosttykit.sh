#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -n "${GHOSTTY_SHA:-}" ]; then
  GHOSTTY_SHA="$GHOSTTY_SHA"
else
  if [ ! -d "$REPO_ROOT/ghostty" ] || ! git -C "$REPO_ROOT/ghostty" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Missing ghostty submodule. Run ./scripts/setup.sh or git submodule update --init --recursive first." >&2
    exit 1
  fi
  GHOSTTY_SHA="$(git -C "$REPO_ROOT/ghostty" rev-parse HEAD)"
fi

TAG_HELPER="${GHOSTTYKIT_RELEASE_TAG_HELPER:-$SCRIPT_DIR/ghosttykit-release-tag.sh}"
if [ -n "${GHOSTTYKIT_RELEASE_TAG:-}" ]; then
  PRIMARY_TAG="$GHOSTTYKIT_RELEASE_TAG"
else
  PRIMARY_TAG="$("$TAG_HELPER" "$GHOSTTY_SHA")"
fi
LEGACY_TAG="xcframework-$GHOSTTY_SHA"
ARCHIVE_NAME="${GHOSTTYKIT_ARCHIVE_NAME:-GhosttyKit.xcframework.tar.gz}"
OUTPUT_DIR="${GHOSTTYKIT_OUTPUT_DIR:-GhosttyKit.xcframework}"
CHECKSUMS_FILE="${GHOSTTYKIT_CHECKSUMS_FILE:-$SCRIPT_DIR/ghosttykit-checksums.txt}"
GHOSTTYKIT_REPO="${GHOSTTYKIT_REPO:-Enigma-Labs-Technology/zerocmux}"
DOWNLOAD_RETRIES="${GHOSTTYKIT_DOWNLOAD_RETRIES:-30}"
DOWNLOAD_RETRY_DELAY="${GHOSTTYKIT_DOWNLOAD_RETRY_DELAY:-20}"
DOWNLOAD_CONNECT_TIMEOUT="${GHOSTTYKIT_DOWNLOAD_CONNECT_TIMEOUT:-10}"
DOWNLOAD_MAX_TIME="${GHOSTTYKIT_DOWNLOAD_MAX_TIME:-300}"
DOWNLOAD_HEAD_MAX_TIME="${GHOSTTYKIT_DOWNLOAD_HEAD_MAX_TIME:-30}"
ARCHIVE_VALIDATOR="${GHOSTTYKIT_ARCHIVE_VALIDATOR:-$SCRIPT_DIR/validate-xcframework-archive.py}"

DOWNLOAD_URLS=()
DOWNLOAD_TAGS=()
if [ -n "${GHOSTTYKIT_URL:-}" ]; then
  DOWNLOAD_URLS+=("$GHOSTTYKIT_URL")
  DOWNLOAD_TAGS+=("${GHOSTTYKIT_RELEASE_TAG:-custom-url}")
else
  DOWNLOAD_URLS+=("https://github.com/$GHOSTTYKIT_REPO/releases/download/$PRIMARY_TAG/$ARCHIVE_NAME")
  DOWNLOAD_TAGS+=("$PRIMARY_TAG")
  if [ -z "${GHOSTTYKIT_RELEASE_TAG:-}" ] && [ "$PRIMARY_TAG" != "$LEGACY_TAG" ]; then
    DOWNLOAD_URLS+=("https://github.com/$GHOSTTYKIT_REPO/releases/download/$LEGACY_TAG/$ARCHIVE_NAME")
    DOWNLOAD_TAGS+=("$LEGACY_TAG")
  fi
fi

if [ ! -f "$CHECKSUMS_FILE" ]; then
  echo "Missing checksum file: $CHECKSUMS_FILE" >&2
  exit 1
fi

EXPECTED_SHA256="$(
  awk -v sha="$GHOSTTY_SHA" '
    $1 == sha {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$CHECKSUMS_FILE" || true
)"

if [ -z "$EXPECTED_SHA256" ]; then
  echo "Missing pinned GhosttyKit checksum for ghostty $GHOSTTY_SHA in $CHECKSUMS_FILE" >&2
  exit 1
fi

echo "Downloading $ARCHIVE_NAME for ghostty $GHOSTTY_SHA"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ghosttykit-download.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
ARCHIVE_BASENAME="$(basename "$ARCHIVE_NAME")"
ARCHIVE_PATH="$TMP_DIR/$ARCHIVE_BASENAME"
EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"

download_http_status() {
  local url="$1"
  curl --silent --show-error --location --head \
    --connect-timeout "$DOWNLOAD_CONNECT_TIMEOUT" \
    --max-time "$DOWNLOAD_HEAD_MAX_TIME" \
    --output /dev/null \
    --write-out "%{http_code}" \
    "$url" || true
}

DOWNLOADED_TAG=""
LAST_DOWNLOAD_STATUS=1
for i in "${!DOWNLOAD_URLS[@]}"; do
  DOWNLOAD_URL="${DOWNLOAD_URLS[$i]}"
  DOWNLOAD_TAG="${DOWNLOAD_TAGS[$i]}"
  rm -f "$ARCHIVE_PATH"

  if [ "${#DOWNLOAD_URLS[@]}" -gt 1 ]; then
    HTTP_STATUS="$(download_http_status "$DOWNLOAD_URL")"
    if [ "$HTTP_STATUS" = "404" ]; then
      echo "GhosttyKit release $DOWNLOAD_TAG is not available; trying fallback if present." >&2
      continue
    fi
  fi

  echo "Attempting GhosttyKit release $DOWNLOAD_TAG"
  if curl --fail --show-error --location \
    --connect-timeout "$DOWNLOAD_CONNECT_TIMEOUT" \
    --max-time "$DOWNLOAD_MAX_TIME" \
    --retry "$DOWNLOAD_RETRIES" \
    --retry-delay "$DOWNLOAD_RETRY_DELAY" \
    --retry-all-errors \
    -o "$ARCHIVE_PATH" \
    "$DOWNLOAD_URL"; then
    DOWNLOADED_TAG="$DOWNLOAD_TAG"
    break
  fi

  LAST_DOWNLOAD_STATUS=$?
  if [ "$i" -lt "$((${#DOWNLOAD_URLS[@]} - 1))" ]; then
    echo "GhosttyKit release $DOWNLOAD_TAG download failed; trying fallback release." >&2
  fi
done

if [ -z "$DOWNLOADED_TAG" ]; then
  echo "Failed to download $ARCHIVE_NAME for ghostty $GHOSTTY_SHA" >&2
  exit "$LAST_DOWNLOAD_STATUS"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "$ARCHIVE_NAME checksum mismatch" >&2
  echo "Expected: $EXPECTED_SHA256" >&2
  echo "Actual:   $ACTUAL_SHA256" >&2
  exit 1
fi

python3 "$ARCHIVE_VALIDATOR" "$ARCHIVE_PATH"
mkdir -p "$(dirname "$OUTPUT_DIR")"
tar --no-same-owner -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
rm -rf "$OUTPUT_DIR"
mv "$EXTRACT_DIR/GhosttyKit.xcframework" "$OUTPUT_DIR"
test -d "$OUTPUT_DIR"

echo "Verified and extracted $OUTPUT_DIR"
