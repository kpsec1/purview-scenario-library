# Contributing / authoring guide

This repo is built one small, self-contained **fragment** at a time so delivery is continuous and
work survives interruptions. The authoritative workflow lives in [`AGENTS.md`](AGENTS.md); this is
the short version.

## The loop

1. Read [`PROGRESS.md`](PROGRESS.md). Pick the top unblocked `TODO`.
2. Do **exactly one** fragment to definition-of-done (`AGENTS.md` §9).
3. Update `PROGRESS.md` (move to DONE with commit hash + date; add follow-ups; note blockers).
4. Commit with a conventional-commit message. Then stop / re-enter.

## Fragment = one of

- A scenario reaching definition-of-done (docs + code + four-lens review), or
- A scoped sub-task (e.g. a cross-cutting doc, or `-part1/-part2/-part3` of a large scenario).

Never batch multiple scenarios into one commit. Breadth comes from many small commits.

## Non-negotiables

- **Ground facts in Microsoft Learn.** No invented cmdlets, blade paths, or licensing claims.
- **Code is author-only.** It is written to run in the *buyer's* tenant. Never execute it against
  a live tenant from this repo. Every script has a `-WhatIf` / dry-run path and a validation script.
- **No secrets.** Parameterize everything; read tenant IDs and creds from parameters/config.
- **Uniform format.** Every scenario README follows the identical skeleton in `AGENTS.md` §4.
- **Four-lens review** (Red / Blue / CISO / MS Product Owner) is part of done, not optional.

## Commit message convention

```
feat(dlp): add PCI Teams exfiltration-block scenario
docs(cross-cutting): add Purview licensing matrix
fix(insider-risk): correct policy indicator names per MS Learn
```
