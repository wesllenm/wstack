#!/usr/bin/env bash
# Aprova os scripts do próprio plugin sem regra allow no projeto, só em forma fechada (PreToolUse em Bash). A lógica está
# em script-allow.mjs; sem node, ou fora da forma, o hook não diz nada e vale o pedido de permissão normal.
set -uo pipefail

command -v node > /dev/null || exit 0
verdict=$(node "$(dirname "$0")/script-allow.mjs" 2> /dev/null)
[ "$verdict" = ALLOW ] || exit 0
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"script-allow: script do plugin na forma fechada"}}'
