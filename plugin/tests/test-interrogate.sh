#!/usr/bin/env bash
# Casos do interrogate.mjs (pacote de revisão para modelos de outro fornecedor, configurados no risk.conf), com modelos
# falsos: scripts bash que leem o pedido da entrada padrão e devolvem uma resposta fixa. Sem rede e sem modelo.
# Uso: test-interrogate.sh [<interrogate.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

script=${1:-$(dirname "$0")/../scripts/interrogate.mjs}
[ -f "$script" ] || { echo "interrogate.mjs não encontrado" >&2; exit 2; }
script=$(cd "$(dirname "$script")" && pwd)/$(basename "$script")
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-it-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

repo=$work/repo
mkdir -p "$repo/.claude" "$work/bin"
git -C "$repo" init -q
printf 'diff --git a/src/a.cs b/src/a.cs\n+var total = itens.Sum(i => i.Preco);\nMARCADOR-DO-PACOTE\n' > "$work/pacote.txt"
: > "$work/vazio.txt"

# modelo que só responde se recebeu a instrução e o pacote, com texto antes da lista (deve ser cortado)
cat > "$work/bin/ataca.sh" <<'EOF'
entrada=$(cat)
case $entrada in *"revisor adversarial"*MARCADOR-DO-PACOTE*) ;; *) echo "pedido incompleto"; exit 0 ;; esac
cat <<'R'
Claro, seguem os achados:
- id: interrogate-1
  categoria: correctness
  severidade: importante
  confiança: 80
  local: src/a.cs:1
  trecho: |
    var total = itens.Sum(i => i.Preco);
  evidência: src/a.cs:1 — soma sem quantidade
  cenário: item com quantidade 2 → total pela metade
  correção mínima: multiplicar pela quantidade
  preexistente: não
R
EOF
printf 'cat > /dev/null; echo "sem achados"\n' > "$work/bin/limpo.sh"
printf 'cat > /dev/null; echo "acho que está tudo certo"\n' > "$work/bin/prosa.sh"
printf 'cat > /dev/null; echo "chave ausente" >&2; exit 1\n' > "$work/bin/quebra.sh"
printf 'cat > /dev/null; sleep 5; echo "sem achados"\n' > "$work/bin/lento.sh"

# item completo no formato da rubrica; os modelos abaixo o reaproveitam
cat > "$work/item.txt" <<'EOF'
- id: interrogate-1
  categoria: correctness
  severidade: importante
  confiança: 80
  local: src/a.cs:1
  trecho: |
    var total = itens.Sum(i => i.Preco);
  evidência: src/a.cs:1 — soma sem quantidade
  cenário: item com quantidade 2 → total errado
  correção mínima: multiplicar pela quantidade
  preexistente: não
EOF
# o "á" de "há" sai partido entre duas escritas (bytes c3 e a1 separados), como um pedaço de pipe pode cortar
cat > "$work/bin/partido.sh" <<EOF
cat > /dev/null
sed -n '1,8p' "$work/item.txt"
printf '  cenário: total errado quando h\303'; sleep 0.3; printf '\241 dois itens\n'
sed -n '10,11p' "$work/item.txt"
EOF
# prosa depois da lista
printf 'cat > /dev/null; cat "%s"; printf "\\nEspero ter ajudado! Qualquer coisa, chame.\\n"\n' "$work/item.txt" > "$work/bin/fecho.sh"
# um item completo e um incompleto
printf 'cat > /dev/null; cat "%s"; printf -- "- id: interrogate-2\\n  local: src/a.cs:1\\n"\n' "$work/item.txt" > "$work/bin/meio.sh"
# só itens incompletos
printf 'cat > /dev/null; printf -- "- id: x\\n  local: a.cs:1\\n"\n' > "$work/bin/oco.sh"
# "sem achados" com pontuação e negrito
printf 'cat > /dev/null; echo "**Sem achados.**"\n' > "$work/bin/pontuado.sh"

conf() { printf '%s\n' "$@" > "$repo/.claude/risk.conf"; }
run() { # run <pacote>: código de saída em $code, stderr em $err
  rm -f "$work"/saida*
  err=$(cd "$repo" && CLAUDE_PROJECT_DIR=$repo node "$script" "$1" "$work/saida.txt" 2>&1 > /dev/null)
  code=$?
}
expect() { # expect <caso> <código esperado>
  [ "$code" = "$2" ] || fail "$1: código $code, esperado $2 ($err)"
}

conf 'default_branch = main'
run "$work/pacote.txt"; expect 'sem interrogate_cmd' 10
[ ! -e "$work/saida.txt" ] || fail 'sem interrogate_cmd: gravou saída'

conf "interrogate_cmd = alfa bash $work/bin/ataca.sh"
run "$work/pacote.txt"; expect 'um modelo com achado' 0
grep -q '^- id: alfa-interrogate-1$' "$work/saida.txt" || fail 'um modelo com achado: id sem o prefixo do modelo'
grep -q 'Claro, seguem' "$work/saida.txt" && fail 'um modelo com achado: texto antes da lista não foi cortado'
grep -q 'pedido incompleto' "$work/saida.txt" && fail 'um modelo com achado: o modelo não recebeu instrução e pacote'
[ -f "$work/saida.txt.alfa.bruto" ] || fail 'um modelo com achado: sem a resposta bruta'

conf "interrogate_cmd = zeta bash $work/bin/partido.sh"
run "$work/pacote.txt"; expect 'acento partido entre pedaços' 0
grep -q 'cenário: total errado quando há dois itens' "$work/saida.txt" || fail 'acento partido: texto corrompido na saída'

conf "interrogate_cmd = eta bash $work/bin/fecho.sh"
run "$work/pacote.txt"; expect 'prosa depois da lista' 0
grep -q 'Espero' "$work/saida.txt" && fail 'prosa depois da lista: foi para a saída'
grep -q '^- id: eta-interrogate-1$' "$work/saida.txt" || fail 'prosa depois da lista: perdeu o item'

conf "interrogate_cmd = teta bash $work/bin/meio.sh"
run "$work/pacote.txt"; expect 'item incompleto junto de completo' 0
grep -q 'teta-interrogate-2' "$work/saida.txt" && fail 'item incompleto: foi para a saída'
printf '%s' "$err" | grep -q '1 sem campo obrigatório descartado' || fail "item incompleto: descarte não informado ($err)"

conf "interrogate_cmd = iota bash $work/bin/oco.sh"
run "$work/pacote.txt"; expect 'todos os itens incompletos' 3

conf "interrogate_cmd = kapa bash $work/bin/pontuado.sh"
run "$work/pacote.txt"; expect '"sem achados" pontuado' 0
[ "$(cat "$work/saida.txt")" = 'sem achados' ] || fail '"sem achados" pontuado: saída diferente'

conf "interrogate_cmd = beta bash $work/bin/limpo.sh"
run "$work/pacote.txt"; expect 'sem achados' 0
[ "$(cat "$work/saida.txt")" = 'sem achados' ] || fail 'sem achados: saída diferente de "sem achados"'

conf "interrogate_cmd = alfa bash $work/bin/ataca.sh" "interrogate_cmd = gama bash $work/bin/quebra.sh"
run "$work/pacote.txt"; expect 'um modelo falha' 3
grep -q '^- id: alfa-interrogate-1$' "$work/saida.txt" || fail 'um modelo falha: perdeu os achados do que respondeu'
printf '%s' "$err" | grep -q 'gama — saiu com código 1' || fail 'um modelo falha: motivo ausente no stderr'

conf "interrogate_cmd = delta bash $work/bin/lento.sh" 'interrogate_timeout = 1'
inicio=$SECONDS
run "$work/pacote.txt"; expect 'prazo esgotado' 3
[ $((SECONDS - inicio)) -lt 4 ] || fail 'prazo esgotado: não matou o modelo no prazo'

conf "interrogate_cmd = eps bash $work/bin/prosa.sh"
run "$work/pacote.txt"; expect 'resposta fora do formato' 3

conf 'interrogate_cmd = Nome-Inválido bash x'
run "$work/pacote.txt"; expect 'nome inválido' 2
conf "interrogate_cmd = alfa bash $work/bin/ataca.sh" "interrogate_cmd = alfa bash $work/bin/limpo.sh"
run "$work/pacote.txt"; expect 'nome repetido' 2
conf "interrogate_cmd = alfa bash $work/bin/ataca.sh" 'interrogate_timeout = 0'
run "$work/pacote.txt"; expect 'prazo inválido' 2
conf "interrogate_cmd = alfa bash $work/bin/ataca.sh"
run "$work/vazio.txt"; expect 'pacote vazio' 2
run "$work/nao-existe.txt"; expect 'pacote ausente' 2

if [ "$fails" -eq 0 ]; then echo 'test-interrogate: todos os casos passaram'; exit 0; fi
echo "test-interrogate: $fails falha(s)"
exit 1
