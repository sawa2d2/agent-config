#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CODEX_HOME="$tmp/codex"
export XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"
mkdir -p "$HOME"

bash "$root/scripts/install-nvim-acp" > /dev/null
destination="$HOME/.config/nvim/plugin/agent-acp.lua"
[[ $(readlink "$destination") == "$root/deploy/nvim/plugin/agent-acp.lua" ]]
bash "$root/scripts/install-nvim-acp" > /dev/null
rm "$destination"
printf 'user config\n' > "$destination"
if bash "$root/scripts/install-nvim-acp" > /dev/null 2>&1; then
  echo 'FAIL: overwrote user config' >&2
  exit 1
fi
[[ $(cat "$destination") == 'user config' ]]

command -v nvim > /dev/null || { echo 'SKIP: nvim configuration checks (nvim unavailable)'; exit 0; }
cat > "$tmp/check.lua" <<'LUA'
local source = assert(vim.env.ACP_SOURCE)
local captured
package.loaded.codecompanion = { setup = function(config) captured = config end }
local function check(choice, bob_available, expected)
  vim.env.AGENT_CONFIG_ACP_AGENT = choice
  vim.fn.executable = function(command)
    return command == "bob" and bob_available and 1 or 0
  end
  dofile(source)
  assert(captured.interactions.chat.adapter == expected, "wrong selection: " .. tostring(choice))
  local bob = captured.adapters.acp.bob()
  assert(vim.deep_equal(bob.commands.default, { "bob", "acp" }))
end
package.loaded["codecompanion.adapters.acp.helpers"] = {}
check("codex", false, "codex")
check("codex", true, "codex")
check("claude_code", true, "claude_code")
check("bob", false, "bob")
check(nil, true, "bob")
check(nil, false, "claude_code")
check("invalid", true, "bob")
check("invalid", false, "claude_code")
assert(vim.fn.maparg("<leader>a", "n"):find("CodeCompanionChat Toggle", 1, true))
LUA
ACP_SOURCE="$root/deploy/nvim/plugin/agent-acp.lua" nvim --headless -u NONE -i NONE -l "$tmp/check.lua"
echo 'PASS: Neovim ACP selection and isolated installation'
