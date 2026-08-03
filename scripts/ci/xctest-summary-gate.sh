#!/usr/bin/env bash
# Decide whether a non-zero `xcodebuild test` exit is tolerable.
#
# The app-host suites intentionally tolerate ordinary XCTest assertion
# failures: they run real SwiftUI/WebKit/Ghostty windows on shared CI Macs
# and a subset is environment-sensitive. What must never be tolerated is an
# *unexpected* failure (a thrown/uncaught error or a crash), which XCTest
# reports as the parenthesised count in
#
#     Executed 897 tests, with 203 failures (16 unexpected) in 279.144 seconds
#
# The previous inline version of this gate took only the LAST summary line.
# When the app host crashes and XCTest relaunches, xcodebuild prints a
# trailing
#
#     Executed 0 tests, with 0 failures (0 unexpected) in 0.000 seconds
#
# for the empty relaunch. That line became the "last" summary and reported
# "(0 unexpected)", so a run with 16 unexpected failures was announced as
# "All failures are expected, treating as pass". This gate instead considers
# every summary line, and refuses to pass a run it cannot account for.
#
# Usage:
#   xctest-summary-gate.sh [log-file]      # reads stdin when no file given
# Exit 0 => tolerate, exit 1 => fail the step.
set -uo pipefail

log_source="${1:-/dev/stdin}"

awk '
  # XCTest summary lines, e.g.
  #   Executed 3 tests, with 1 failure (0 unexpected) in 0.077 (0.078) seconds
  match($0, /Executed [0-9]+ tests?, with [0-9]+ failures? \([0-9]+ unexpected\)/) {
    line = substr($0, RSTART, RLENGTH)

    split(line, head, " ")
    executed = head[2] + 0
    failures = head[5] + 0

    unexpected = line
    sub(/.*\(/, "", unexpected)
    sub(/ unexpected\).*/, "", unexpected)
    unexpected += 0

    # xcodebuild prints a summary per suite plus repeated overall totals, so
    # these counters are only ever used as "is any of them non-zero" flags,
    # never as a true test count.
    summaries += 1
    total_executed += executed
    max_failures = (failures > max_failures) ? failures : max_failures
    max_unexpected = (unexpected > max_unexpected) ? unexpected : max_unexpected
    if (unexpected > 0 && !(line in seen)) {
      seen[line] = 1
      offenders = offenders "  " line "\n"
    }
    next
  }
  END {
    if (summaries == 0) {
      print "No XCTest summary line found in the test output." > "/dev/stderr"
      print "Refusing to treat an unexplained non-zero exit as a pass." > "/dev/stderr"
      exit 1
    }
    if (total_executed == 0) {
      print "Every XCTest summary reported 0 executed tests." > "/dev/stderr"
      print "Refusing to treat a run that executed nothing as a pass." > "/dev/stderr"
      exit 1
    }
    if (max_unexpected > 0) {
      print "Unexpected test failures detected:" > "/dev/stderr"
      printf "%s", offenders > "/dev/stderr"
      exit 1
    }
    printf "No unexpected failures across %d summary line(s) (worst line: %d failure(s)); treating as pass.\n", \
      summaries, max_failures
    exit 0
  }
' "$log_source"
