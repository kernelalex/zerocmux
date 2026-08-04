#!/usr/bin/env bash
# Pins macOS jobs to the ephemeral self-hosted Tart pool and rejects cloud
# provider labels. Linux jobs use self-contained RunsOn Flex labels.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_DIR="$ROOT_DIR/.github/workflows"
CI_FILE="$WORKFLOW_DIR/ci.yml"
GHOSTTYKIT_FILE="$WORKFLOW_DIR/build-ghosttykit.yml"
COMPAT_FILE="$WORKFLOW_DIR/ci-macos-compat.yml"
RELEASE_FILE="$WORKFLOW_DIR/release.yml"
NIGHTLY_FILE="$WORKFLOW_DIR/nightly.yml"
TMUX_FILE="$WORKFLOW_DIR/tmux-corpus.yml"
TUI_FILE="$WORKFLOW_DIR/cmux-tui.yml"
TEST_MACOS_FILE="$WORKFLOW_DIR/test-macos.yml"
E2E_FILE="$WORKFLOW_DIR/test-e2e.yml"
PERF_FILE="$WORKFLOW_DIR/perf-activation.yml"
RELOAD_FILE="$WORKFLOW_DIR/reload-build.yml"

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

if grep -R -n -E 'runs-on:.*(macos-(latest|[0-9]+)|warp-macos|blacksmith-)|os: (macos-(latest|[0-9]+)|warp-macos|blacksmith-)' "$WORKFLOW_DIR"; then
  echo "FAIL: macOS workflows must route through the Tart self-hosted pool"
  exit 1
fi

if grep -R -n -E 'runs-on:.*(extras=.*otel|/otel([/+]|$))' "$WORKFLOW_DIR"; then
  echo "FAIL: RunsOn labels must not enable OTEL telemetry"
  exit 1
fi

# ci.yml jobs
check_runner "$CI_FILE" "workflow-guard-tests" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$CI_FILE" "app-host-unit-tests" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$CI_FILE" "swift-package-tests" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$CI_FILE" "tests-build-and-lag" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$CI_FILE" "release-build" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$CI_FILE" "ui-regressions" 'runs-on: tartelet' "Tartelet self-hosted"

# build-ghosttykit.yml
check_runner "$GHOSTTYKIT_FILE" "build-ghosttykit" 'runs-on: tartelet' "Tartelet self-hosted"

# ci-macos-compat.yml uses matrix.os.
check_runner "$COMPAT_FILE" "compat-tests" 'os: tartelet' "Tartelet self-hosted"

# release.yml jobs
check_runner "$RELEASE_FILE" "build-ghostty-cli-helper" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$RELEASE_FILE" "build-sign-notarize" 'runs-on: \[tartelet, zerocmux-signing\]' "Tartelet self-hosted signing"

# Other macOS workflows
check_runner "$NIGHTLY_FILE" "build-sign-notarize-nightly" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$TMUX_FILE" "terminal-nightly" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$TUI_FILE" "test" "matrix\.os == 'macos' && 'tartelet'" "Tartelet self-hosted for macOS"
check_runner "$TEST_MACOS_FILE" "tests" 'runs-on: tartelet' "Tartelet self-hosted"
check_runner "$E2E_FILE" "e2e" "&& 'tartelet' \|\| inputs\.runner" "Tartelet self-hosted"
check_runner "$PERF_FILE" "activation-session-benchmark" "&& 'tartelet' \|\| inputs\.runner" "Tartelet self-hosted"
check_runner "$RELOAD_FILE" "build" 'runs-on: \$\{\{ inputs\.runner \}\}' "the Tart-only dispatch input"

if ! grep -Fq 'default: tartelet' "$RELOAD_FILE"; then
  echo "FAIL: reload-build.yml must default to the Tart self-hosted pool"
  exit 1
fi
