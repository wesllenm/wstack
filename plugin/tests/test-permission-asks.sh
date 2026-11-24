#!/usr/bin/env bash
# Casos do permission-asks.mjs (conta as decisões `ask` de hook numa transcrição JSONL do Claude Code), com uma
# transcrição sintética no formato medido numa sessão real: o ask de hook é um anexo `hook_success` cujo stdout é o
# JSON do hook, e o comando vem do `tool_use` de mesmo id. Sem rede.
# Uso: test-permission-asks.sh [<permission-asks.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

script=${1:-$(dirname "$0")/../scripts/permission-asks.mjs}
[ -f "$script" ] || { echo "permission-asks.mjs não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-pa-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0

use() { # use <id> <comando>: chamada de ferramenta Bash do assistente
  jq -cn --arg id "$1" --arg c "$2" '{type:"assistant",uuid:("a-"+$id),message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}'
}
hook() { # hook <uuid> <id> <stdout do hook>: anexo hook_success de um PreToolUse
  jq -cn --arg u "$1" --arg id "$2" --arg o "$3" '{type:"attachment",uuid:$u,attachment:{type:"hook_success",hookName:"PreToolUse:Bash",hookEvent:"PreToolUse",toolUseID:$id,stdout:$o,exitCode:0}}'
}
reply() { # reply <decision JSON>: resultado de ferramenta com a decisão de permissão registrada pela plataforma
  jq -cn --argjson d "$1" '{type:"user",uuid:"r",message:{role:"user",content:[{type:"tool_result",tool_use_id:"x",content:"ok"}]},permissionDecision:$d}'
}
verdict() { # verdict <decisão> <motivo>: stdout de um hook PreToolUse
  jq -cn --arg d "$1" --arg r "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
}

path_reason='path-guard: o comando cita uma trava do harness (.claude/hooks)'
redirect_reason='redirect-guard: redirecionamento para fora da pasta temporária'
long_cmd="bash .claude/scripts/classify-diff.sh --paths $(printf 'a%.0s' $(seq 1 300))"

main=$work/main.jsonl
{
  use t1 'bash .claude/scripts/classify-diff.sh > /tmp/x/s1.log 2>&1'
  hook u1 t1 "$(verdict ask "$path_reason")"
  use t2 'ls .claude/hooks'
  hook u2 t2 "$(verdict ask "$path_reason")"
  use t3 'git status > .gitignore'
  hook u3 t3 "$(verdict ask "$redirect_reason")"
  use t4 "$long_cmd"
  hook u4 t4 "$(verdict ask "$path_reason")"
  # repetição do mesmo anexo (a plataforma regrava registros): conta uma vez
  hook u4 t4 "$(verdict ask "$path_reason")"
  # hook que liberou, que não opinou e saída que não é JSON: não são pedidos
  use t5 'git log --oneline -5'
  hook u5 t5 "$(verdict allow 'git-read-allow: forma fechada')"
  hook u6 t5 ''
  hook u7 t5 'texto solto com permissionDecision ask'
  # texto que apenas cita um ask (resultado de ferramenta, mensagem): não é pedido
  jq -cn --arg q "$(verdict ask "$path_reason")" '{type:"user",uuid:"q",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t5",content:$q}]}}'
  # hook de outro evento com a mesma saída não conta como pedido de permissão
  jq -cn --arg o "$(verdict ask "$path_reason")" '{type:"attachment",uuid:"u8",attachment:{type:"hook_success",hookEvent:"Stop",toolUseID:"t5",stdout:$o}}'
  reply '{"decision":"accept","source":"user_temporary","grantScope":"once"}'
  reply '{"decision":"accept","source":"config","reasonType":"rule"}'
  reply '{"decision":"accept","source":"hook","reasonType":"hook"}'
  echo 'linha que não é JSON'
} > "$main"

subs=$work/subagents
mkdir -p "$subs"
{
  use s1 'cat .claude/settings.json'
  hook v1 s1 "$(verdict ask "$path_reason")"
} > "$subs/agent-abc.jsonl"
echo '{"hook_success":"nao e transcricao"}' > "$subs/agent-abc.meta.json"

run() { node "$script" "$@" 2> /dev/null; }
has() { # has <rótulo> <saída> <trecho literal>
  case "$2" in *"$3"*) ;; *) echo "FALHOU: $1: faltou \"$3\" na saída:"; printf '%s\n' "$2"; fails=$((fails + 1)) ;; esac
}
lacks() { # lacks <rótulo> <saída> <trecho literal>
  case "$2" in *"$3"*) echo "FALHOU: $1: sobrou \"$3\" na saída:"; printf '%s\n' "$2"; fails=$((fails + 1)) ;; esac
}

# sessão principal: 3 path-guard + 1 redirect-guard (o anexo repetido e o texto citado não contam)
out=$(run "$main")
has 'principal' "$out" 'pedidos: 4 (path-guard 3, redirect-guard 1)'
has 'principal motivo' "$out" "$path_reason"
has 'principal comando' "$out" 'bash .claude/scripts/classify-diff.sh > /tmp/x/s1.log 2>&1'
has 'principal comando curto' "$out" 'git status > .gitignore'
has 'aprovação manual' "$out" 'aprovações manuais: 1'
lacks 'comando longo é resumido' "$out" "$long_cmd"
has 'comando longo é resumido' "$out" '...'
lacks 'allow não é pedido' "$out" 'git-read-allow'
lacks 'Stop não é pedido' "$out" 'Stop'

# com a pasta de subagentes: o pedido do subagente soma e vem rotulado; o .meta.json não é lido
out=$(run "$main" "$subs")
has 'subagentes' "$out" 'pedidos: 5 (path-guard 4, redirect-guard 1)'
has 'subagente rótulo' "$out" 'agent-abc'
has 'subagente comando' "$out" 'cat .claude/settings.json'

# sem pedido: zero explícito
echo '{"type":"user","uuid":"z","message":{"role":"user","content":"oi"}}' > "$work/empty.jsonl"
out=$(run "$work/empty.jsonl")
has 'zero' "$out" 'pedidos: 0'

# uso errado e arquivo ausente
node "$script" > /dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || { echo "FALHOU: sem argumento devia sair com 2, saiu com $rc"; fails=$((fails + 1)); }
node "$script" "$work/nao-existe.jsonl" > /dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] || { echo "FALHOU: arquivo ausente devia sair com 1, saiu com $rc"; fails=$((fails + 1)); }
node "$script" "$main" "$work/nao-existe" > /dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] || { echo "FALHOU: pasta de subagentes ausente devia sair com 1, saiu com $rc"; fails=$((fails + 1)); }

if [ "$fails" -eq 0 ]; then echo "test-permission-asks: todos os casos passaram"; exit 0; fi
echo "test-permission-asks: $fails falha(s)"
exit 1
