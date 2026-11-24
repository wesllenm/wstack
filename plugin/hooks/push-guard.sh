#!/usr/bin/env bash
# Guarda do git push (PreToolUse em Bash). O allow do settings.json libera "git push -u origin <branch de atividade>"
# por glob, e um glob aceita qualquer coisa depois do branch; este hook decide cada push que começa um subcomando:
#   permitido  forma exata validada (alfabeto fechado, remoto origin, destino de atividade ou refs/heads/wip/): segue
#   pergunta   força o pedido de permissão mesmo que o allow case (force-with-lease, outro remoto ou destino,
#              aspas, $, heredoc, comentário...): só o desenvolvedor aprova
#   recusa     main/master, force puro, +, apagar, mirror/all/tags, --no-verify, -c e GIT_*: código 2, nem com aprovação
# A lógica está em push-guard.mjs. Limite: push indireto (bash -c, eval, script) não passa por aqui e cai no pedido
# de permissão normal, porque não casa nenhuma regra do allow.
set -uo pipefail

input=$(cat)
ask() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$1"; exit 0; }
if ! command -v node > /dev/null; then
  # sem node não dá para ler o comando: todo push pede permissão
  printf '%s' "$input" | grep -q 'push' && ask '"push-guard: node ausente; push só com aprovação do desenvolvedor"'
  exit 0
fi
verdict=$(printf '%s' "$input" | node "$(dirname "$0")/push-guard.mjs")
case "$verdict" in
  OK) exit 0 ;;
  ASK*) ask "$(printf '%s' "push-guard: ${verdict#ASK }" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.stringify(s)))')" ;;
  DENY*) echo "push-guard: ${verdict#DENY } (recusado: push para a main, force puro e apagar ref são sempre do desenvolvedor)" >&2; exit 2 ;;
  *) ask '"push-guard: veredito ilegível; push só com aprovação do desenvolvedor"' ;;
esac
