#!/usr/bin/env bash
# Sonda 2 do wstack, passo C (PreToolUse em Bash): mesmo formato dos hooks Node que o plugin vai ter, um wrapper que
# roda o .mjs da própria pasta. Só olha dois comandos da sonda: no `echo wstack-sonda-node`, sem node ou com o node
# falhando, nega dizendo por quê; no número 5 do passo B, se o node falhar, sai calado (o pedido de aprovação aparece
# normalmente, e uma falha daqui não se confunde com uma regra allow que não casou). Qualquer outro comando passa sem
# saída.
set -u
input=$(cat)
deny() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"; exit 0; }
case "$input" in
  *wstack-sonda-node*)
    command -v node > /dev/null || deny 'wstack-sonda-node: node ausente'
    printf '%s' "$input" | node "$(dirname "$0")/sonda-node.mjs" || deny 'wstack-sonda-node: o node falhou (import quebrado?)'
    ;;
  *sonda-allow.sh\ 5*)
    command -v node > /dev/null || exit 0
    printf '%s' "$input" | node "$(dirname "$0")/sonda-node.mjs" 2> /dev/null || exit 0
    ;;
esac
exit 0
