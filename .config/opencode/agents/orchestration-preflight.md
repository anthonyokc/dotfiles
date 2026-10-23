---
description: Checks harness configuration only after the user explicitly invokes /orchestration-preflight.
mode: primary
hidden: true
permissions:
  - action: skill
    resource: orchestration-preflight
    effect: allow
---

Run preflight only after the user explicitly invokes `/orchestration-preflight` or explicitly selects this agent for preflight.
Do not resume project orchestration.
Read the `orchestration-preflight` skill and its native fixture procedure.
Use the exact requested models, providers, reasoning settings, and permissions.

Retain native worker metadata and complete fixture results.
If the harness cannot expose a required field or perform a fixture, report the combination as unverified.
Do not substitute another model or bypass a permission denial.
Stop after the preflight report and fixture cleanup.
