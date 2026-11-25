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

node "$script" > /dev/null 2>&1; [ $? = 2 ] || fail 'sem argumento: código diferente de 2'
node "$script" "$work/nao-existe.txt" > /dev/null 2>&1; [ $? = 2 ] || fail 'arquivo ausente: código diferente de 2'

if [ "$fails" -eq 0 ]; then echo 'test-slop-check: todos os casos passaram'; exit 0; fi
echo "test-slop-check: $fails falha(s)"
exit 1
