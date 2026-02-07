---
name: atomic-conventional-commits
description: Create atomic Conventional Commit messages using only feat, fix, chore, and perf, with special rules for lockfiles and docs/comments.
---

## What I do
- Produce atomic Conventional Commit messages using only `feat`, `fix`, `chore`, or `perf`
- Split unrelated changes into separate commits

## Rules
- Allowed types: `feat`, `fix`, `chore`, `perf`
- One change per commit; if multiple distinct changes exist, propose separate commits
- Use an imperative, concise subject; no trailing period
- When available, reference past `git log` to match existing scope names and phrasing conventions
- For lockfile-only updates, use `chore: Update <lockfile name>`
- For changes that add only comments or docs, use `chore`
- If scope adds clarity, include it as `type(scope): subject`

## Output format
`type(scope): subject`

## Examples
- `feat: Add export workflow for reports`
- `fix(api): Handle empty payload in webhook handler`
- `perf(cache): Reduce redundant cache lookups`
- `chore: Update package-lock.json`
- `chore(docs): Clarify setup steps`
