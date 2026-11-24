#!/usr/bin/env bash
# Sonda 2 do wstack, passo C (PreToolUse em Bash): mesmo formato dos hooks Node que o plugin vai ter, um wrapper que
# roda o .mjs da própria pasta. Sem node, ou se ele falhar, nega o comando da sonda dizendo por quê; qualquer outro
# comando passa sem saída.
set -u
input=$(cat)
deny() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"; exit 0; }
case "$input" in
  *wstack-sonda-node* | *sonda-allow.sh*) ;;
  *) exit 0 ;;
esac
command -v node > /dev/null || deny 'wstack-sonda-node: node ausente'
printf '%s' "$input" | node "$(dirname "$0")/sonda-node.mjs" || deny 'wstack-sonda-node: o node falhou (import quebrado?)'
