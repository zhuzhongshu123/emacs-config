#!/usr/bin/env python3
"""Exercise native emacsclient auto-start with an isolated Emacs daemon."""

import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time
import unittest


REPO = Path(__file__).resolve().parents[1]


class ClientLauncherSmoke(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="emacs-client-launcher-")
        self.root = Path(self.temp.name)
        (self.root / "bin").mkdir()
        self.launcher = self.root / "bin/emacs-tui"
        shutil.copy2(REPO / "bin/emacs-tui", self.launcher)
        self.emacsclient = shutil.which("emacsclient")
        self.env = os.environ.copy()
        # Native emacsclient invokes `emacs --daemon=...`. Redirect only the
        # test process's executable lookup to this isolated configuration.
        real_emacs = shutil.which("emacs")
        executable = self.root / "bin/emacs"
        executable.write_text(f'#!/bin/sh\nexec "{real_emacs}" --init-directory "{self.root}" "$@"\n')
        executable.chmod(0o755)
        self.env.update(PATH=str(self.root / "bin") + os.pathsep + self.env["PATH"],
                        TERM="xterm-256color")
        self.env.pop("COLORTERM", None)
        self.socket = str(self.root / ".cache/server/tui")
        self.env["EMACS_SOCKET_NAME"] = self.socket
        shutil.copy2(REPO / "early-init.el", self.root / "early-init.el")
        os.symlink(REPO / "modules", self.root / "modules", target_is_directory=True)
        os.symlink(REPO / "elpa", self.root / "elpa", target_is_directory=True)
        (self.root / "init.el").write_text(f'(load "{REPO}/init.el" nil t)\n')

    def tearDown(self):
        subprocess.run(
            [self.emacsclient, "-s", self.socket, "-a", "false", "-e", "(kill-emacs)"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10,
        )
        self.temp.cleanup()

    def eval(self, expression):
        return subprocess.run(
            [self.emacsclient, "-s", self.socket, "-a", "false", "-e", expression],
            capture_output=True, text=True, check=True, timeout=10,
        ).stdout.strip()

    def ensure_daemon(self):
        subprocess.run(
            [self.emacsclient, "-s", self.socket, "-a", "", "-e", "t"],
            env={**self.env, "COLORTERM": "truecolor"},
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            check=True, timeout=20,
        )

    def test_native_auto_start_reuse_and_restart(self):
        self.ensure_daemon()
        first_pid = self.eval("(emacs-pid)")
        self.ensure_daemon()
        self.assertEqual(self.eval("(emacs-pid)"), first_pid)
        self.assertEqual(self.eval('(getenv "COLORTERM")'), '\"truecolor\"')
        self.eval("(kill-emacs)")
        self.ensure_daemon()
        self.assertNotEqual(self.eval("(emacs-pid)"), first_pid)

    def test_terminal_client_keeps_daemon_and_read_only_file(self):
        self.ensure_daemon()
        first_pid = self.eval("(emacs-pid)")
        file = self.root / "reader.txt"
        file.write_text("unique-reader-content\n")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        client = subprocess.Popen([str(self.launcher), str(file)], env=self.env,
                                  stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        try:
            output = b""
            deadline = time.monotonic() + 10
            while b"unique-reader-content" not in output and time.monotonic() < deadline:
                if select.select([master], [], [], 1)[0]:
                    output += os.read(master, 65536)
            self.assertIn(b"unique-reader-content", output)
            state = self.eval(
                f'(with-current-buffer (get-file-buffer "{file}") '
                '(list buffer-read-only (buffer-modified-p)))'
            )
            self.assertEqual(state, "(t nil)")
            os.write(master, b"\x18\x03")
            self.assertEqual(client.wait(timeout=10), 0)
            self.assertEqual(self.eval("(emacs-pid)"), first_pid)
            self.assertEqual(self.eval(f'(and (get-file-buffer "{file}") t)'), "t")
        finally:
            if client.poll() is None:
                client.terminate()
                client.wait(timeout=5)
            os.close(master)


if __name__ == "__main__":
    unittest.main()
