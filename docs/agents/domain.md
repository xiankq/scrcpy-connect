# Domain docs

## Layout

This repository uses a single context:

- `GLOSSARY.md` at the repository root defines domain vocabulary.
- `docs/adr/` contains architectural decision records.

## Before exploring

Read `GLOSSARY.md` and ADRs relevant to the area being explored.

If these documents do not exist, proceed silently. The `/domain-modeling`
skill creates them when terminology or decisions are resolved.

## Vocabulary

Use glossary terms in issue titles, proposals, hypotheses, and tests.
Follow any explicitly preferred terms and avoided synonyms.

If a needed concept is absent, reconsider whether it belongs to the
domain. Record genuine vocabulary gaps for `/domain-modeling`.

## Decision conflicts

Explicitly identify any proposal that contradicts an existing ADR.
Cite the ADR and explain why the decision should be reconsidered.
