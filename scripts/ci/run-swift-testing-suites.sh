#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <package-path>" >&2
  exit 2
fi

package_path="$1"
suite_timeout_seconds="${CMUX_SWIFT_TEST_SUITE_TIMEOUT_SECONDS:-300}"
tolerate_ghostty_binary_diagnostic="${CMUX_SWIFT_TEST_TOLERATE_GHOSTTY_BINARY_DIAGNOSTIC:-0}"
if ! [[ "$suite_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "CMUX_SWIFT_TEST_SUITE_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_dir="$(mktemp -d "${TMPDIR:-/tmp}/zerocmux-swift-testing-suites.XXXXXX")"
trap 'rm -rf "$output_dir"' EXIT

is_cosmetic_ghostty_binary_failure() {
  local output_file="$1"
  local requires_test_summary="$2"

  [ "$tolerate_ghostty_binary_diagnostic" = "1" ] || return 1
  grep -q 'unexpected binary' "$output_file" || return 1
  ! grep -Eq 'with [1-9][0-9]* failures?' "$output_file" || return 1
  if awk '
    /unexpected binary/ { next }
    /(^|[^a-zA-Z])error:/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$output_file"; then
    return 1
  fi
  if [ "$requires_test_summary" = "1" ]; then
    grep -Eq 'Test run with [0-9]+ tests?( in [0-9]+ suites?)? passed' "$output_file"
  fi
}

# Keep process-global test state inside one suite. Some packages otherwise
# finish every assertion but leave the aggregate Swift Testing runner waiting.
suite_list_output="$output_dir/list.txt"
suite_list_status=0
set +e
swift test list --package-path "$package_path" 2>&1 | tee "$suite_list_output"
suite_list_status=${PIPESTATUS[0]}
set -e
suite_list="$(sed -nE 's/^[^.]+\.([^/]+)\/.*$/\1/p' "$suite_list_output" | sort -u)"

if [ -z "$suite_list" ]; then
  echo "no test suites discovered for $package_path" >&2
  exit 1
fi
if [ "$suite_list_status" -ne 0 ]; then
  if is_cosmetic_ghostty_binary_failure "$suite_list_output" 0; then
    echo "Tolerated cosmetic GhosttyKit binaryTarget diagnostic while listing suites."
  else
    exit "$suite_list_status"
  fi
fi

run_suite_attempt() {
  local suite="$1"
  local output_file="$2"
  local suite_status=0

  set +e
  python3 "$script_dir/run_with_timeout.py" \
    --timeout-seconds "$suite_timeout_seconds" \
    -- swift test --package-path "$package_path" --filter "$suite" \
    2>&1 | tee "$output_file"
  suite_status=${PIPESTATUS[0]}
  set -e

  if [ "$suite_status" -ne 0 ] \
    && is_cosmetic_ghostty_binary_failure "$output_file" 1; then
    echo "Tolerated cosmetic GhosttyKit binaryTarget diagnostic; suite passed."
    return 0
  fi
  return "$suite_status"
}

while IFS= read -r suite; do
  [ -n "$suite" ] || continue
  echo "swift test $package_path --filter $suite"
  suite_status=0
  run_suite_attempt "$suite" "$output_dir/$suite-attempt-1.txt" || suite_status=$?
  if [ "$suite_status" -eq 124 ]; then
    echo "Swift test suite timed out; retrying $suite once." >&2
    suite_status=0
    run_suite_attempt "$suite" "$output_dir/$suite-attempt-2.txt" || suite_status=$?
  fi
  if [ "$suite_status" -ne 0 ]; then
    exit "$suite_status"
  fi
done < <(printf '%s\n' "$suite_list")
