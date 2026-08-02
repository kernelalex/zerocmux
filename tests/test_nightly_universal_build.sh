#!/usr/bin/env bash
# Regression test for the universal nightly macOS track.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_FILE="$ROOT_DIR/.github/workflows/nightly.yml"

if ! awk '
  /^      - name: Build universal nightly app \(Release\)/ { in_universal=1; next }
  in_universal && /^      - name:/ { in_universal=0 }
  in_universal && /xcodebuild -scheme zerocmux/ { saw_scheme=1 }
  in_universal && /-destination '\''generic\/platform=macOS'\''/ { saw_destination=1 }
  in_universal && /ARCHS="arm64 x86_64"/ { saw_archs=1 }
  in_universal && /ONLY_ACTIVE_ARCH=NO/ { saw_only_active_arch=1 }
  END { exit !(saw_scheme && saw_destination && saw_archs && saw_only_active_arch) }
' "$WORKFLOW_FILE"; then
  echo "FAIL: nightly workflow must build the zerocmux universal app with both slices"
  exit 1
fi

if ! grep -Fq 'NIGHTLY_BUNDLE_ID="${APPLE_NIGHTLY_BUNDLE_ID:-com.kernelalex.zerocmux.nightly}"' "$WORKFLOW_FILE"; then
  echo "FAIL: nightly workflow must default to the zerocmux nightly bundle ID"
  exit 1
fi

if ! grep -Fq 'NIGHTLY_DMG_IMMUTABLE="zerocmux-nightly-macos-${NIGHTLY_BUILD}.dmg"' "$WORKFLOW_FILE"; then
  echo "FAIL: nightly workflow must use zerocmux nightly DMG names"
  exit 1
fi

if ! grep -Fq 'zerocmux NIGHTLY.app' "$WORKFLOW_FILE"; then
  echo "FAIL: nightly workflow must package the app as zerocmux NIGHTLY.app"
  exit 1
fi

if ! grep -Fq './scripts/sparkle_generate_appcast.sh "$NIGHTLY_DMG_IMMUTABLE" nightly appcast.xml' "$WORKFLOW_FILE"; then
  echo "FAIL: nightly workflow must generate the nightly appcast from the immutable DMG"
  exit 1
fi

if ! grep -Fq 'cp appcast.xml appcast-universal.xml' "$WORKFLOW_FILE"; then
  echo "FAIL: nightly workflow must keep the legacy universal appcast compatibility feed"
  exit 1
fi

if ! grep -Fq "core.setOutput('should_publish', isMainRef ? 'true' : 'false');" "$WORKFLOW_FILE"; then
  echo "FAIL: nightly decide step must expose should_publish based on whether the ref is main"
  exit 1
fi

if ! awk '
  /^      - name: Upload branch nightly artifacts/ { in_upload=1; next }
  in_upload && /^      - name:/ { in_upload=0 }
  in_upload && /if: needs\.decide\.outputs\.should_publish != '\''true'\''/ { saw_if=1 }
  in_upload && /uses: actions\/upload-artifact@/ { saw_upload=1 }
  in_upload && /zerocmux-nightly-macos\*\.dmg/ { saw_dmg=1 }
  in_upload && /appcast\.xml/ { saw_appcast=1 }
  in_upload && /appcast-universal\.xml/ { saw_legacy_appcast=1 }
  END { exit !(saw_if && saw_upload && saw_dmg && saw_appcast && saw_legacy_appcast) }
' "$WORKFLOW_FILE"; then
  echo "FAIL: non-main nightly runs must upload the nightly DMG and both appcasts"
  exit 1
fi

if ! awk '
  /^      - name: Publish nightly release assets/ { in_publish=1; next }
  in_publish && /^      - name:/ { in_publish=0 }
  in_publish && /if: needs\.decide\.outputs\.should_publish == '\''true'\''/ { saw_publish_if=1 }
  in_publish && /zerocmux-nightly-macos-\$\{\{ github\.run_id \}\}\*\.dmg/ { saw_immutable=1 }
  in_publish && /zerocmux-nightly-macos\.dmg/ { saw_stable=1 }
  in_publish && /appcast\.xml/ { saw_appcast=1 }
  in_publish && /appcast-universal\.xml/ { saw_legacy_appcast=1 }
  END { exit !(saw_publish_if && saw_immutable && saw_stable && saw_appcast && saw_legacy_appcast) }
' "$WORKFLOW_FILE"; then
  echo "FAIL: main nightly publish must include stable and immutable DMGs plus both appcasts"
  exit 1
fi

echo "PASS: nightly workflow publishes the zerocmux universal nightly track"
