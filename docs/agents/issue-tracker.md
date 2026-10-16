# Issue tracker: Local Markdown

Issues and specs live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`.
- Specs: `.scratch/<feature-slug>/spec.md`.
- Implementation tickets: `.scratch/<feature-slug>/issues/<NN>-<slug>.md`,
  numbered from `01`, with one file per ticket.
- Record triage state in a `Status:` line near the top of each ticket.
  Use the role strings in `docs/agents/triage-labels.md`.
- Append comments and conversation history under `## Comments`.

## Publishing and fetching

When a skill says "publish to the issue tracker", create the appropriate
spec or ticket file using the conventions above.

When a skill says "fetch the relevant ticket", read its referenced file.
Resolve a ticket number within its feature directory.

## Wayfinding operations

Used by `/wayfinder`.

- Map: `.scratch/<effort>/map.md`, containing Notes,
  Decisions-so-far, and Fog.
- Child ticket: `.scratch/<effort>/issues/NN-<slug>.md`.
  Record its question in the body and its type in a `Type:` line:
  `research`, `prototype`, `grilling`, or `task`.
- Blocking: record `Blocked by: NN, NN` near the top.
  A ticket is unblocked when every listed ticket is `resolved`.
- Frontier: scan tickets in number order for the first open,
  unblocked, unclaimed ticket.
- Claim: set `Status: claimed` and save before starting work.
- Resolve: append the answer under `## Answer`, set `Status: resolved`,
  then append a brief finding and a relative link to the map's
  Decisions-so-far section.

Wayfinding uses `claimed` and `resolved` as lifecycle statuses.
Triage uses the statuses defined in `docs/agents/triage-labels.md`.
