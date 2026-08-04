#!/usr/bin/env bash
set -euo pipefail

if ! command -v automationmodetool >/dev/null 2>&1; then
  echo "::warning::automationmodetool is unavailable; XCTest will use its default automation-mode setup"
  exit 0
fi

if ! sudo -n true 2>/dev/null; then
  echo "::warning::Passwordless sudo unavailable; XCTest will use its default automation-mode setup"
  exit 0
fi

python3 - <<'PY'
import os
import signal
import subprocess
import sys

command = [
    "sudo",
    "-n",
    "automationmodetool",
    "enable-automationmode-without-authentication",
]
process = subprocess.Popen(command, start_new_session=True)
try:
    returncode = process.wait(timeout=30)
except subprocess.TimeoutExpired:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    print(
        "::warning::automationmodetool timed out; XCTest will use its default automation-mode setup"
    )
    sys.exit(0)

if returncode != 0:
    print(
        f"::warning::automationmodetool exited with status {returncode}; "
        "XCTest will use its default automation-mode setup"
    )
PY
