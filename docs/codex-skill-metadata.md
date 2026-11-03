# Codex Office/browser skill metadata audit

Checked on 2026-11-03 with the installed `codex-cli 0.160.0` (`codex --version`
and `codex --help`). This is an inventory and policy decision, not a token
savings measurement.

## Installed targets

Compared the `name` frontmatter of installed `SKILL.md` files with the 11 names
in `scripts/install-claude-settings`: `docx`, `pptx`, `xlsx`, `pdf`,
`google-workspace`, `computer-use`, `built-in-browser`, `chrome-browser`,
`claude-in-chrome`, `morning`, and `import-memory`.

| Inspected location | SKILL.md files | Matching names |
| --- | ---: | ---: |
| `~/.codex/skills` (including `.system`) | 24 | 0 |
| `~/.agents/skills` | 0 | 0 |
| `~/.codex/plugins/cache` | 26 | 0 |
| `/etc/codex/skills` | 0 | 0 |

The cache contains Sites, Work Pets, plugin management, and OpenAI template
skills. Cache presence does not establish that a plugin is enabled or that its
skills are in the current model context. This inventory is machine-specific;
it does not establish what every Codex installation provides.

## Supported controls and decision

The official [Build skills documentation](https://learn.chatgpt.com/docs/build-skills)
distinguishes explicit invocation (`$skill` or `/skills`) from implicit selection.
For a skill that we own, `agents/openai.yaml` can contain:

```yaml
policy:
  allow_implicit_invocation: false
```

The documented effect is to prevent implicit invocation while retaining
explicit invocation. It is not a documented guarantee of hiding metadata from
the initial model context. `[[skills.config]]` with `enabled = false` disables
a skill; it is not an equivalent policy preserving explicit use. The separate
`skills.max_context_tokens` setting budgets the initial list globally and may
affect useful coding skills too; no global budget is imposed here.

No Office/browser override is installed: there are no matching targets, and
rewriting unmanaged plugin caches or disabling skills would not preserve the
requested ownership and explicit-invocation boundaries. If matching skills are
introduced later, review their ownership and existing invocation policy before
adding a targeted default. Superpowers policy conversion belongs to the
separate `scripts/install-skill` / `scripts/install-tools` work.

## Verification and limits

An isolated temporary HOME, CODEX_HOME, and XDG_CONFIG_HOME contained a single
`audit-explicit` skill with the policy above. Through `codex app-server --stdio`,
JSON-RPC `initialize` followed by `skills/list` (with the temporary working
directory and `forceReload: true`) returned the fixture with `enabled: true`.
Thus it remained discoverable in that API list. The response omitted policy;
this check does not prove runtime implicit-selection enforcement, interactive
picker behavior, or which metadata reaches the model. An initial probe expecting
a policy field failed; the corrected probe checked only visibility and enabled
state. No model request or token measurement was performed.

`bash tests/run tests/test_install_claude_settings.sh tests/test_install_skill.sh`
passed both existing tests using temporary fixtures. No installation was run
against the real HOME or CODEX_HOME, and no global settings were edited.
