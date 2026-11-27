#!/usr/bin/env bash
# Conta quantas vezes uma sessão parou pedindo aprovação, e por quê: os pedidos de hook (agrupados por hook e motivo,
# pelo permission-asks.mjs do plugin) e o total de aprovações manuais, que inclui os pedidos das regras ask do
# settings.json, que nenhum hook faz. Roda depois da sessão, sobre a transcrição dela.
# Para medir o atrito de uma sessão autônoma: rodar uma tarefa realista de uns 30 minutos (build, teste, ssh para um host, > para arquivo
# temporário, docker exec) e, ao fim, este script na mesma máquina.
# Uso: measure-permission-asks.sh                    a sessão mais recente do projeto da pasta atual
#      measure-permission-asks.sh <pasta do projeto> a sessão mais recente desse projeto
#      measure-permission-asks.sh <transcrição.jsonl>
# A transcrição fica em ~/.claude/projects/<pasta do projeto com cada caractere fora de [A-Za-z0-9] trocado por ->/
# (ou em $CLAUDE_CONFIG_DIR/projects), e os subagentes em <sessão>/subagents/.
# Código: 0 contou, 1 transcrição ilegível, 2 uso errado ou nada encontrado.
set -uo pipefail

plugin=$(cd "$(dirname "$0")/.." && pwd -P)
command -v node > /dev/null || { echo "node ausente do PATH" >&2; exit 2; }
arg=${1:-.}
if [ -f "$arg" ]; then
  file=$arg
else
  proj=$(cd "$arg" 2> /dev/null && pwd -W 2> /dev/null || cd "$arg" 2> /dev/null && pwd -P) || { echo "pasta não encontrada: $arg" >&2; exit 2; }
  base=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
  # o Claude Code nomeia a pasta da sessão pelo caminho do projeto; no Windows, pelo caminho com a letra do disco
  enc=$(node -e 'process.stdout.write(process.argv[1].replace(/[^A-Za-z0-9]/g, "-"))' "$proj")
  dir="$base/$enc"
  [ -d "$dir" ] || { echo "sem sessões em $dir (pastas existentes: $(ls "$base" 2> /dev/null | head -5 | tr '\n' ' '))" >&2; exit 2; }
  file=$(ls -t "$dir"/*.jsonl 2> /dev/null | head -1)
  [ -n "$file" ] || { echo "nenhuma transcrição em $dir" >&2; exit 2; }
fi
sub="${file%.jsonl}/subagents"
echo "Transcrição: $file"
echo "Alterada em: $(date -r "$file" '+%Y-%m-%d %H:%M' 2> /dev/null || echo '?')"
echo
if [ -d "$sub" ]; then node "$plugin/scripts/permission-asks.mjs" "$file" "$sub"; else node "$plugin/scripts/permission-asks.mjs" "$file"; fi
rc=$?
echo
echo "Leitura: 'pedidos' são os pedidos de hook, por hook; 'aprovações manuais' contam todo pedido que você aprovou,"
echo "inclusive os das regras ask do settings.json. A diferença entre os dois é o que veio das regras, sem hook."
exit "$rc"
