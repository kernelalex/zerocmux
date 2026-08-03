#!/usr/bin/env python3

import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "ci" / "run-swift-testing-suites.sh"


class SwiftTestingSuiteTimeoutTests(unittest.TestCase):
    def run_with_fake_swift(
        self,
        swift_source: str,
        *,
        timeout_seconds: str = "1",
        tolerate_ghostty_diagnostic: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        temp = pathlib.Path(temp_dir.name)
        fake_swift = temp / "swift"
        fake_swift.write_text(swift_source, encoding="utf-8")
        fake_swift.chmod(0o755)
        package = temp / "ExampleTests"
        package.mkdir()
        env = os.environ.copy()
        env["PATH"] = f"{temp}:{env['PATH']}"
        env["CMUX_SWIFT_TEST_SUITE_TIMEOUT_SECONDS"] = timeout_seconds
        if tolerate_ghostty_diagnostic:
            env["CMUX_SWIFT_TEST_TOLERATE_GHOSTTY_BINARY_DIAGNOSTIC"] = "1"

        return subprocess.run(
            [str(RUNNER), str(package)],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=5,
            check=False,
        )

    def test_hung_suite_is_terminated_before_the_job_timeout(self) -> None:
        completed = self.run_with_fake_swift(
            "#!/usr/bin/env bash\n"
            "if [[ \"$*\" == *\"test list\"* ]]; then\n"
            "  echo 'ExampleTests.HangingSuite/testNeverFinishes()'\n"
            "  exit 0\n"
            "fi\n"
            "sleep 30\n"
        )

        self.assertEqual(completed.returncode, 124, completed.stdout)
        self.assertEqual(completed.stdout.count("timed out after 1s"), 2)
        self.assertIn("retrying HangingSuite once", completed.stdout)

    def test_known_ghostty_diagnostic_is_tolerated_for_passing_suites(self) -> None:
        completed = self.run_with_fake_swift(
            "#!/usr/bin/env bash\n"
            "echo 'error: unexpected binary name in GhosttyKit'\n"
            "if [[ \"$*\" == *\"test list\"* ]]; then\n"
            "  echo 'ExampleTests.PassingSuite/testPasses()'\n"
            "else\n"
            "  echo 'Test run with 1 test in 1 suite passed'\n"
            "fi\n"
            "exit 1\n",
            tolerate_ghostty_diagnostic=True,
        )

        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("while listing suites", completed.stdout)
        self.assertIn("suite passed", completed.stdout)

    def test_other_errors_are_not_hidden_by_ghostty_diagnostic_tolerance(self) -> None:
        completed = self.run_with_fake_swift(
            "#!/usr/bin/env bash\n"
            "echo 'error: unexpected binary name in GhosttyKit'\n"
            "echo 'error: compilation failed'\n"
            "if [[ \"$*\" == *\"test list\"* ]]; then\n"
            "  echo 'ExampleTests.FailingSuite/testFails()'\n"
            "fi\n"
            "exit 1\n",
            tolerate_ghostty_diagnostic=True,
        )

        self.assertNotEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("error: compilation failed", completed.stdout)


if __name__ == "__main__":
    unittest.main()
