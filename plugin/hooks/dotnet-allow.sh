#!/usr/bin/env bash
# Libera dotnet build, test, restore, format e ef migrations sem pedido de permissão só num formato fechado
# (PreToolUse em Bash). Essas formas saíram do allow por prefixo do settings.json porque o prefixo aceitava opção que
# grava arquivo (-flp:logfile=, -o, --logger...). A lógica está em dotnet-allow.mjs; sem node, ou fora do formato, o
# hook não diz nada e vale o pedido de permissão normal. Só vale com allow_module = dotnet válido no risk.conf do projeto.
set -uo pipefail

command -v node > /dev/null || exit 0
verdict=$(node "$(dirname "$0")/dotnet-allow.mjs")
[ "$verdict" = ALLOW ] || exit 0
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"dotnet-allow: dotnet no formato fechado"}}'
