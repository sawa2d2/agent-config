# Native context compaction

Normal repository launchers (`bin/codex`, `bin/claude`, `bin/bob`) use the
CLI's native compaction, including `new` and resume. This is an experiment
with triggers near the retained custom handoff's 35k/50k measurements, not a
claim that native compaction is faster, cheaper, or more accurate.

| CLI inspected | Managed default | Approximate native trigger |
| --- | --- | --- |
| Codex 0.167.0 | `model_auto_compact_token_limit = 35000` | 35k active-context tokens, subject to native model limits |
| Claude Code 2.1.319 | `autoCompactWindow: 100000` | Typically 67k: 100k minus up to 20k output reserve and 13k summary reserve |
| Bob Shell 2.0.9 | `session.compactionThresholdPercent: 19` | 51,300 at a 270k model window; 19% of the server-provided window otherwise |

Claude cannot reach 35k using the documented window setting: 100k is its
minimum, so this is the nearest supported window. Per-model settings, CLI and
environment overrides can change the effective window. Its installed code also
contains `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, but the current public environment
reference does not list it and some execution paths ignore it. We do not set
this internal override or fake a model's context window.

Bob's installed distribution reads the native session percentage, divides it
by 100, and compares current context with `window * fraction`. No minimum
clamp was found in that path or the shipped setting definitions. 19 is the
nearest whole percentage to 50k for the observed 270k window. This is evidence
from 2.0.9, not a published minimum/range guarantee: the public Shell settings
schema does not describe this key. Recheck the installed implementation after
upgrades. A different model/window changes the absolute trigger; no model
metadata override is installed.

Native compaction summarizes history and retains context in the same session.
It is not `/clear` plus takeover in a fresh session. The threshold controls
when compaction is considered, not the resulting summary size or the next
request's token count. Fixed instructions, retained messages, summaries and
new tool output can keep context above a target. Native checks can run inside
a long turn, whereas custom handoff waits for a successful turn boundary;
the measurements and timing are therefore only approximately comparable.
No real-model performance or summary-quality comparison has been run here.

## Selecting the retained handoff

Put `auto-handoff` first, then use the ordinary launcher arguments:

```sh
codex auto-handoff new
claude auto-handoff new
bob auto-handoff new
```

Without `new`, the usual resume defaults apply. Manual handoff and takeover,
custom rotation code, hook relays and their tests remain available. Native
compaction stays enabled even in opt-in mode and can run before a custom
rotation. To compare with the earlier native headroom, choose it explicitly:

```sh
codex auto-handoff new -c model_auto_compact_token_limit=100000
claude auto-handoff new --autocompact 120000
```

For Bob, back up settings and explicitly set
`session.compactionThresholdPercent` to `37` for that comparison, then start
the underlying CLI through the launcher only after accounting for the managed
migration below. A wrapper refresh migrates 37 to 19; to keep 37, run the real
Bob CLI via `scripts/agent-auto-handoff bob /absolute/path/to/bob chat --auto-approve`
after setting it, bypassing the settings installer. Restore settings after the
comparison. The wrapper opt-in alone never disables native compaction.
See [automatic handoff](automatic-handoff.md) for its safety and recovery rules.

## Migration and application

The installers add missing settings and migrate only recognized old defaults:
Codex's exact first line of 100000 or 200000; Claude's numeric 120000 or 200000;
Bob's numeric 37 or 80. Other explicit values, Codex profiles/quoted/dotted
keys, Claude model-specific choices and compaction-disable settings survive.
Old JSON settings have no provenance marker, so an intentional value equal to
an old managed default is indistinguishable and will migrate. Review/back up
those values before applying. No real HOME settings were changed during this
implementation or its tests.

The launchers already refresh managed settings on startup. Starting one from
this checkout applies its migration; do not launch it against a real HOME
until the local-settings change is approved. `type -a codex claude bob` shows
whether your PATH selects these wrappers or a standalone CLI. A standalone
CLI does not execute this repository's installer.

After approval, run from this worktree. These existing installers also refresh
their established non-compaction defaults; the Claude installer writes its
managed theme. Back up their targets first (dereference symlinks so their old
contents are saved). Keep the printed backup path for restoration:

```sh
git switch feat/native-context-compaction
compaction_backup=$(mktemp -d "$HOME/native-compaction-backup.XXXXXX")
for rel in .codex/config.toml .claude/settings.json .claude/themes/agent-config-selected.json .bob/settings/settings.json; do target="$HOME/$rel"; if [[ $rel == .codex/config.toml ]]; then target="${CODEX_HOME:-$HOME/.codex}/config.toml"; fi; mkdir -p "$compaction_backup/$(dirname "$rel")"; if [[ -e $target ]]; then cp -pL -- "$target" "$compaction_backup/$rel"; else touch "$compaction_backup/$rel.absent"; fi; done
printf 'Backup: %s\n' "$compaction_backup"
bash scripts/install-codex-compaction && bash scripts/install-claude-settings && bash scripts/install-bob-settings
```

Restore in the same shell, with the same `CODEX_HOME` (or set
`compaction_backup` to the saved path). Writing through existing targets keeps
symlinks intact. Stop sessions first so a settings reload does not race this:

```sh
for rel in .codex/config.toml .claude/settings.json .claude/themes/agent-config-selected.json .bob/settings/settings.json; do target="$HOME/$rel"; if [[ $rel == .codex/config.toml ]]; then target="${CODEX_HOME:-$HOME/.codex}/config.toml"; fi; if [[ -f "$compaction_backup/$rel" ]]; then cat "$compaction_backup/$rel" > "$target"; elif [[ -f "$compaction_backup/$rel.absent" ]]; then rm -f -- "$target"; fi; done
```

A later wrapper launch reapplies managed defaults; restore the earlier checkout
or use the underlying CLI when comparing the previous configuration.

## Evidence and verification

- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference):
  native token limit and default total-context scope. The installed 0.167.0
  App Server `generate-json-schema` output also exposes the integer field.
- [Claude settings reference](https://code.claude.com/docs/en/settings-reference#autocompactwindow)
  and [environment variables](https://code.claude.com/docs/en/env-vars): supported
  window range and overrides. Installed 2.1.319 `Pre`/`MY` functions subtract
  `min(maxOutputTokens, 20000)` and 13000; native scheduling and model choice
  can change when compaction actually occurs.
- [Bob Shell context management](https://bob.ibm.com/docs/shell/core-concepts/context-window-management):
  context and summarization semantics. Installed `@ibm/bob/dist/bob.js` 2.0.9
  `getCompactionThreshold()` and `S8i` establish the percentage calculation;
  `getModelInfo()` supplies the actual model window.

Run the relevant deterministic suites; they isolate settings under temporary
homes and use CLI doubles/PTYs, not real credentials or model requests:

```sh
git switch feat/native-context-compaction
bash tests/run tests/test_install_codex_compaction.sh tests/test_install_claude_settings.sh tests/test_install_bob_settings.sh tests/test_cli_wrappers.sh tests/test_claude_wrapper.sh tests/test_agent_auto_handoff.sh tests/test_codex_auto_handoff.sh tests/test_install_agent_hooks.sh tests/test_bob_handoff_suggest.sh tests/test_codex_handoff_suggest.sh tests/test_codex_hook_refresh.sh
```

Expected: all suites pass. Coverage includes new defaults, old-default
migration, explicit-value preservation, native versus opt-in PTY routing,
argument forwarding, and retained handoff rotation/recovery.
