#!/usr/bin/env python3
"""Select existing Rex sessions and local projects without tmux or sesh."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def rex(*args):
    binary = shutil.which("rex")
    if not binary:
        binary = str(Path.home() / "Library/Application Support/com.superlogical.rex/"
                     "RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")
    result = subprocess.run([binary, *args], check=True, text=True, capture_output=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def project_paths():
    root = Path.home() / "code"
    if root.is_dir():
        for owner in sorted(root.iterdir()):
            if not owner.is_dir() or owner.name.startswith("."):
                continue
            for repo in sorted(owner.iterdir()):
                if not repo.is_dir() or repo.name.startswith("."):
                    continue
                # Bare repositories keep their usable checkouts one level deeper.
                if (repo / ".bare").exists() or (repo / ".git/worktrees").is_dir():
                    for worktree in sorted(repo.iterdir()):
                        if worktree.is_dir() and not worktree.name.startswith("."):
                            yield worktree.resolve()
                else:
                    yield repo.resolve()
    if shutil.which("zoxide"):
        result = subprocess.run(["zoxide", "query", "--list"], text=True,
                                capture_output=True, check=True)
        for value in result.stdout.splitlines():
            path = Path(value)
            if path.is_dir():
                yield path.resolve()


def connect(path):
    path = Path(path).expanduser().resolve(strict=True)
    if not path.is_dir():
        raise ValueError(f"Not a directory: {path}")
    if (path / ".bare").exists() or (path / ".git/worktrees").is_dir():
        for branch in ("main", "master"):
            if (path / branch).is_dir():
                path = path / branch
                break
        else:
            raise ValueError(f"Select a checkout inside the bare repository: {path}")
    try:
        label = str(path.relative_to(Path.home() / "code"))
    except ValueError:
        label = str(path)
    if len(label) > 128:
        raise ValueError("The project path exceeds Rex's 128-character limit for labels")
    sessions = rex("ls", "--json")["sessions"] or []
    matches = [session for session in sessions if session.get("label") == label]
    if len(matches) > 1:
        raise ValueError(f"Several Rex sessions use the label: {label}")
    session = matches[0] if matches else rex("new", label, "--cwd", str(path), "--json")
    rex("do", "session.select", "session_id=" + session["session_id"])


def pick(include_projects):
    choices = {}
    for session in rex("ls", "--json")["sessions"] or []:
        choices[f"Session: {session.get('label', '')} [{session['session_id'][-8:]}]"] = (
            "session", session["session_id"])
    if include_projects:
        for path in dict.fromkeys(project_paths()):
            choices[f"Directory: {path}"] = ("path", str(path))
    if not choices:
        return
    fzf = shutil.which("fzf")
    if not fzf:
        raise RuntimeError("fzf is required for the Rex project picker")
    result = subprocess.run(
        [fzf, "--no-sort", "--border", "--prompt", "Rex > ", "--header",
         "Select a session or directory. Escape cancels."],
        input="\n".join(choices), text=True, stdout=subprocess.PIPE)
    if result.returncode in (1, 130):
        return
    result.check_returncode()
    kind, target = choices[result.stdout.rstrip("\n")]
    if kind == "session":
        rex("do", "session.select", "session_id=" + target)
    else:
        connect(target)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "pick"
    if mode in ("pick", "sessions"):
        pick(mode == "pick")
    elif mode == "connect" and len(sys.argv) == 3:
        connect(sys.argv[2])
    elif mode in ("clone", "create"):
        scripts = {
            "clone": "find_and_clone_repo_and_connect_with_sesh",
            "create": "create_new_repo_and_connect_with_sesh",
        }
        env = os.environ.copy()
        env["PATH"] = str(Path(__file__).parent / "compat") + os.pathsep + env["PATH"]
        subprocess.run(["bash", str(Path.home() / "scripts" / scripts[mode])],
                       env=env, check=True)
    else:
        raise ValueError("Expected pick, sessions, clone, create, or connect DIRECTORY")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Rex project picker failed: {error}", file=sys.stderr)
        if sys.stdin.isatty():
            input("Press Enter to close.")
        sys.exit(1)
