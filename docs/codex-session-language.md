# Codex session management and language tooling

Assessed on 2026-11-03 against installed `codex-cli 0.160.0` and
`pyright 1.1.414`. This is a branch-local assessment of the corresponding
CODEX-TODO item; integration into the default branch is pending.

## Session workflows

Use the existing launchers and native commands. The
[official CLI reference](https://learn.chatgpt.com/docs/cli/reference)
documents the session commands below; their help was also checked locally.
Use a session UUID when possible to avoid ambiguous names.

| Existing workflow | Codex equivalent or limitation |
| --- | --- |
| `bobtask resume`, session selection | `codexl` / `codexla` already call native `resume` / `resume --all`; `codex resume <UUID>` selects directly. Native filtering is by working directory, unlike the repository scope of `bobtask -c` and `clauderm`. |
| `clauderm`, `bobtask rm` | `codex delete <UUID>` permanently deletes a session, with native confirmation. No extra deletion script is needed. |
| Hide without deleting history | `codex archive <UUID>`; restore with `codex unarchive <UUID>`. |
| Continue a separate history | `codex fork <UUID>`; this retains prior context and is different from a fresh-context handoff. |
| `bobtask list`, multi-select cleanup | Existing native pickers cover interactive discovery. No equivalent to Bob's exact tabular, repository-scoped batch workflow was established; no private database parser is added. |
| `bobtask mv` | No supported in-place history/workspace migration command was established. `--cd` selects a working root; it is not evidence of rewriting saved history or quoted paths. |

For transcript and fresh-context workflows, the
[official slash-command guide](https://learn.chatgpt.com/docs/cli/slash-commands)
documents `/export session.md` (Markdown export after the turn finishes),
`/rename <name>` (name a chat), and `/new` (start a fresh chat).
Export is a practical text alternative to `bobtask dump`, not its raw JSON
database format. For `bobtask handoff`, invoke the existing `handoff` skill to
write `.agent-handoff.md`, then use `codex new` with a prompt to read that note.
The existing launch/delegation commands remain responsible for pane and worktree
selection. No Bob cost-limit continuation or clipboard automation is implied.

## Python diagnostics and navigation

The repository installs Claude's `pyright-lsp` plugin in
`scripts/install-claude-plugins`; `scripts/install-nix-tools` reuses an existing
`pyright-langserver` or installs the Pyright package. Claude's
[plugin manifest reference](https://code.claude.com/docs/en/plugins-reference#lspservers)
defines its `lspServers` integration. That Claude configuration is not portable
to Codex.

For Codex, reuse the project's existing check command and Python environment.
When Pyright is available, run `pyright --project .` from the project root, or
`pyright --outputjson path/to/file.py` for structured diagnostics. The
[Pyright CLI reference](https://github.com/microsoft/pyright/blob/main/docs/command-line.md)
documents these options. This provides type diagnostics through the shell;
it does not provide LSP definition, reference, hover, or rename operations.
Use the editor's existing language tooling for those operations. Text searches
with `rg` are useful but do not establish semantic references.

No supported native LSP server configuration was found in the
[Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
or installed CLI help/features. A temporary config containing
`[lsp_servers.pyright]` was rejected by `codex --strict-config --no-daemon`
with `unknown configuration field lsp_servers` (exit 1). This rules out that
setting, rather than proving that every possible integration is unavailable.
The documented `mcp_servers` interface speaks MCP; pointing it directly at
`pyright-langserver --stdio` would not adapt LSP to MCP. No unverified adapter,
invented setting, or duplicate package installation is introduced.

## Verification and limits

All CLI probes used temporary `HOME` and `CODEX_HOME`; no real session was
archived, deleted, or resumed. Help checks covered `resume`, `fork`, `archive`,
`unarchive`, and `delete`; the feature list was inspected. Codex warned that
helper PATH aliases cannot be created under `/tmp`, but returned help normally.
The initial strict-config probe with `features list` was rejected because that
subcommand does not support strict mode; the interactive invocation above
reached configuration validation without starting a model turn.

Pyright was run on a temporary file containing `value: int = "wrong"`:
JSON output reported one `reportAssignmentType` error and exit 1, as expected.
Authenticated TUI operations, slash commands, live LSP navigation, and automatic
agent selection of diagnostics were not exercised. Slash-command behavior above
is documented upstream, not runtime-verified here. No token savings are claimed.

Relevant existing fixture checks were run through `tests/run`:
`test_cli_wrappers.sh`, `test_shell_aliases.sh`, `test_clauderm.sh`,
`test_bobtask.sh`, `test_install_claude_plugins.sh`, and
`test_install_nix_tools.sh`. These check the existing integration, not native
Codex session mutations. This assessment changes documentation only.
