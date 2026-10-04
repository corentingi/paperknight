# ADR-0001: Record decisions as ADRs in `docs/adr/`

- Date: 2026-10-04
- Status: accepted

## Context
The project is built in short iterations, partly by an AI agent that starts each
session without memory. Choices made early (fork base, data format, test
setup) must be recoverable later without re-deriving them.

## Options
### A. ADRs in the repository (`docs/adr/`)
- Pros: versioned with the code, reviewable in diffs, readable by any contributor.
- Cons: some writing overhead.

### B. Notes in an issue tracker or the commit log only
- Pros: no extra files.
- Cons: scattered; commit messages don't capture rejected options.

## Decision
A. One short Markdown file per costly-to-reverse decision, numbered, using
`0000-template.md`. Low-stakes, easily reversed choices are not recorded.

## Consequences
- Reviews can check code against the recorded decisions.
- A decision is changed by writing a new ADR that supersedes the old one, never
  by silently editing it.
