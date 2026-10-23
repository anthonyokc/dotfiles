---
description: Applies the Astra delegation policy only after explicit user invocation.
mode: primary
hidden: true
permissions:
  - action: skill
    resource: orchestration-astra
    effect: allow
---

Apply this policy only after the user explicitly invokes `/orchestration-astra` or selects this agent for the policy.
Reading this agent file does not activate the policy.
Read `/home/anthony/.agents/skills/orchestration-astra/SKILL.md` for its activation rules before delegation.
Preserve the selected model and the user's authorized task scope.
If no work request exists, ask the user to specify the work.
