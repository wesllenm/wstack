#!/usr/bin/env bash
# Guarda da escrita em pastas git (PreToolUse em Edit, Write, MultiEdit e NotebookEdit). A lógica está em write-guard.mjs:
# recusa (código 2) gravar em caminho que passe por .git ou dentro das pastas git do projeto. Sem node, recusa todo
# caminho em que apareça ".git" como componente (falha fechada para o que importa, aberta para o resto).
set -uo pipefail

input=$(cat)
deny() { echo "write-guard: $1 (pastas git só pelo próprio git, nunca pela ferramenta de escrita)" >&2; exit 2; }
if ! command -v node > /dev/null; then
  printf '%s' "$input" | grep -Eiq '"(file_path|notebook_path)" *: *"[^"]*(\.git([\\/". :]|$)|git~[0-9]|\.gitconfig|/etc/gitconfig)' && deny "caminho com .git ou config do git (node ausente)"
  exit 0
fi
verdict=$(printf '%s' "$input" | node "$(dirname "$0")/write-guard.mjs")
case "$verdict" in
  OK) exit 0 ;;
  ASK*)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' \
      "$(printf '%s' "write-guard: ${verdict#ASK }" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.stringify(s)))')"
    exit 0 ;;
  DENY*) deny "${verdict#DENY }" ;;
  *) deny "veredito ilegível" ;;
esac
