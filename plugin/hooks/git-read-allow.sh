#!/usr/bin/env bash
# Libera git log, git diff e git show sem pedido de permissão só num formato fechado (PreToolUse em Bash). Essas
# formas saíram do allow do settings.json porque a regra por prefixo aceitava --output=<arquivo>. A lógica está em
# git-read-allow.mjs; sem node, ou fora do formato, o hook não diz nada e vale o pedido de permissão normal.
set -uo pipefail

command -v node > /dev/null || exit 0
verdict=$(node "$(dirname "$0")/git-read-allow.mjs")
[ "$verdict" = ALLOW ] || exit 0
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"git-read-allow: git log/diff/show no formato fechado"}}'
