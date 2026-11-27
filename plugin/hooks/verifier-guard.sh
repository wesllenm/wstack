#!/usr/bin/env bash
# Trava os comandos de Bash do review-verifier (PreToolUse em Bash): a prova que ele roda foi escrita por uma lente que
# leu código possivelmente hostil. Rede e execução arbitrária são negadas, as formas conhecidas de prova passam, o resto
# pede aprovação. Outros agentes e a sessão principal passam sem veredito. A lógica está em verifier-guard.mjs; sem
# node, ou se ele falhar, o comando pede aprovação.
set -uo pipefail

input=$(cat)
ask() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$1"; exit 0; }
command -v node > /dev/null || ask '"verifier-guard: node ausente; comando só com aprovação"'
verdict=$(printf '%s' "$input" | node "$(dirname "$0")/verifier-guard.mjs") || ask '"verifier-guard: falhou ao ler o comando; comando só com aprovação"'
case "$verdict" in
  '') exit 0 ;;
  DENY*) echo "verifier-guard: ${verdict#DENY }" >&2; exit 2 ;;
  ASK*) ask "$(printf '%s' "verifier-guard: ${verdict#ASK }" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.stringify(s)))')" ;;
  *) ask '"verifier-guard: veredito ilegível; comando só com aprovação"' ;;
esac
