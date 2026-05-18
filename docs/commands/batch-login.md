# `codex-auth batch-login`

## Usage

```shell
codex-auth batch-login <path> [--line <n>|--from-line <n>] [--device-auth]
```

## Behavior

- Reads an accounts file with colon-separated lines.
- Selects every usable line by default, just one 1-based file line with `--line`, or every usable line starting at a 1-based file line with `--from-line`.
- Runs a fresh `codex login` or `codex login --device-auth` process for each selected account.
- Verifies that the resulting auth email matches the selected line before syncing the account into the registry.
- Saves the registry after each successful login.

## Notes

- The file format is the same five-field format used by the external automation flow.
- Lines starting with `#` and blank lines are ignored.
- `--line` uses the source file line number, starting at 1.
- `--from-line` is useful for resuming from a specific file row after earlier rows were already handled.
- If any selected account fails, the command logs the failure and keeps moving through the remaining lines before returning a batch failure status.
