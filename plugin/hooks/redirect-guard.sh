#!/usr/bin/env bash
# Pede aprovação para comando Bash com redirecionamento (>) para arquivo, salvo formas fechadas (PreToolUse em Bash).
# No modo automático e no acceptEdits, o Claude Code não aplica ao redirecionamento as regras ask de Edit. A lógica está
# em redirect-guard.mjs; sem node, todo comando com > pede aprovação.
set -uo pipefail

input=$(cat)
ask() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$1"; exit 0; }
if ! command -v node > /dev/null; then
  printf '%s' "$input" | grep -q '>' && ask '"redirect-guard: node ausente; comando com > só com aprovação"'
  exit 0
fi
verdict=$(printf '%s' "$input" | node "$(dirname "$0")/redirect-guard.mjs") || ask '"redirect-guard: falhou ao ler o comando; comando só com aprovação"'
case "$verdict" in
  '') exit 0 ;;
  ASK*) ask "$(printf '%s' "redirect-guard: ${verdict#ASK }" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.stringify(s)))')" ;;
  *) ask '"redirect-guard: veredito ilegível; comando só com aprovação"' ;;
esac
