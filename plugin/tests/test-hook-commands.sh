#!/usr/bin/env bash
# Casos dos comandos de hook do PreToolUse como estão no settings.json, rodados pelo sh como o Claude Code roda:
# com o arquivo do hook ausente, o write-guard recusa (código 2) e o push-guard e o checkpoint-tests pedem aprovação
# (JSON ask); com o arquivo presente, o veredito do próprio hook passa intacto (o deny do push-guard continua deny).
# Uso: test-hook-commands.sh [<settings.json>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

top=$(git rev-parse --show-toplevel 2> /dev/null)
settings=${1:-$top/.claude/settings.json}
[ -f "$settings" ] || { echo "settings.json não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-hookcmd-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0

cmd_of() { # cmd_of <matcher> <nome do hook>
  jq -r --arg m "$1" --arg h "$2" '.hooks.PreToolUse[] | select(.matcher == $m) | .hooks[] | .command | select(contains($h))' "$settings"
}
run() { # run <comando> <projeto> <payload> -> imprime "código|decisão"
  local out rc
  out=$(printf '%s' "$3" | CLAUDE_PROJECT_DIR=$2 sh -c "$1" 2> /dev/null); rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null)"
}
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
for c in "$wg" "$pg" "$ct" "$rg"; do [ -n "$c" ] || { echo "FALHOU: comando de hook não encontrado no settings.json"; fails=$((fails + 1)); }; done

# arquivo do hook ausente
expect '2|' "$(run "$wg" "$work/vazio" "$write_payload")" 'write-guard ausente recusa'
expect '0|ask' "$(run "$pg" "$work/vazio" "$bash_payload")" 'push-guard ausente pede aprovação'
expect '0|ask' "$(run "$ct" "$work/vazio" "$bash_payload")" 'checkpoint-tests ausente pede aprovação'
expect '0|ask' "$(run "$rg" "$work/vazio" "$bash_payload")" 'redirect-guard ausente pede aprovação'
expect '0|' "$(run "$rg" "$top" "$bash_payload")" 'redirect-guard presente não diz nada sem >'
expect '0|ask' "$(run "$rg" "$top" '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"git status > .gitignore"}}')" 'redirect-guard presente pede aprovação para > em arquivo'

# arquivo presente: o veredito do hook passa intacto
expect '0|' "$(run "$wg" "$top" "$write_payload")" 'write-guard presente libera arquivo comum'
expect '2|' "$(run "$wg" "$top" '{"tool_name":"Write","cwd":"/tmp","tool_input":{"file_path":"/tmp/r/.git/config"}}')" 'write-guard presente recusa .git'
expect '0|' "$(run "$pg" "$top" "$bash_payload")" 'push-guard presente não diz nada fora de push'
expect '2|' "$(run "$pg" "$top" '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"git push origin main"}}')" 'push-guard presente recusa push para a main'
expect '0|' "$(run "$ct" "$top" "$bash_payload")" 'checkpoint-tests presente não diz nada fora de commit'

# TaskCompleted: o ask não vale fora do PreToolUse; ausente, o checkpoint-tests recusa fechar a tarefa (código 2)
tc=$(jq -r '.hooks.TaskCompleted[].hooks[].command | select(contains("checkpoint-tests.sh"))' "$settings")
[ -n "$tc" ] || { echo "FALHOU: comando do TaskCompleted não encontrado"; fails=$((fails + 1)); }
expect '2|' "$(run "$tc" "$work/vazio" '{"hook_event_name":"TaskCompleted"}')" 'checkpoint-tests ausente no TaskCompleted recusa'

# o .gitignore é a barreira entre o índice e o .env (git add sem -f é liberado): fica no deny, a única regra que o
# Claude Code aplica também ao redirecionamento no modo automático e no acceptEdits (prove-redirect-guard.sh)
for r in 'Edit(./.gitignore)' 'Edit(./**/.gitignore)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r)' "$settings" > /dev/null || { echo "FALHOU: $r fora do deny"; fails=$((fails + 1)); }
  jq -e --arg r "$r" '.permissions.ask | index($r)' "$settings" > /dev/null && { echo "FALHOU: $r também no ask"; fails=$((fails + 1)); }
done
jq -e '.permissions.allow[] | select(test("gitignore"))' "$settings" > /dev/null && { echo "FALHOU: regra de .gitignore no allow"; fails=$((fails + 1)); }

if [ "$fails" -eq 0 ]; then echo "test-hook-commands: todos os casos passaram"; exit 0; fi
echo "test-hook-commands: $fails falha(s)"
exit 1
