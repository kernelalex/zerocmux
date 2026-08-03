#!/usr/bin/env bash
# Pins macOS jobs to GitHub-hosted Apple Silicon and rejects legacy provider
# labels. Linux jobs use self-contained RunsOn Flex labels.
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

if grep -R -n -E 'depot-|Depot' "$WORKFLOW_DIR"; then
  echo "FAIL: workflows must not reference Depot after the RunsOn migration"
  exit 1
fi

if grep -R -n -E 'runs-on:.*(warp-macos|blacksmith-)|os: (warp-macos|blacksmith-)' "$WORKFLOW_DIR"; then
  echo "FAIL: always-on workflows must not hardcode warp-/blacksmith- runner labels"
  exit 1
fi

if grep -R -n -E 'runs-on:.*(extras=.*otel|/otel([/+]|$))' "$WORKFLOW_DIR"; then
  echo "FAIL: RunsOn labels must not enable OTEL telemetry"
  exit 1
fi

# ci.yml jobs
check_runner "$CI_FILE" "app-host-unit-tests" 'runs-on: macos-latest' "GitHub-hosted macos-latest"
check_runner "$CI_FILE" "tests-build-and-lag" 'runs-on: macos-latest' "GitHub-hosted macos-latest"
check_runner "$CI_FILE" "release-build" 'runs-on: macos-latest' "GitHub-hosted macos-latest"
check_runner "$CI_FILE" "ui-regressions" 'runs-on: macos-latest' "GitHub-hosted macos-latest"

# build-ghosttykit.yml
check_runner "$GHOSTTYKIT_FILE" "build-ghosttykit" 'runs-on: macos-latest' "GitHub-hosted macos-latest"

# ci-macos-compat.yml uses matrix.os.
check_runner "$COMPAT_FILE" "compat-tests" 'os: macos-latest' "GitHub-hosted macos-latest"

# release.yml jobs
check_runner "$RELEASE_FILE" "build-ghostty-cli-helper" 'runs-on: macos-latest' "GitHub-hosted macos-latest"
check_runner "$RELEASE_FILE" "build-sign-notarize" 'runs-on: macos-latest' "GitHub-hosted macos-latest"
