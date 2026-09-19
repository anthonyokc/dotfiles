---
description: Review atomic Conventional Commit messages interactively
subtask: true
model: cursor/composer-2.5
---
Use the `atomic-conventional-commits` skill.

Inspect the current staged and unstaged changes and the recent commit history. Propose the atomic commits and their messages.

Do not stage files, create commits, or modify the worktree.

Run this approval loop:

1. Show the complete numbered list of proposed commits. For each commit, show its message and a concise change summary.
2. Use the `question` tool to ask: "Approve these commit messages? Choose Yes or No, or type feedback."
3. Offer `Yes` and `No` as the predefined choices. Treat any custom response as revision feedback.
4. If the user chooses `Yes`, show the approved list and finish.
5. If the user chooses `No`, stop without changing anything.
6. If the user provides feedback, revise the proposals, show the complete revised list, and ask the same question again.
7. Repeat until the user chooses `Yes` or `No`. Do not infer approval from feedback or silence.

Additional context from the user:
$ARGUMENTS
