#!/usr/bin/env bash
# Pins the expensive macOS jobs and the release signing lanes to the sanctioned
# Depot runners. This keeps those lanes from silently drifting back to
# GitHub-hosted macos-* runners or onto other third-party/self-hosted
# providers (warp-/blacksmith-) that the project no longer runs always-on CI on.
#
# Exception: cmux-browser.yml stays GitHub-hosted by design (its PR lane runs
# untrusted code) and is excluded from the provider sweep below.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_DIR="$ROOT_DIR/.github/workflows"
CI_FILE="$WORKFLOW_DIR/ci.yml"
GHOSTTYKIT_FILE="$WORKFLOW_DIR/build-ghosttykit.yml"
COMPAT_FILE="$WORKFLOW_DIR/ci-macos-compat.yml"
RELEASE_FILE="$WORKFLOW_DIR/release.yml"

check_runner() {
  local file="$1" job="$2" pattern="$3" description="$4"
  local job_body
  job_body="$(awk -v job="$job" '
    $0 ~ "^  "job":" { in_job=1; next }
    in_job && /^  [^[:space:]]/ { in_job=0 }
    in_job { print }
  ' "$file")"
  if ! grep -Eq "$pattern" <<<"$job_body"; then
    echo "FAIL: $job in $(basename "$file") must use $description"
    exit 1
  fi
  echo "PASS: $job uses $description"
}

if grep -R -n -E 'runs-on:.*(warp-macos|blacksmith-)|os: (warp-macos|blacksmith-)' "$WORKFLOW_DIR"; then
  echo "FAIL: always-on workflows must not hardcode warp-/blacksmith- runner labels (use Depot or GitHub-hosted runners)"
  exit 1
fi

# ci.yml jobs
check_runner "$CI_FILE" "app-host-unit-tests" 'runs-on: depot-macos-26' "Depot macos-26"
check_runner "$CI_FILE" "tests-build-and-lag" 'runs-on: depot-macos-26' "Depot macos-26"
check_runner "$CI_FILE" "release-build" 'runs-on: depot-macos-26' "Depot macos-26"
check_runner "$CI_FILE" "ui-regressions" 'runs-on: depot-macos-26' "Depot macos-26"

# build-ghosttykit.yml
check_runner "$GHOSTTYKIT_FILE" "build-ghosttykit" 'runs-on: depot-macos-26' "Depot macos-26"

# ci-macos-compat.yml uses matrix.os.
check_runner "$COMPAT_FILE" "compat-tests" 'os: depot-macos-26' "Depot macos-26"

# release.yml jobs
check_runner "$RELEASE_FILE" "build-ghostty-cli-helper" 'runs-on: depot-macos-26' "Depot macos-26"
check_runner "$RELEASE_FILE" "build-sign-notarize" 'runs-on: depot-macos-26' "Depot macos-26"
