#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
rules=$root/deploy/codex/rules/agent-config.rules

# Without the real CLI there is no parser to check against.
command -v codex >/dev/null 2>&1 || { echo 'SKIP: codex not found'; exit 0; }
decision() { codex execpolicy check --rules "$rules" "$@" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("decision", "none"))'; }

# gfinish runs outside the sandbox; nothing else is widened.
[[ $(decision gfinish -y -m 'fix: message') == allow ]]
for command in 'git push' 'git merge main' 'rm -rf /' 'touch gfinish'; do
  # shellcheck disable=SC2086
  [[ $(decision $command) == none ]] || { echo "unexpected match: $command"; exit 1; }
done
