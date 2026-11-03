# Codex RTK coverage review

Branch-local review on 2026-11-03. No coverage expansion is justified by the
evidence below. Test runners, pipelines and compound commands continue through
Codex's normal approval flow without this hook rewriting them.

## Supported contract

The official [Hooks documentation](https://learn.chatgpt.com/docs/hooks#pretooluse)
requires `permissionDecision: "allow"` alongside `updatedInput`.
`permissionDecision: "ask"` is unsupported. `PermissionRequest` does not support
`updatedInput` either. These documented interfaces do not provide a rewrite-only
decision that preserves the ordinary approval decision.

## Local observations

- Installed CLI: `codex-cli 0.160.0`; installed RTK: `rtk 0.50.0`.
- Ran `rtk hook codex` with JSON fixtures under a temporary HOME,
  XDG_CONFIG_HOME and XDG_DATA_HOME. The input included `session_id`,
  `transcript_path`, `cwd`, `permission_mode: "default"`,
  `hook_event_name: "PreToolUse"`, `tool_name: "Bash"`, `tool_use_id` and
  `tool_input.command`.
- `git status` became `rtk git status`; `cargo test` became `rtk cargo test`;
  `git status && git diff` became `rtk git status && rtk git diff`.
  Each response contained `permissionDecision: "allow"` and `updatedInput`.
  `cat a | head` produced no rewrite. These were hook invocations only;
  no test runner or rewritten compound command was executed.
- A Codex exec attempt with a temporary HOME/CODEX_HOME, `--ephemeral`,
  `--skip-git-repo-check`, `--sandbox read-only` and `--json` did not complete
  within 25 seconds. A local mock-model server could not be started because
  creating an AF_INET socket raised `PermissionError: [Errno 1] Operation not
  permitted`. No approval, sandbox or hook-trust bypass was used.

Therefore the old end-to-end approval/input-rewrite interaction has **not** been
reproduced in this environment. The installed RTK response and current official
contract support retaining the existing restriction; they do not establish that
a newer CLI fixes the interaction. A future expansion needs a trusted-hook
runtime comparison of no hook, rewrite without allow, and rewrite with allow,
including a command that normally requires approval. Run that comparison in an
environment with working model access or a local mock provider and keep all
command effects inside temporary fixtures. Confirm that approval requests and
denials still govern the rewritten command before changing coverage.

## Safe filter corrections

The review also reproduced two omissions entirely within temporary fixtures:

- `find input -fprint0 output` wrote `input\0` to `output`.
- `rg --hostname-bin=<fixture-helper> --hyperlink-format=default --color=always
  fixture input` invoked the helper, which wrote a fixture marker.

The filter now excludes `-fprint0` and both forms of `--hostname-bin`, so these
commands retain normal approval. Existing read-only command coverage is retained.
This is a conservative command filter, not a shell sandbox or a proof that local
executables, Git configuration, or files are trustworthy.

Regression checks (with fake RTK, not a live model):

```sh
tests/run tests/test_codex_rtk_hook.sh tests/test_install_agent_hooks.sh
```

The tests exercise the actual filter and temporary installer fixtures. They do
not verify live Codex approvals or measure token savings.
