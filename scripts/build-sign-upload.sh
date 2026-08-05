#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, create DMG, generate appcast, and upload to GitHub release.
# Usage: ./scripts/build-sign-upload.sh <tag> [--allow-overwrite]
# Requires: ~/.secrets/cmuxterm.env with Apple signing credentials and SPARKLE_PRIVATE_KEY.

usage() {
  cat <<'EOF'
Usage: ./scripts/build-sign-upload.sh <tag> [--allow-overwrite]

Options:
  --allow-overwrite   Permit replacing existing release assets for the same tag.
                      Use only for emergency rerolls.
EOF
}

ALLOW_OVERWRITE="false"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-overwrite)
      ALLOW_OVERWRITE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}"

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

TAG="$1"
SIGN_HASH="A050CC7E193C8221BDBA204E731B046CDCCC1B30"
ENTITLEMENTS="cmux.entitlements"
APP_PATH="build/Build/Products/Release/zerocmux.app"

# --- Pre-flight ---
for tool in zig xcodebuild create-dmg xcrun codesign ditto gh; do
  command -v "$tool" >/dev/null || { echo "MISSING: $tool" >&2; exit 1; }
done
echo "Pre-flight checks passed"

# --- Build GhosttyKit (if needed) ---
if [ ! -d "GhosttyKit.xcframework" ]; then
  echo "Building GhosttyKit..."
  ./scripts/build-ghosttykit-xcframework.sh
  rm -rf GhosttyKit.xcframework
  cp -R ghostty/macos/GhosttyKit.xcframework GhosttyKit.xcframework
else
  echo "GhosttyKit.xcframework exists, skipping build"
fi

# --- Build app (Release, unsigned) ---
echo "Building app..."
rm -rf build/
xcodebuild -scheme zerocmux -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
echo "Build succeeded"

HELPER_PATH="$APP_PATH/Contents/Resources/bin/ghostty"
if [ ! -x "$HELPER_PATH" ]; then
  echo "Ghostty theme picker helper not found at $HELPER_PATH" >&2
  exit 1
fi

# --- Inject Sparkle keys ---
source ~/.secrets/cmuxterm.env
SPARKLE_PRIVATE_KEY_VALUE="${SPARKLE_PRIVATE_KEY:-}"
unset SPARKLE_PRIVATE_KEY
if [ -z "$SPARKLE_PRIVATE_KEY_VALUE" ]; then
  echo "Missing SPARKLE_PRIVATE_KEY secret" >&2
  exit 1
fi
echo "Injecting Sparkle keys..."
SPARKLE_PUBLIC_KEY_DERIVED="$(printf '%s' "$SPARKLE_PRIVATE_KEY_VALUE" | swift scripts/derive_sparkle_public_key.swift --stdin)"
unset SPARKLE_PRIVATE_KEY_VALUE
APP_PLIST="$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$APP_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY_DERIVED" "$APP_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://github.com/Enigma-Labs-Technology/zerocmux/releases/latest/download/appcast.xml" "$APP_PLIST"
echo "Sparkle keys injected"

# zerocmux is a non-sandboxed app. Sparkle's sandbox-only XPC services make the
# installer handoff wait for an agent connection that never arrives.
./scripts/remove-sparkle-sandbox-xpc-services.sh "$APP_PATH"

# --- Codesign ---
echo "Codesigning..."
./scripts/sign-zerocmux-bundle.sh "$APP_PATH" "$ENTITLEMENTS" "$SIGN_HASH"
echo "Codesign verified"

# --- Notarize app ---
echo "Notarizing app..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" zerocmux-notary.zip
xcrun notarytool submit zerocmux-notary.zip \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
rm -f zerocmux-notary.zip
echo "App notarized"

# --- Create and notarize DMG ---
echo "Creating DMG..."
./scripts/verify-app-bundle-licenses.sh "$APP_PATH"
rm -f zerocmux-macos.dmg
create-dmg --codesign "$SIGN_HASH" zerocmux-macos.dmg "$APP_PATH"
echo "Notarizing DMG..."
xcrun notarytool submit zerocmux-macos.dmg \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple zerocmux-macos.dmg
xcrun stapler validate zerocmux-macos.dmg
echo "DMG notarized"

# --- Generate Sparkle appcast ---
echo "Generating appcast..."
source ~/.secrets/cmuxterm.env
SPARKLE_PRIVATE_KEY_VALUE="${SPARKLE_PRIVATE_KEY:-}"
unset SPARKLE_PRIVATE_KEY
if [ -z "$SPARKLE_PRIVATE_KEY_VALUE" ]; then
  echo "Missing SPARKLE_PRIVATE_KEY secret" >&2
  exit 1
fi
old_umask="$(umask)"
umask 077
SPARKLE_PRIVATE_KEY_FILE_PATH="$(mktemp "${TMPDIR:-/tmp}/zerocmux-sparkle-private-key.XXXXXX")"
umask "$old_umask"
trap 'rm -f "${SPARKLE_PRIVATE_KEY_FILE_PATH:-}"' EXIT
printf '%s' "$SPARKLE_PRIVATE_KEY_VALUE" > "$SPARKLE_PRIVATE_KEY_FILE_PATH"
unset SPARKLE_PRIVATE_KEY_VALUE
SPARKLE_PRIVATE_KEY_FILE="$SPARKLE_PRIVATE_KEY_FILE_PATH" ./scripts/sparkle_generate_appcast.sh zerocmux-macos.dmg "$TAG" appcast.xml
rm -f "$SPARKLE_PRIVATE_KEY_FILE_PATH"
trap - EXIT
unset SPARKLE_PRIVATE_KEY APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD

# --- Create GitHub release (if needed) and upload ---
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists"
  EXISTING_ASSETS="$(gh release view "$TAG" --json assets --jq '.assets[].name' || true)"
  HAS_CONFLICTING_ASSET="false"
  for asset in zerocmux-macos.dmg appcast.xml; do
    if printf '%s\n' "$EXISTING_ASSETS" | grep -Fxq "$asset"; then
      HAS_CONFLICTING_ASSET="true"
      break
    fi
  done

  if [[ "$HAS_CONFLICTING_ASSET" == "true" && "$ALLOW_OVERWRITE" != "true" ]]; then
    echo "ERROR: Refusing to overwrite signed release assets for existing tag $TAG." >&2
    echo "Use a new tag, or rerun with --allow-overwrite for an emergency reroll." >&2
    exit 1
  fi

  if [[ "$ALLOW_OVERWRITE" == "true" ]]; then
    echo "Uploading with overwrite enabled for existing release $TAG..."
    gh release upload "$TAG" zerocmux-macos.dmg appcast.xml --clobber
  else
    echo "Uploading to existing release $TAG..."
    gh release upload "$TAG" zerocmux-macos.dmg appcast.xml
  fi
else
  echo "Creating release $TAG and uploading..."
  gh release create "$TAG" zerocmux-macos.dmg appcast.xml --title "$TAG" --notes "See CHANGELOG.md for details"
fi

# --- Verify ---
gh release view "$TAG"

# --- Update Homebrew cask (skip for nightlies) ---
if [[ "$TAG" != *"-nightly"* ]]; then
  VERSION="${TAG#v}"
  DMG_SHA256=$(shasum -a 256 zerocmux-macos.dmg | cut -d' ' -f1)
  echo "Updating homebrew cask to $VERSION (SHA: $DMG_SHA256)..."
  CASK_FILE="homebrew-cmux/Casks/zerocmux.rb"
  if [ -f "$CASK_FILE" ]; then
    cat > "$CASK_FILE" << CASKEOF
cask "zerocmux" do
  version "${VERSION}"
  sha256 "${DMG_SHA256}"

  url "https://github.com/Enigma-Labs-Technology/zerocmux/releases/download/v#{version}/zerocmux-macos.dmg"
  name "zerocmux"
  desc "Zero-telemetry native macOS terminal workspace for AI coding agents"
  homepage "https://github.com/Enigma-Labs-Technology/zerocmux"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "zerocmux.app"
  binary "#{appdir}/zerocmux.app/Contents/Resources/bin/zerocmux"

  zap trash: [
    "~/Library/Application Support/zerocmux",
    "~/Library/Caches/zerocmux",
    "~/Library/Preferences/com.kernelalex.zerocmux.plist",
    "~/Library/Application Support/cmux",
    "~/Library/Caches/cmux",
    "~/Library/Preferences/ai.manaflow.cmuxterm.plist",
  ]
end
CASKEOF
    cd homebrew-cmux
    git add Casks/zerocmux.rb
    if git diff --staged --quiet; then
      echo "Homebrew cask already up to date"
    else
      git commit -m "Update zerocmux to ${VERSION}"
      git push
      echo "Homebrew cask updated"
    fi
    cd ..
  else
    echo "WARNING: homebrew-zerocmux submodule not found, skipping cask update"
  fi
fi

# --- Cleanup ---
rm -rf build/ zerocmux-macos.dmg appcast.xml
echo ""
echo "=== Release $TAG complete ==="
say "zerocmux release complete"
