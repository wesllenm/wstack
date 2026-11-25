#!/usr/bin/env bash
# Casos do principles.mjs (princípios lidos de fato numa sessão, a partir da transcrição JSONL), com uma transcrição
# sintética no formato medido nesta versão: a ferramenta Skill é um tool_use com input.skill ("wstack:commit"), o Read
# traz input.file_path, e o /comando digitado chega na mensagem do usuário como <command-name>. Sem rede.
# Uso: test-principles.sh [<principles.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

script=${1:-$(dirname "$0")/../scripts/principles.mjs}
[ -f "$script" ] || { echo "principles.mjs não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-pr-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

use() { # use <ferramenta> <input JSON>: chamada de ferramenta do assistente
  jq -cn --arg n "$1" --argjson i "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t",name:$n,input:$i}]}}'
}
user() { jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
said() { jq -cn --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }

main=$work/main.jsonl
mkdir -p "$work/subagents"
{
  use Skill '{"skill":"wstack:tdd"}'
  use Agent '{"subagent_type":"wstack:database-helper","prompt":"x"}'
  use Read '{"file_path":"/home/u/.claude/plugins/cache/wstack/wstack/0.0.13/skills/lead/reference/revisao.md"}'
  use Read '{"file_path":"/home/u/.claude/plugins/cache/wstack/wstack/0.0.13/skills/lead/playbooks/bug.md"}'
  use Read '{"file_path":"/home/u/projeto/src/reference/nada.md"}'
  user '<command-name>/wstack:correct</command-name> <command-args>não é assim</command-args>'
  said 'exemplo no texto do assistente: <command-name>/wstack:security</command-name>'
  echo 'linha que não é JSON'
} > "$main"
use Skill '{"skill":"wstack:api-design"}' > "$work/subagents/agent-1.jsonl"

out=$(node "$script" "$main" "$work/subagents"); code=$?
[ "$code" = 0 ] || fail "sem relatório: código $code"
carregadas=$(printf '%s\n' "$out" | sed -n 's/^carregadas: //p')
for s in lead tdd query-plan correct api-design; do
  printf '%s' "$carregadas" | grep -qw -- "$s" || fail "sem relatório: $s não aparece em carregadas ($carregadas)"
done
printf '%s' "$carregadas" | grep -qw security && fail 'sem relatório: /comando citado pelo assistente contou como carregado'
printf '%s\n' "$out" | grep -q '^referências: lead/playbooks/bug.md, lead/reference/revisao.md$' \
  || fail "sem relatório: referências erradas ($(printf '%s\n' "$out" | grep '^referências'))"

out=$(node "$script" "$main" --agent explore);
printf '%s\n' "$out" | grep '^carregadas:' | grep -qw lead && fail '--agent explore: a pré-carga do lead continuou'

rel=$work/rel.txt
printf '%s\n' 'Princípios aplicados: tdd — vermelho antes do código — teste de regressão escrito antes da correção' \
  '- `wstack:query-plan` — plano no banco real — índice novo descartado' \
  'Referências lidas: reference/revisao.md — antes da revisão; playbooks/bug.md — depois de classificar' 'Limpeza: nada' > "$rel"
out=$(node "$script" "$main" "$work/subagents" --report "$rel"); code=$?
[ "$code" = 0 ] || fail "relatório coerente: código $code ($out)"
printf '%s\n' "$out" | grep -q '^citadas: query-plan, tdd$' || fail "relatório coerente: citadas erradas ($out)"

printf '%s\n' 'Princípios aplicados: domain-modeling — invariantes — agregado novo' 'Referências lidas: reference/revisao.md — antes; reference/arena.md — no plano' > "$rel"
out=$(node "$script" "$main" --report "$rel"); code=$?
[ "$code" = 3 ] || fail "citação sem leitura: código $code"
printf '%s\n' "$out" | grep -q '^SEM LEITURA: domain-modeling' || fail 'citação sem leitura: skill não acusada'
printf '%s\n' "$out" | grep -q '^SEM LEITURA: .*reference/arena.md' || fail 'citação sem leitura: referência não acusada'

# separador com meia-risca ou hífen no lugar do travessão: mesma skill, sem falso "sem leitura"
for sep in '–' '-'; do
  printf 'Princípios aplicados: tdd %s vermelho antes %s teste novo\nReferências lidas: reference/revisao.md %s antes\n' "$sep" "$sep" "$sep" > "$rel"
  out=$(node "$script" "$main" --report "$rel"); code=$?
  [ "$code" = 0 ] || fail "separador '$sep': código $code ($out)"
done
# referência de outra skill sem o prefixo dela, e com o prefixo errado
use Read '{"file_path":"/h/.claude/plugins/cache/wstack/wstack/0.0.13/skills/performance/reference/dotnet.md"}' > "$work/perf.jsonl"
printf 'Princípios aplicados: nenhum\nReferências lidas: reference/dotnet.md — antes do benchmark\n' > "$rel"
node "$script" "$work/perf.jsonl" --report "$rel" > /dev/null; code=$?
[ "$code" = 0 ] || fail "referência de outra skill sem prefixo: código $code"
printf 'Princípios aplicados: nenhum\nReferências lidas: query-plan/reference/dotnet.md — antes\n' > "$rel"
node "$script" "$work/perf.jsonl" --report "$rel" > /dev/null; code=$?
[ "$code" = 3 ] || fail "referência com prefixo de outra skill: código $code"
# frontmatter de agente com CRLF: a pré-carga continua valendo (agente sintético numa cópia do plugin)
plug=$work/plug; mkdir -p "$plug/scripts" "$plug/agents"; cp "$script" "$plug/scripts/"
printf -- '---\r\nname: crlf\r\nskills:\r\n  - security\r\n---\r\n# x\r\n' > "$plug/agents/crlf.md"
out=$(node "$plug/scripts/principles.mjs" "$main" --agent crlf)
printf '%s\n' "$out" | grep '^carregadas:' | grep -qw security || fail "frontmatter CRLF: pré-carga ignorada ($out)"

printf 'Princípios aplicados: nenhum\nReferências lidas: nenhuma\n' > "$rel"
node "$script" "$main" --report "$rel" > /dev/null; code=$?
[ "$code" = 0 ] || fail "nenhum princípio: código $code"
printf 'Resumo: x\n' > "$rel"
node "$script" "$main" --report "$rel" > /dev/null; code=$?
[ "$code" = 3 ] || fail "campo ausente: código $code"

node "$script" > /dev/null 2>&1; [ $? = 2 ] || fail 'sem argumento: código diferente de 2'
node "$script" "$main" --agent '../x' > /dev/null 2>&1; [ $? = 2 ] || fail '--agent com caminho: código diferente de 2'
node "$script" "$work/nao-existe.jsonl" > /dev/null 2>&1; [ $? = 1 ] || fail 'transcrição ausente: código diferente de 1'

if [ "$fails" -eq 0 ]; then echo 'test-principles: todos os casos passaram'; exit 0; fi
echo "test-principles: $fails falha(s)"
exit 1
