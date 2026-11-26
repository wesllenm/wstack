#!/usr/bin/env bash
# Pede aprovação para comando Bash que cita caminho protegido (os do ask e do deny de Edit) ou arquivo de segredo, para
# dotnet fora das formas fechadas e para gh --web (PreToolUse em Bash). No modo automático e no acceptEdits, o Claude
# Code não aplica as regras ask de Edit a comandos de terminal. A lógica está em path-guard.mjs; sem node, ou se ele
# falhar, todo comando pede aprovação.
set -uo pipefail

input=$(cat)
ask() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$1"; exit 0; }
command -v node > /dev/null || ask '"path-guard: node ausente; todo comando só com aprovação"'
verdict=$(printf '%s' "$input" | node "$(dirname "$0")/path-guard.mjs") || ask '"path-guard: falhou ao ler o comando; comando só com aprovação"'
case "$verdict" in
  '') exit 0 ;;
  DENY*) echo "path-guard: ${verdict#DENY }" >&2; exit 2 ;;
  ASK*) ask "$(printf '%s' "path-guard: ${verdict#ASK }" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.stringify(s)))')" ;;
  *) ask '"path-guard: veredito ilegível; comando só com aprovação"' ;;
esac
