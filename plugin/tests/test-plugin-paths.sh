#!/usr/bin/env bash
# Os hooks, scripts e o setup da nuvem moram no plugin: nenhuma linha de código deles roda ou manda rodar algo de
# .claude/scripts, .claude/hooks ou .claude/cloud/setup.sh do projeto (que não existem mais). Comentários não contam; o
# que é do projeto de verdade (.claude/risk.conf, .claude/cloud/hosts.conf, .claude/settings.json) não entra na regra.
# Uso: test-plugin-paths.sh [<pasta do plugin>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

plugin=${1:-$(dirname "$0")/..}
[ -d "$plugin/hooks" ] && [ -d "$plugin/scripts" ] || { echo "pasta do plugin inválida: $plugin" >&2; exit 2; }
fails=0

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "FALHOU: caminho do harness no projeto: $hit"
  fails=$((fails + 1))
done < <(grep -rnE '\.claude/(scripts|hooks)/|\.claude/cloud/setup\.sh' "$plugin/hooks" "$plugin/scripts" "$plugin/cloud" |
  grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)')

if [ "$fails" -eq 0 ]; then echo "test-plugin-paths: todos os casos passaram"; exit 0; fi
echo "test-plugin-paths: $fails falha(s)"
exit 1
