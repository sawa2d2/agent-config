#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
export CODEX_HOME="$tmp/codex"
config="$CODEX_HOME/config.toml"
install_model() { bash "$root/scripts/install-codex-subagent-model" >/dev/null; }
fail() { echo "FAIL: $*" >&2; exit 1; }
install_model
[[ $(cat "$config") == $'[agents]\ndefault_subagent_model = "gpt-6-luna"' ]] || fail 'missing default'
touch -t 200001010000 "$config"
before=$(stat -c %Y "$config")
install_model
[[ $(stat -c %Y "$config") == "$before" ]] || fail 'unchanged config rewritten'

# Insert into an existing table; leave parent, effort, profiles and role choices alone.
cat > "$config" <<'TOML'
model = "gpt-6.1-sol"
[agents] # shared limits
max_threads = 4
default_subagent_reasoning_effort = "high"
[agents.explorer]
config_file = "agents/explorer.toml"
[profiles.review.agents]
default_subagent_model = "gpt-6-astra"
TOML
cp "$config" "$tmp/original"
chmod 600 "$config"
install_model
sed '/^default_subagent_model = "gpt-6-luna"$/d' "$config" > "$tmp/rest"
cmp "$tmp/original" "$tmp/rest" || fail 'unrelated choices changed'
[[ $(stat -c %a "$config") == 600 ]] || fail 'permissions changed'
grep -q '^default_subagent_model = "gpt-6-luna"$' "$config" || fail 'table default missing'

# Preserve explicit values in supported TOML spellings, including inline tables.
for text in \
  $'[agents]\ndefault_subagent_model = "gpt-6-astra"' \
  'agents.default_subagent_model = "gpt-6-astra"' \
  $'["agents"]\n"default_subagent_model" = "gpt-6-astra"' \
  "'agents'.'default_subagent_model' = 'gpt-6-astra'" \
  'agents = { default_subagent_model = "gpt-6-astra" }' \
  '"\u0061gents".default_subagent_model = "gpt-6-astra"'; do
  printf '%s\n' "$text" > "$config"
  cp "$config" "$tmp/original"
  install_model
  cmp "$config" "$tmp/original" || fail 'explicit value overwritten'
done

# Table-like text and comments in strings must not be mistaken for actual keys.
cat > "$config" <<'TOML'
developer_instructions = """
[agents]
default_subagent_model = "fake"
"""
["agents"] # actual table
max_threads = 2
TOML
install_model
[[ $(grep -c '^default_subagent_model = "gpt-6-luna"$' "$config") == 1 ]] || fail 'multiline string confused table detection'

# Dotted settings without a parent table and a symlinked config remain supported.
printf '%s\n' 'agents.max_threads = 2' > "$tmp/target"
rm "$config"
ln -s "$tmp/target" "$config"
install_model
[[ -L $config ]] || fail 'symlink replaced'
grep -q '^agents.default_subagent_model = "gpt-6-luna"$' "$tmp/target" || fail 'dotted default missing'
unset CODEX_HOME
install_model
[[ -f "$HOME/.codex/config.toml" ]] || fail 'default HOME path missing'
config="$HOME/.codex/config.toml"
# A table header without its final newline must stay valid after insertion.
printf '[agents]' > "$config"
install_model
[[ $(cat "$config") == $'[agents]\ndefault_subagent_model = "gpt-6-luna"' ]] || fail 'unterminated table header'
echo 'PASS: Codex subagent defaults preserve explicit and unrelated settings'
