#!/usr/bin/env python3
"""Behavioral regression test for scripts/ci/xctest-summary-gate.sh.

The app-host unit-test steps tolerate ordinary XCTest assertion failures but
must fail on unexpected failures (thrown errors / crashes). The gate used to
read only the LAST `Executed ... tests` summary, so the empty summary an
app-host relaunch appends silently rescued a run that had already reported
unexpected failures. These cases drive the real script and assert on its exit
status, not on its source text.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

GATE = Path(__file__).resolve().parent.parent / "scripts" / "ci" / "xctest-summary-gate.sh"

# Verbatim shape of the tail of app-host shard 4 in run 30776532164: the real
# result (16 unexpected) is followed by the summaries XCTest emits for the
# empty relaunch after the app host crashed.
CRASH_RELAUNCH_TAIL = """\
\t Executed 25 tests, with 9 failures (0 unexpected) in 0.812 (0.819) seconds
\t Executed 897 tests, with 203 failures (16 unexpected) in 279.144 (280.269) seconds
\t Executed 897 tests, with 203 failures (16 unexpected) in 279.144 (280.270) seconds
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
"""

TOLERATED_ASSERTION_FAILURES = """\
\t Executed 3 tests, with 1 failure (0 unexpected) in 0.077 (0.078) seconds
\t Executed 897 tests, with 203 failures (0 unexpected) in 279.144 (280.269) seconds
"""

CLEAN_RUN = """\
\t Executed 897 tests, with 0 failures (0 unexpected) in 279.144 (280.269) seconds
"""

UNEXPECTED_IN_MIDDLE = """\
\t Executed 54 tests, with 80 failures (8 unexpected) in 141.581 (141.603) seconds
\t Executed 36 tests, with 31 failures (0 unexpected) in 14.469 (14.496) seconds
\t Executed 900 tests, with 111 failures (0 unexpected) in 300.000 (300.001) seconds
"""

BUILD_DIED_BEFORE_TESTING = """\
** TEST FAILED **
error: Could not resolve package dependencies
"""

NOTHING_RAN = """\
\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
"""

CASES: list[tuple[str, str, int]] = [
    (
        "crash relaunch tail must not rescue a run with unexpected failures",
        CRASH_RELAUNCH_TAIL,
        1,
    ),
    (
        "ordinary assertion failures stay tolerated",
        TOLERATED_ASSERTION_FAILURES,
        0,
    ),
    ("a clean run passes", CLEAN_RUN, 0),
    (
        "an unexpected failure anywhere in the output fails the gate",
        UNEXPECTED_IN_MIDDLE,
        1,
    ),
    (
        "output with no summary at all fails instead of passing",
        BUILD_DIED_BEFORE_TESTING,
        1,
    ),
    ("a run that executed nothing fails instead of passing", NOTHING_RAN, 1),
]


def run_gate(text: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/bin/bash", str(GATE)],
        input=text,
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )


def main() -> int:
    if not GATE.exists():
        print(f"FAIL: gate script missing at {GATE}")
        return 1

    failures = 0
    for name, text, expected_status in CASES:
        result = run_gate(text)
        if result.returncode != expected_status:
            failures += 1
            print(f"FAIL: {name}")
            print(f"  expected exit {expected_status}, got {result.returncode}")
            print(f"  stdout={result.stdout.strip()!r}")
            print(f"  stderr={result.stderr.strip()!r}")

    # The failing case must name the offending summary so CI logs stay
    # actionable instead of just saying "unexpected test failures detected".
    offender = run_gate(CRASH_RELAUNCH_TAIL)
    if "16 unexpected" not in offender.stderr:
        failures += 1
        print("FAIL: gate did not report the offending summary line")
        print(f"  stderr={offender.stderr.strip()!r}")

    # A log-file argument must behave the same as stdin.
    import tempfile

    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
        handle.write(CRASH_RELAUNCH_TAIL)
        log_path = handle.name
    from_file = subprocess.run(
        ["/bin/bash", str(GATE), log_path],
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )
    Path(log_path).unlink(missing_ok=True)
    if from_file.returncode != 1:
        failures += 1
        print(f"FAIL: file argument path returned {from_file.returncode}, expected 1")

    if failures:
        print(f"FAIL: {failures} xctest summary gate case(s) failed")
        return 1

    print(f"PASS: xctest summary gate handles {len(CASES) + 2} cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
