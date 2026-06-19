---
name: grill-with-docs
description: >-
  A relentless interview to sharpen a plan or design that ALSO maintains the
  project's docs as it goes — sharpening fuzzy language into CONTEXT.md and
  recording hard-to-reverse decisions as ADRs. Use when the user wants to grill,
  stress-test, pressure-test, pre-mortem, or "poke holes in" a plan AND wants the
  domain model / decision records kept current — especially anything touching
  networking, server authority, components, content (.tres), bots, or
  persistence. For grilling without doc side-effects, use grill-me.
disable-model-invocation: true
---

Run a `/grilling` session, using the `/domain-modeling` skill.

Grilling supplies the interview loop and the server-authority invariants;
domain-modeling supplies the glossary (`CONTEXT.md`) and decision-record (ADR)
discipline. Update both inline as terms crystallise and decisions land — don't
batch.
