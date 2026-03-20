#!/usr/bin/env bash
set -euo pipefail

source "$HOME/scripts/helpers/ensure_ssh_key_loaded.sh"

# Examples of call:
# git-clone-bare-for-worktrees git@github.com:name/repo.git
# => Clones to a /repo directory
#
# git-clone-bare-for-worktrees git@github.com:name/repo.git my-repo
# => Clones to a /my-repo directory

usage() {
    echo "Usage: $0 [--upstream=<upstream-url>] <repo-url> [<directory-name>]"
    exit 1
}

upstream=""
while [[ "$1" =~ ^-- ]]; do
    case "$1" in
        --upstream=*)
            upstream="${1#*=}"
            shift
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "$1" ]; then
    usage
fi

url=$1
basename=${url##*/}
name=${2:-${basename%.*}}

if [[ "$url" == git@*:* || "$url" == ssh://* ]]; then
    ensure_github_ssh_key_loaded
fi

mkdir $name
cd "$name"

# Moves all the administrative git files (a.k.a $GIT_DIR) under .bare directory.
#
# Plan is to create worktrees as siblings of this directory.
# Example targeted structure:
# .bare
# main
# new-awesome-feature
# hotfix-bug-12
# ...
git clone --bare "$url" .git

# Explicitly sets the remote origin fetch so we can fetch remote branches
git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
git config core.logallrefupdates true
git fetch origin # Gets all branches from origin

if [ -n "$upstream" ]; then
    echo "Adding upstream remote..."
    git remote add upstream "$upstream"
    git fetch upstream
fi

# Need to update all local branches to track the remote branches
# See: https://stackoverflow.com/questions/54367011/git-bare-repositories-worktrees-and-tracking-branches
git for-each-ref --format='%(refname:short)' refs/heads | while read branch; do
    git branch --set-upstream-to=origin/"$branch" "$branch"
done

# Create initial worktree for the default branch
default_branch=$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')

# If we could determine the default branch, create its worktree
if [ -n "$default_branch" ] && [ "$default_branch" != "(unknown)" ]; then
    remote=$(if [ -n "$upstream" ]; then echo "upstream"; else echo "origin"; fi)

    echo "Creating initial worktree for the default branch ($remote/$default_branch)..."
    git worktree add -B "$default_branch" "$default_branch" "${remote}/$default_branch"
else
    # Default branch is unknown, create a main branch and worktree
    echo "Default branch is unknown, creating main branch and worktree..."
    git worktree add -B main main origin/main || git worktree add -B main main
fi
