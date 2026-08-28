#!/usr/bin/env python3

import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
import unittest


PLUGIN_DIR = Path(__file__).resolve().parent.parent
HELPER = PLUGIN_DIR / "safe-state"


class SafeStateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="melonamin-fast-state-test.", dir="/tmp")
        self.root = Path(self.temporary.name)
        self.state = self.root / "state" / "omarchy" / "plugins" / "melonamin.fast"
        self.environment = os.environ.copy()
        self.environment["MELONAMIN_FAST_STATE_DIR"] = str(self.state)

    def tearDown(self):
        self.temporary.cleanup()

    def run_helper(self, *arguments, timeout=2):
        return subprocess.run(
            [str(HELPER), *arguments],
            env=self.environment,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )

    def initialize(self):
        result = self.run_helper("history-read")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [])

    def test_history_is_bounded_private_and_atomic(self):
        self.initialize()
        result = self.run_helper(
            "history-add",
            "--timestamp", "1000",
            "--down", "120.5",
            "--up", "40.25",
            "--ping", "8.5",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[0]["down"], 120.5)

        history_path = self.state / "history.json"
        self.assertTrue(history_path.is_file())
        self.assertEqual(stat.S_IMODE(history_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)
        self.assertFalse(list(self.state.glob(".history.*")))

        reread = self.run_helper("history-read")
        self.assertEqual(reread.returncode, 0, reread.stderr)
        self.assertEqual(json.loads(reread.stdout), json.loads(result.stdout))

    def test_history_symlink_is_never_followed_and_is_replaced(self):
        self.initialize()
        victim = self.root / "victim"
        victim.write_text("do not replace\n")
        history_path = self.state / "history.json"
        history_path.symlink_to(victim)

        rejected = self.run_helper("history-read")
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(victim.read_text(), "do not replace\n")

        replaced = self.run_helper(
            "history-add",
            "--timestamp", "2000",
            "--down", "10",
            "--up", "5",
        )
        self.assertEqual(replaced.returncode, 0, replaced.stderr)
        self.assertFalse(history_path.is_symlink())
        self.assertTrue(history_path.is_file())
        self.assertEqual(victim.read_text(), "do not replace\n")

    def test_fifo_and_oversized_history_fail_without_blocking(self):
        self.initialize()
        history_path = self.state / "history.json"
        os.mkfifo(history_path, 0o600)
        fifo_result = self.run_helper("history-read", timeout=1)
        self.assertNotEqual(fifo_result.returncode, 0)

        history_path.unlink()
        history_path.write_bytes(b"[" + b" " * (64 * 1024) + b"]")
        oversized_result = self.run_helper("history-read", timeout=1)
        self.assertNotEqual(oversized_result.returncode, 0)
        self.assertIn("exceeds", oversized_result.stderr)

    def test_lock_rejects_symlinks_fifos_and_hardlinks_without_truncation(self):
        self.initialize()
        victim = self.root / "lock-victim"
        victim.write_text("preserve me\n")
        lock_path = self.state / "speedtest.lock"
        lock_path.symlink_to(victim)

        symlink_result = self.run_helper("lock", "--", "/usr/bin/true")
        self.assertNotEqual(symlink_result.returncode, 0)
        self.assertEqual(victim.read_text(), "preserve me\n")

        lock_path.unlink()
        os.mkfifo(lock_path, 0o600)
        fifo_result = self.run_helper("lock", "--", "/usr/bin/true", timeout=1)
        self.assertNotEqual(fifo_result.returncode, 0)

        lock_path.unlink()
        victim.chmod(0o600)
        os.link(victim, lock_path)
        hardlink_result = self.run_helper("lock", "--", "/usr/bin/true")
        self.assertNotEqual(hardlink_result.returncode, 0)
        self.assertEqual(victim.read_text(), "preserve me\n")

    def test_lock_descriptor_spans_exec_and_busy_ok_skips(self):
        holder = subprocess.Popen(
            [str(HELPER), "lock", "--", sys.executable, "-c", "import time; time.sleep(5)"],
            env=self.environment,
        )
        try:
            for _ in range(100):
                if (self.state / "speedtest.lock").exists():
                    busy = self.run_helper("lock", "--", "/usr/bin/true")
                    if busy.returncode == 75:
                        break
                time.sleep(0.02)
            else:
                self.fail("lock holder never became observable")

            skipped = self.run_helper("lock", "--busy-ok", "--", "/usr/bin/true")
            self.assertEqual(skipped.returncode, 0, skipped.stderr)
            self.assertIn("skipped", skipped.stdout)
            self.assertEqual(stat.S_IMODE((self.state / "speedtest.lock").stat().st_mode), 0o600)
        finally:
            holder.terminate()
            holder.wait(timeout=2)

    def test_state_directory_chain_rejects_symlinks(self):
        target = self.root / "redirected"
        target.mkdir()
        linked = self.root / "linked"
        linked.symlink_to(target, target_is_directory=True)
        self.environment["MELONAMIN_FAST_STATE_DIR"] = str(linked / "melonamin.fast")

        result = self.run_helper("history-read")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr)
        self.assertFalse((target / "melonamin.fast").exists())

        self.environment["MELONAMIN_FAST_STATE_DIR"] = "/"
        root_result = self.run_helper("history-read")
        self.assertNotEqual(root_result.returncode, 0)
        self.assertIn("filesystem root", root_result.stderr)

    def test_runtime_sources_do_not_reopen_state_temporary_files(self):
        panel = (PLUGIN_DIR / "Panel.qml").read_text()
        scheduled = (PLUGIN_DIR / "run-scheduled-test").read_text()
        speedtest = (PLUGIN_DIR / "run-speedtest").read_text()
        interactive = (PLUGIN_DIR / "run-interactive-test").read_text()

        self.assertNotIn("FileView", panel)
        self.assertNotIn("historyPath", panel)
        self.assertNotIn("mktemp", scheduled)
        self.assertNotIn("mktemp", speedtest)
        self.assertNotIn("speedtest.lock", scheduled)
        self.assertNotIn("speedtest.lock", speedtest)
        self.assertNotIn("speedtest.lock", interactive)
        self.assertNotIn("jq", scheduled)


if __name__ == "__main__":
    unittest.main()
