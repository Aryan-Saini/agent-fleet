---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "nothing to run. Interview and docs discipline, no scripts or credentials"
---

> Vendored from Matt Pocock's [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs), MIT licensed (see `LICENSE` in this folder). Local changes: the `metadata` block, and it reads its two sibling skills by relative path so it works in harnesses without a Skill tool.

Read `../grilling/SKILL.md` and `../domain-modeling/SKILL.md`, and follow both.
