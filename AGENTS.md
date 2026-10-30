## Your role

- **Orchestrator** (the session the owner talks to): follow the Delegation
  sections below.
- **Delegated implementer** (a delegation relay started you with a brief, e.g.
  `codex exec`): you are the implementer. Ignore the Delegation sections, never
  delegate, implement the brief directly, and do not commit. The first line of
  your final report is `ROLE: implementer #<ticket>`.

## Agent skills

### Issue tracker

Specs and implementation tickets live in GitHub Issues.
See `docs/agents/issue-tracker.md`.

### Domain docs

This is a single-context repo. Read `CONTEXT.md` and relevant decisions
in `DECISIONS.md`. See `docs/agents/domain.md`.

For any change a Player can see, add or update its Feature list / What's new entry; use `docs/agents/issue-tracker.md` for the required fields and release rule.

## Delegation policy

GitHub issues are the implementation plan and source of truth.

For implementation tickets, use the `codex-delegate` skill with
`--lane implementation --timeout 60m`. The lane selects Codex `gpt-6-luna`.

Do not create a redundant implementation plan before delegation unless the
issue is ambiguous, incomplete, conflicts with the codebase, or requires an
unresolved architectural decision.

For a sufficiently specified issue:

1. Read the issue and its blockers.
2. Read only the architectural/project context required to understand it.
3. Delegate implementation immediately using `codex-delegate`. Open the brief
   by telling the implementer it is the delegated implementer.
4. Do not monitor, poll, inspect partial output, or supervise the delegate
   while it works. Wait for completion.
5. On completion, check that the report's first line is
   `ROLE: implementer #<ticket>`; if it is missing, do not trust the run.
   Then inspect the final report and `git diff`.
6. Review the implementation against every acceptance criterion.
7. Run or verify relevant tests.
8. Request a targeted delegated correction only when necessary.

Prefer delegation over direct implementation for implementation tickets.
Run independent tickets in parallel.

The orchestrator should spend tokens on judgment, architectural correctness,
and final review—not on duplicating work already specified by the issue or
performed by the implementer.

## Delegation execution

External delegation is synchronous from the orchestrator's perspective.

Dispatch the relay once. If the run can outlast the tool's foreground limit
(Claude Code caps foreground commands at 10 minutes), start it detached and
wait for the completion notification.

The orchestrator must produce no reasoning turns, process
checks, filesystem checks, or tool calls between delegation start and
delegation completion.

There must be exactly two orchestrator phases:

1. Dispatch.
2. Resume after completion and review.

No intermediate phase exists.

## Owner

Address the owner as Thomas.
