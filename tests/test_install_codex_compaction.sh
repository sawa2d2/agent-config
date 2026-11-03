#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
unset CODEX_HOME
config="$HOME/.codex/config.toml"
install_compaction() { bash "$root/scripts/install-codex-compaction" >/dev/null; }
fail() { echo "FAIL: $*" >&2; exit 1; }
install_compaction
[[ $(cat "$config") == 'model_auto_compact_token_limit = 100000' ]] || fail 'default'
before=$(stat -c '%i:%Y' "$config")
install_compaction
[[ $(stat -c '%i:%Y' "$config") == "$before" ]] || fail 'rewritten'
for entry in 'model_auto_compact_token_limit = 123456' '"model_auto_compact_token_limit" = 0' "'model_auto_compact_token_limit' = 80_000" 'profiles.small.model_auto_compact_token_limit = 64000' $'[profiles.small]\nmodel_auto_compact_token_limit = 64000'; do
  printf '%s' "$entry" > "$config"
  install_compaction
  [[ $(cat "$config") == "$entry" ]] || fail 'explicit value changed'
done
printf '%s' $'# model_auto_compact_token_limit = 999\nmodel = "test"\n[tui]\ntheme = "dracula"' > "$config"
cp "$config" "$tmp/original"
chmod 600 "$config"
mv "$config" "$tmp/target"
ln -s "$tmp/target" "$config"
install_compaction
[[ -L "$config" && $(stat -c '%a' "$tmp/target") == 600 ]] || fail 'symlink or mode'
{ printf '%s\n' 'model_auto_compact_token_limit = 100000'; cat "$tmp/original"; } > "$tmp/expected"
cmp "$config" "$tmp/expected" || fail 'unrelated settings changed'
CODEX_HOME="$tmp/custom" install_compaction
[[ $(cat "$tmp/custom/config.toml") == 'model_auto_compact_token_limit = 100000' ]] || fail 'CODEX_HOME'
# The earlier managed root line moves to the new value; the rest is kept.
printf '%s\n' 'model_auto_compact_token_limit = 200000' '[tui]' 'theme = "dracula"' > "$config"
install_compaction
[[ $(cat "$config") == $'model_auto_compact_token_limit = 100000\n[tui]\ntheme = "dracula"' ]] || fail 'old default not migrated'
echo 'PASS: Codex compaction defaults and explicit settings'
