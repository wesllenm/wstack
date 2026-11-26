#!/usr/bin/env bash
# Casos do slop-check.mjs (padrões da skill unslop em texto em português): cada erro, avisos, o que é ignorado (código
# entre crases, bloco cercado, rodapé de commit), fronteira de palavra com acento e que o texto da linha não sai na
# saída. Sem rede.
# Uso: test-slop-check.sh [<slop-check.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

script=${1:-$(dirname "$0")/../scripts/slop-check.mjs}
[ -f "$script" ] || { echo "slop-check.mjs não encontrado" >&2; exit 2; }
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-sc-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

check() { # check <caso> <código esperado> <padrão esperado na saída | -> <texto>
  printf '%s\n' "$4" > "$work/t.txt"
  out=$(node "$script" "$work/t.txt" 2> /dev/null); code=$?
  [ "$code" = "$2" ] || fail "$1: código $code, esperado $2 ($out)"
  if [ "$3" != - ]; then printf '%s\n' "$out" | grep -q -- "$3" || fail "$1: saída sem \"$3\" ($out)"; fi
}

check 'abertura vazia' 3 'erro: abertura vazia' 'Claro! Segue a correção.'
check 'claro no meio da frase' 0 - 'Deixa claro que a fila é idempotente.'
check 'fecho vazio' 3 'erro: fecho vazio' 'Qualquer dúvida, é só falar.'
check 'autorreferência' 3 'erro: autorreferência' 'Este commit adiciona o cache de preços.'
check 'autorreferência de PR' 3 'erro: autorreferência' 'Neste PR, o login muda.'
check 'muleta de ênfase' 3 'erro: muleta de ênfase' 'É importante ressaltar que o job roda à noite.'
check 'a nível de' 3 'erro: "a nível de"' 'Mudança a nível de banco.'
check 'gerundismo' 3 'erro: gerundismo' 'Vamos estar enviando o e-mail depois.'
check 'o mesmo como pronome' 3 'erro: "o mesmo" como pronome' 'O arquivo foi lido e o mesmo foi apagado.'
check 'o mesmo como adjetivo' 0 - 'Usa o mesmo cliente HTTP do pedido.'
check 'emoji' 3 'erro: emoji' 'Corrige o cálculo do frete 🚀'
check 'aviso sem erro' 0 'aviso: adjetivo vago' 'Torna o parser robusto contra entrada vazia.'
check 'aviso com acento' 0 'aviso: ganho sem número' 'A consulta ficou otimizada.'
check 'endereçar' 0 'aviso: "endereçar"' 'Endereça o problema do timeout.'
check 'não apenas mas também' 0 'aviso: "não apenas' 'Valida não apenas o e-mail, mas também o telefone.'
check 'texto limpo' 0 - 'Reduz o tempo do relatório de 420 ms para 90 ms: uma consulta em vez de uma por linha.'
check 'código entre crases' 0 - 'Troca `realizarValidacao` por `validar` e remove `ehRobusto`.'
check 'menção entre aspas' 0 - 'Tira do título o "este commit" e o “a nível de”.'
check 'uso fora das aspas' 3 'erro: autorreferência' 'Este commit troca o "robusto" por um número.'
check 'bloco cercado' 0 - $'Exemplo:\n```\n// Este commit adiciona isto\nvar robusto = 1;\n```\nFim.'
check 'rodapé do commit' 0 - $'Corrige o frete\n\nRefs: #12 este commit\nCo-Authored-By: Claude <noreply@anthropic.com>'

printf 'senha=SEGREDO-123 este commit robusto\n' > "$work/s.txt"
out=$(node "$script" "$work/s.txt" 2>&1)
printf '%s' "$out" | grep -q 'SEGREDO' && fail 'conteúdo da linha apareceu na saída'

# --pr: seções do corpo do PR na ordem da skill commit, com Por quê e Verificação, sem seção vazia, até 40 linhas
prcheck() { # prcheck <caso> <código esperado> <padrão esperado | -> <texto>
  printf '%s\n' "$4" > "$work/pr.txt"
  local out rc; out=$(node "$script" --pr "$work/pr.txt" 2> /dev/null); rc=$?
  [ "$rc" = "$2" ] || fail "--pr $1: código $rc, esperado $2 ($out)"
  [ "$3" = - ] || grep -qF -- "$3" <<< "$out" || fail "--pr $1: sem '$3' ($out)"
}
ok=$'Lote 9.\n\n## Por quê\nO frete saía errado.\n\n## O que mudou\n- `Frete.Calcular` soma o peso.\n\n## Raio de impacto\nSó o checkout.\n\n## Verificação\n- 12 testes passam.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n\nhttps://claude.ai/code/session_x'
prcheck 'no formato' 0 - "$ok"
prcheck 'fora de ordem' 3 'seção fora de ordem' $'## Por quê\nx\n\n## Verificação\ny\n\n## O que mudou\nz'
prcheck 'seção desconhecida' 3 'seção desconhecida' $'## Por quê\nx\n\n## Testes\ny\n\n## Verificação\nz'
prcheck 'seção repetida' 3 'seção repetida' $'## Por quê\nx\n\n## Por quê\ny\n\n## Verificação\nz'
prcheck 'seção vazia' 3 'seção vazia' $'## Por quê\nx\n\n## Escopo\n\n## Verificação\nz'
prcheck 'sem Verificação' 3 'seção obrigatória ausente no PR: ## Verificação' $'## Por quê\nx\n\n## O que mudou\ny'
prcheck 'longo' 3 'linhas de texto (máximo 40)' "$(printf '## Por quê\n'; for i in $(seq 1 40); do echo "linha $i"; done; printf '## Verificação\nok\n')"
prcheck 'padrões continuam valendo' 3 'erro: autorreferência' $'## Por quê\nEste PR corrige o frete.\n\n## Verificação\nok'
prcheck '### dentro de seção não conta' 0 - $'## Por quê\nx\n### Detalhe\ny\n\n## Verificação\nz'
# sem --pr, as seções não são conferidas
printf '## Testes\nx\n' > "$work/pr.txt"; node "$script" "$work/pr.txt" > /dev/null 2>&1; [ $? = 0 ] || fail 'sem --pr: conferiu as seções'
node "$script" --pr > /dev/null 2>&1; [ $? = 2 ] || fail '--pr sem arquivo: código diferente de 2'

node "$script" > /dev/null 2>&1; [ $? = 2 ] || fail 'sem argumento: código diferente de 2'
node "$script" "$work/nao-existe.txt" > /dev/null 2>&1; [ $? = 2 ] || fail 'arquivo ausente: código diferente de 2'

if [ "$fails" -eq 0 ]; then echo 'test-slop-check: todos os casos passaram'; exit 0; fi
echo "test-slop-check: $fails falha(s)"
exit 1
