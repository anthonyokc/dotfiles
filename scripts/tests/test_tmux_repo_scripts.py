import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]


class TmuxRepoScriptTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="tmux-repo-tests-")
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        (self.home / "scripts").symlink_to(SCRIPTS, target_is_directory=True)
        (self.home / "code").mkdir()
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            # Exercise macOS's system tools and Bash, without Homebrew nproc.
            "PATH": f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "MULTIPLEXER": "tmux",
            "HERDR_SOCKET_PATH": "",
        }
        fd = shutil.which("fd")
        self.assertIsNotNone(fd, "fd is required by the repository picker")
        (self.bin / "fd").symlink_to(fd)
        self.stub("gum", 'cat >"$HOME/choices"\n'
                  'if [[ -z "${PICK:-}" ]]; then exit 1; fi\n'
                  'printf "%s\\n" "$PICK"\n')
        self.stub("sesh", 'if [[ "$1" == connect ]]; then\n'
                  '  printf "%s\\n" "$2" >"$HOME/connected"\nfi\n')
        self.stub("gh", 'echo "Unexpected GitHub operation" >&2\nexit 99\n')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + body)
        path.chmod(0o755)

    def run_script(self, name, *arguments):
        return subprocess.run(
            ["/bin/bash", str(SCRIPTS / name), *arguments],
            env=self.env, cwd=self.home, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=15,
        )

    def test_picker_preserves_spaces_and_quotes_in_repo_paths(self):
        repo = self.home / "code" / "owner" / "repo's space"
        repo.mkdir(parents=True)
        self.env["PICK"] = " repo's space"
        result = self.run_script("find_repo_directory_and_connect_with_sesh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "connected").read_text().strip(), str(repo))

    def test_picker_expands_bare_repositories(self):
        repo = self.home / "code" / "owner" / "bare repo"
        repo.mkdir(parents=True)
        subprocess.run(["/usr/bin/git", "init", "--bare", str(repo / ".git")],
                       env=self.env, check=True, capture_output=True)
        for name in ["main", "feature"]:
            (repo / name).mkdir()
        self.env["PICK"] = " bare repo/main"
        result = self.run_script("find_repo_directory_and_connect_with_sesh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "connected").read_text().strip(), str(repo / "main"))
        choices = (self.home / "choices").read_text().splitlines()
        self.assertLess(choices.index(" bare repo/main"), choices.index(" bare repo/feature"))

    def test_empty_picker_can_be_cancelled(self):
        result = self.run_script("find_repo_directory_and_connect_with_sesh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / "connected").exists())

    def test_creator_help_loads_all_helpers(self):
        result = self.run_script("create_new_repo_and_connect_with_sesh", "--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--local-only", result.stdout)

    def test_creator_supports_system_bash_without_github_access(self):
        result = self.run_script(
            "create_new_repo_and_connect_with_sesh", "--non-interactive",
            "--owner", "MixedCase", "--name", "local-test", "--layout", "normal",
            "--template", "NONE", "--local-only",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        repo = self.home / "code" / "mixedcase" / "local-test"
        self.assertTrue((repo / ".git").is_dir())
        self.assertIn(str(repo), result.stdout)
        self.assertFalse((self.home / "connected").exists())

    def test_creator_normalizes_interactively_selected_owner(self):
        self.stub("gh", 'if [[ "$*" == "api user --jq .login" ]]; then\n'
                  '  echo MixedCase\nelse\n  exit 99\nfi\n')
        self.env["PICK"] = "mixedcase"
        result = self.run_script(
            "create_new_repo_and_connect_with_sesh", "--name", "interactive-test",
            "--layout", "normal", "--template", "None", "--local-only", "--no-connect",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mixedcase", (self.home / "choices").read_text().splitlines())
        self.assertTrue((self.home / "code/mixedcase/interactive-test/.git").is_dir())


if __name__ == "__main__":
    unittest.main()
