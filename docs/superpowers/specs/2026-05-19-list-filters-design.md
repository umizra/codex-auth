# codex-auth List Filters Design

## Goal

Add a reusable account filtering layer for `codex-auth list` and `codex-auth list --live` so operators can quickly hide exhausted accounts, find usable accounts, and inspect error states without making the normal command slower.

## Scope

This design covers filtering for account list display only. It does not change login, daemon switching, account refresh semantics, or registry storage.

## User-Facing Behavior

Plain `codex-auth list` continues to show all accounts by default. This preserves script compatibility and keeps exhausted or broken accounts visible unless the user explicitly filters them.

New CLI filters:

- `--nonzero`: hide accounts where the displayed usage score is exhausted.
- `--available`: show accounts that appear usable, with a usage score above the default switch threshold and no known usage error.
- `--min <percent>`: show accounts whose usage score is greater than or equal to the provided percentage.
- `--errors`: show only accounts with an error-like usage state, such as `401 token_expired`, `TimedOut`, missing usage, or refresh failure.
- `--query <text>`: match account email, alias, or display name.

Filters are composable. For example, `codex-auth list --available --query outlook --skip-api` shows cached usable Outlook accounts without forcing live API refresh.

## Live TUI Behavior

`codex-auth list --live` starts with no filters by default. The same filter model is applied to the live row set.

Interactive hotkeys:

- `0`: toggle hiding exhausted accounts.
- `a`: toggle available-only mode.
- `e`: toggle errors-only mode.
- `/`: edit text search.
- `c`: clear filters.

The live header/status line shows active filters, for example:

```text
Filter: available | min >= 10 | query: outlook
```

If filters remove every row, the UI shows a clear empty state. In live mode, the empty state should mention `c` to clear filters.

## Filter Model

Filtering should live in a small shared module, independent of rendering. The module should accept:

- Account record.
- Optional usage override.
- Active account metadata.
- Filter options.

It should return whether the account should be displayed.

The filter model should not know about terminal rendering, key handling, API refresh, or registry persistence.

## Usage Score Rules

The filter engine should use the same score concept already used by auto-switch selection: the best available current usage signal for the account.

Rules:

- `--nonzero` removes accounts with score `<= 0`.
- `--available` removes accounts with score `<= 10` or an error-like usage state.
- `--min <percent>` removes accounts with score below the provided value.
- `--errors` keeps only error-like or unknown usage states.
- Unknown usage remains visible by default.

The active account is not special-cased for default list output. Explicit filters may hide it.

## Performance

Filtering is local and must not trigger API calls by itself.

Existing API flags retain their meaning:

- Default behavior may refresh usage according to existing list rules.
- `--skip-api` must stay fast and filter cached data only.
- `--api` can force refresh, then apply filters.

Live mode may keep refreshing in the background, but each filter toggle should re-render from already loaded data immediately.

## Error Handling

Invalid filter input should fail early with a usage error:

- `--min` must require a value.
- `--min` must accept integers from `0` through `100`.
- Duplicate exclusive filters should be accepted if harmless, but conflicting filters such as `--available --errors` should return a clear usage error unless we intentionally define intersection behavior.

Recommended behavior: treat `--available --errors` as invalid, because it almost always means the user asked for two mutually exclusive views.

## Tests

Add unit tests for:

- Score threshold matching.
- Exhausted-account hiding.
- Available-only behavior.
- Error-only behavior.
- Query matching by email, alias, and display name.
- Empty result behavior.
- CLI parser validation for `--min`, `--query`, and conflicting filters.

Add integration-style tests for:

- `list --skip-api --nonzero`.
- `list --skip-api --available`.
- `list --skip-api --errors`.
- `list --skip-api --query <text>`.

Live TUI tests should focus on filter state transitions and row filtering. Full terminal rendering snapshots are optional unless existing tests already use that pattern.

## Implementation Phases

Phase 1:

- Add shared filter types and matching logic.
- Add CLI parser flags.
- Apply filters to normal `list`.
- Add unit and command tests.

Phase 2:

- Add filter state to live list runtime.
- Add hotkeys.
- Render active filter summary.
- Add live state tests.
