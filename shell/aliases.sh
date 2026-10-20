# Alias agent-config launchers in interactive Bash or Zsh.
# Source this from a shell startup file; its position does not matter because
# aliases are unaffected by tools such as nvm or Nix reordering PATH later.

if [[ -n ${ZSH_VERSION:-} ]]; then
  # Zsh-only expansion; eval keeps Bash from parsing it.
  eval '_agent_config_source=${(%):-%x}'
else
  _agent_config_source=${BASH_SOURCE[0]}
fi
_agent_config_bin=$(cd -- "$(dirname -- "$_agent_config_source")/../bin" && pwd -P)

for _agent_config_launcher in "$_agent_config_bin"/*; do
  [[ -f "$_agent_config_launcher" && -x "$_agent_config_launcher" ]] || continue
  # shellcheck disable=SC2139 # Bind each alias to its launcher path now.
  alias "${_agent_config_launcher##*/}=$(printf '%q' "$_agent_config_launcher")"
done
unset _agent_config_source _agent_config_bin _agent_config_launcher
