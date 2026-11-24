#!/usr/bin/env bash
# Sonda do wstack (PreToolUse em Bash): só para o comando exato `echo wstack-sonda`, pede aprovação e põe no motivo
# o valor da chave `sonda` do .claude/risk.conf do PROJETO. Qualquer outro comando passa sem saída.
set -u
input=$(cat)
command -v jq > /dev/null || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<< "$input" 2> /dev/null)
[ "$cmd" = "echo wstack-sonda" ] || exit 0
project=${CLAUDE_PROJECT_DIR:-}
conf="$project/.claude/risk.conf"
value=""
[ -n "$project" ] && [ -f "$conf" ] && [ ! -L "$conf" ] && value=$(sed -n 's/^[[:space:]]*sonda[[:space:]]*=[[:space:]]*//p' "$conf" | head -1 | tr -d '\r')
[[ $value =~ ^[A-Za-z0-9._-]{1,40}$ ]] || value="NÃO LIDO"
jq -cn --arg r "wstack-sonda: hook do plugin rodou; risk.conf do projeto: sonda = $value" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
exit 0
