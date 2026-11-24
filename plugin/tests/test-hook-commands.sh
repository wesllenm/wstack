#!/usr/bin/env bash
# Casos dos comandos de hook do PreToolUse como estão no hooks.json do plugin, rodados pelo sh como o Claude Code roda
# (CLAUDE_PLUGIN_ROOT é a pasta do plugin): com o arquivo do hook ausente, o write-guard recusa (código 2) e o push-guard,
# o redirect-guard, o path-guard e o checkpoint-tests pedem aprovação (JSON ask); com o arquivo presente, o veredito do
# próprio hook passa intacto (o deny do push-guard continua deny). Confere também que todo arquivo que o hooks.json roda
# existe no plugin, e as regras do .gitignore no settings.json modelo.
# Uso: test-hook-commands.sh [<hooks.json>] [<settings.json modelo>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
hooks=${1:-$here/../hooks/hooks.json}
settings=${2:-$here/fixtures/settings.json}
[ -f "$hooks" ] && [ -f "$settings" ] || { echo "hooks.json ou settings.json modelo não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
plugin=$(cd "$(dirname "$hooks")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-hookcmd-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
# projeto de teste: um repositório com o risk.conf de referência versionado
proj=$work/projeto; mkdir -p "$proj/.claude" && git init -q "$proj" && cp "$here/fixtures/risk.conf" "$proj/.claude/risk.conf"
git -C "$proj" add -A && git -C "$proj" -c user.email=t@t -c user.name=t commit -q -m base

cmd_of() { # cmd_of <matcher> <nome do hook>
  jq -r --arg m "$1" --arg h "$2" '.hooks.PreToolUse[] | select(.matcher == $m) | .hooks[] | .command | select(contains($h))' "$hooks"
}
run() { # run <comando> <pasta do plugin> <payload> -> imprime "código|decisão"
  # sem CLAUDE_CODE_REMOTE: na VM da nuvem ela vale true e livraria as travas por texto (modo nuvem, testado à parte)
  local out rc
  out=$(printf '%s' "$3" | env -u CLAUDE_CODE_REMOTE CLAUDE_PLUGIN_ROOT="$2" CLAUDE_PROJECT_DIR="$proj" sh -c "$1" 2> /dev/null); rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null)"
}

# todo arquivo que um comando do hooks.json roda existe no plugin
files=$(jq -r '.. | .command? // empty' "$hooks" | grep -oE '"\$\{CLAUDE_PLUGIN_ROOT\}"/[A-Za-z0-9._/-]+' | sed 's|^"${CLAUDE_PLUGIN_ROOT}"/||' | sort -u)
[ -n "$files" ] || { echo "FALHOU: nenhum arquivo do plugin no hooks.json"; fails=$((fails + 1)); }
while IFS= read -r f; do
  [ -n "$f" ] && { [ -f "$plugin/$f" ] || { echo "FALHOU: o hooks.json roda $f, que não existe no plugin"; fails=$((fails + 1)); }; }
done <<< "$files"
# o hooks.json só cita a pasta do plugin, nunca .claude/ do projeto
jq -r '.. | .command? // empty' "$hooks" | grep -q 'CLAUDE_PROJECT_DIR\|\.claude/' && { echo "FALHOU: comando do hooks.json cita o projeto"; fails=$((fails + 1)); }
[ -n "$(cmd_of Bash script-allow.sh)" ] || { echo "FALHOU: script-allow fora do PreToolUse em Bash"; fails=$((fails + 1)); }
expect() { # expect <esperado> <obtido> <caso>
  [ "$1" = "$2" ] || { echo "FALHOU: $3: esperado $1, obtido $2"; fails=$((fails + 1)); }
}

bash_payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"git status"}}'
write_payload='{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"/tmp","tool_input":{"file_path":"/tmp/x.txt","content":"x"}}'
mkdir -p "$work/vazio"

wg=$(cmd_of 'Edit|Write|MultiEdit|NotebookEdit' write-guard.sh)
pg=$(cmd_of Bash push-guard.sh)
ct=$(cmd_of Bash checkpoint-tests.sh)
rg=$(cmd_of Bash redirect-guard.sh)
pa=$(cmd_of Bash path-guard.sh)
for c in "$wg" "$pg" "$ct" "$rg" "$pa"; do [ -n "$c" ] || { echo "FALHOU: comando de hook não encontrado no hooks.json"; fails=$((fails + 1)); }; done

# arquivo do hook ausente
expect '2|' "$(run "$wg" "$work/vazio" "$write_payload")" 'write-guard ausente recusa'
expect '0|ask' "$(run "$pg" "$work/vazio" "$bash_payload")" 'push-guard ausente pede aprovação'
expect '0|ask' "$(run "$ct" "$work/vazio" "$bash_payload")" 'checkpoint-tests ausente pede aprovação'
expect '0|ask' "$(run "$rg" "$work/vazio" "$bash_payload")" 'redirect-guard ausente pede aprovação'
expect '0|ask' "$(run "$pa" "$work/vazio" "$bash_payload")" 'path-guard ausente pede aprovação'
expect '0|' "$(run "$rg" "$plugin" "$bash_payload")" 'redirect-guard presente não diz nada sem >'
expect '0|ask' "$(run "$rg" "$plugin" '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"git status > .gitignore"}}')" 'redirect-guard presente pede aprovação para > em arquivo'

# arquivo presente: o veredito do hook passa intacto
expect '0|' "$(run "$wg" "$plugin" "$write_payload")" 'write-guard presente libera arquivo comum'
expect '2|' "$(run "$wg" "$plugin" '{"tool_name":"Write","cwd":"/tmp","tool_input":{"file_path":"/tmp/r/.git/config"}}')" 'write-guard presente recusa .git'
expect '0|' "$(run "$pg" "$plugin" "$bash_payload")" 'push-guard presente não diz nada fora de push'
expect '2|' "$(run "$pg" "$plugin" '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"git push origin main"}}')" 'push-guard presente recusa push para a main'
expect '0|' "$(run "$ct" "$plugin" "$bash_payload")" 'checkpoint-tests presente não diz nada fora de commit'
expect '0|ask' "$(run "$pa" "$plugin" '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"cp /tmp/x .claude/settings.json"}}')" 'path-guard presente pede aprovação para trava'

# TaskCompleted: o ask não vale fora do PreToolUse; ausente, o checkpoint-tests recusa fechar a tarefa (código 2)
tc=$(jq -r '.hooks.TaskCompleted[].hooks[].command | select(contains("checkpoint-tests.sh"))' "$hooks")
[ -n "$tc" ] || { echo "FALHOU: comando do TaskCompleted não encontrado"; fails=$((fails + 1)); }
expect '2|' "$(run "$tc" "$work/vazio" '{"hook_event_name":"TaskCompleted"}')" 'checkpoint-tests ausente no TaskCompleted recusa'

# o .gitignore é a barreira entre o índice e o .env (git add sem -f é liberado): fica no deny, a única regra que o
# Claude Code aplica também ao redirecionamento no modo automático e no acceptEdits (prove-redirect-guard.sh)
for r in 'Edit(./.gitignore)' 'Edit(./**/.gitignore)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r)' "$settings" > /dev/null || { echo "FALHOU: $r fora do deny"; fails=$((fails + 1)); }
  jq -e --arg r "$r" '.permissions.ask | index($r)' "$settings" > /dev/null && { echo "FALHOU: $r também no ask"; fails=$((fails + 1)); }
done
jq -e '(.permissions.allow // [])[] | select(test("gitignore"))' "$settings" > /dev/null && { echo "FALHOU: regra de .gitignore no allow"; fails=$((fails + 1)); }

if [ "$fails" -eq 0 ]; then echo "test-hook-commands: todos os casos passaram"; exit 0; fi
echo "test-hook-commands: $fails falha(s)"
exit 1
