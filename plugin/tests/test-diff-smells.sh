#!/usr/bin/env bash
# Casos do diff-smells.mjs (válvulas de escape e comentários nas linhas que o diff adicionou), num repositório git
# temporário. Sem rede.
# Uso: test-diff-smells.sh [<diff-smells.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

script=${1:-$(dirname "$0")/../scripts/diff-smells.mjs}
[ -f "$script" ] || { echo "diff-smells.mjs não encontrado" >&2; exit 2; }
script=$(cd "$(dirname "$script")" && pwd)/$(basename "$script")
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-ds-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

repo=$work/repo
git init -q "$repo"
gitc() { git -C "$repo" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$repo/src" "$repo/.claude"
printf 'class A {\n  void M() { }\n}\n' > "$repo/src/A.cs"
printf 'base = main\nsmell_comment_limit = 1\n' > "$repo/.claude/risk.conf"
gitc add -A && gitc commit -qm base && gitc branch -q -M main
run() { out=$(cd "$repo" && node "$script" "$@" 2> "$work/err"); code=$?; err=$(cat "$work/err"); }

# caminho feliz: comentário de restrição sai como RESTRICAO, com arquivo e linha
printf 'class A {\n  // não chamar antes de Init()\n  void M() { }\n  // must be called after Start\n  // calcula o total pela quantidade\n}\n' > "$repo/src/A.cs"
run --text
[ "$code" = 0 ] || fail "restrição: código $code ($err)"
grep -q '^RESTRICAO *src/A.cs:2  não  | // não chamar antes de Init()$' <<< "$out" || fail "restrição: sem o sinal em src/A.cs:2 ($out)"
grep -q '^RESTRICAO *src/A.cs:4  must ' <<< "$out" || fail "restrição em inglês: sem o sinal em src/A.cs:4 ($out)"
grep -q '^COMENTARIO *src/A.cs:5' <<< "$out" || fail "comentário comum: não ficou COMENTARIO ($out)"
grep -q 'RESTRICAO=2' <<< "$out" || fail "restrição: total ($out)"
# "não" dentro de outra palavra não conta (naoMexer, denao)
printf 'class A {\n  // denaoexiste nunquinha\n}\n' > "$repo/src/A.cs"
run --text
grep -q '^RESTRICAO' <<< "$out" && fail "palavra parcial: virou RESTRICAO ($out)"
# RESTRICAO é só sinal: comentários descritivos ("sempre retorna uma lista") não bloqueiam o --gate
printf 'class A {\n  // nunca nulo aqui\n  // sempre retorna uma lista\n  // deve vir ordenado\n}\n' > "$repo/src/A.cs"
run --gate --text
[ "$code" = 0 ] || fail "gate: três restrições acima do limite 1 reprovaram (código $code, $out)"
grep -q 'RESTRICAO=3' <<< "$out" || fail "gate: restrições não sinalizadas ($out)"
# o limite continua valendo para os comentários comuns
printf 'class A {\n  // calcula o total\n  // soma o frete\n}\n' > "$repo/src/A.cs"
run --gate --text
[ "$code" = 1 ] && grep -q 'COMENTARIO 2 > 1' <<< "$out" || fail "gate: dois comentários comuns acima do limite 1 não reprovaram (código $code, $out)"
# documentação (///, <remarks>) e continuação de bloco também são procuradas, como sinal
printf 'class A {\n  /// <remarks>Deve ser chamado depois de Init().</remarks>\n  void M() { }\n  /* calcula o total\n   * nunca com lista vazia */\n}\n' > "$repo/src/A.cs"
run --text
grep -q '^RESTRICAO *src/A.cs:2  doc: deve ' <<< "$out" || fail "/// com restrição: sem o sinal ($out)"
grep -q '^RESTRICAO *src/A.cs:5  nunca ' <<< "$out" || fail "continuação de bloco com restrição: sem o sinal ($out)"
grep -q '^DOC *src/A.cs:2' <<< "$out" && fail "/// com restrição: contou como DOC em vez de RESTRICAO ($out)"
# TODO continua MARCADOR (o gate mais estrito), mesmo com palavra de restrição
printf 'class A {\n  // TODO não esquecer\n}\n' > "$repo/src/A.cs"
run --text
grep -q '^MARCADOR' <<< "$out" || fail "marcador: TODO com 'não' deixou de ser MARCADOR ($out)"
# JSON traz o total novo
run
node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit("RESTRICAO" in j.totals?0:1)' <<< "$out" 2> /dev/null \
  || fail "json: totals sem RESTRICAO ($out)"

# smell_exclude é exceção com validade: vencida ou sem data não exclui o arquivo
mkdir -p "$repo/src/Interop"
printf 'class B {\n  // TODO legado\n}\n' > "$repo/src/Interop/B.cs"
printf 'smell_exclude = **/Interop/** | vence: 2999-12-31 | motivo: código gerado de interop\n' > "$repo/.claude/risk.conf"
run --text; grep -q 'src/Interop/B.cs' <<< "$out" && fail "smell_exclude válido: não excluiu ($out)"
for l in 'smell_exclude = **/Interop/**' 'smell_exclude = **/Interop/** | vence: 2000-01-01 | motivo: velho'; do
  printf '%s\n' "$l" > "$repo/.claude/risk.conf"
  run --text; grep -q '^MARCADOR *src/Interop/B.cs' <<< "$out" || fail "smell_exclude sem validade ('$l'): excluiu o arquivo ($out)"
done
rm -rf "$repo/src/Interop"; printf 'base = main\nsmell_comment_limit = 1\n' > "$repo/.claude/risk.conf"

# prosa com cara de código não é código comentado; código de verdade continua sendo
printf 'class A {\n  // Init() precisa vir antes da carga;\n  // Calcula(x) arredonda para baixo\n  // var total = itens.Sum();\n  // conta.Saldo -= valor;\n}\n' > "$repo/src/A.cs"
run --text
grep -q '^CODIGO_COMENTADO *src/A.cs:2' <<< "$out" && fail "prosa terminada em ';' virou código comentado ($out)"
grep -q '^CODIGO_COMENTADO *src/A.cs:3' <<< "$out" && fail "prosa com Calcula(x) virou código comentado ($out)"
grep -q '^CODIGO_COMENTADO *src/A.cs:4' <<< "$out" || fail "código comentado (var ... ;) não foi pego ($out)"
grep -q '^CODIGO_COMENTADO *src/A.cs:5' <<< "$out" || fail "código comentado (atribuição) não foi pego ($out)"
# comentário -- de SQL
mkdir -p "$repo/db"
printf 'SELECT 1;\n-- TODO trocar por view\n-- SELECT * FROM pedidos;\n-- nunca apagar esta coluna\n' > "$repo/db/a.sql"
run --text
grep -q '^MARCADOR *db/a.sql:2' <<< "$out" || fail "SQL: TODO em -- não foi pego ($out)"
grep -q '^CODIGO_COMENTADO *db/a.sql:3' <<< "$out" || fail "SQL: SELECT comentado não foi pego ($out)"
grep -q '^RESTRICAO *db/a.sql:4' <<< "$out" || fail "SQL: restrição em -- não foi pega ($out)"
rm -rf "$repo/db"
# comentário de SQL removido e readicionado (movido) não é novo: a linha removida "-- x" é conteúdo, não cabeçalho
mkdir -p "$repo/db"
printf -- '-- TODO legado\nSELECT 1;\n' > "$repo/db/b.sql"
gitc add -A && gitc commit -qm 'sql base'
printf 'SELECT 1;\n-- TODO legado\n' > "$repo/db/b.sql"
run --base HEAD --text
grep -q '^MARCADOR *db/b.sql' <<< "$out" && fail "SQL movido: comentário removido e readicionado contou como novo ($out)"
# linha adicionada que começa com "++ " não confunde o parser: o comentário da linha seguinte continua sendo lido
printf '++ cabecalho falso\n-- TODO novo\nSELECT 1;\n' > "$repo/db/b.sql"
run --base HEAD --text
grep -q '^MARCADOR *db/b.sql:2' <<< "$out" || fail "linha '++ ': o parser perdeu a linha seguinte ($out)"
git -C "$repo" rm -q -r -f db && gitc commit -qm 'sem sql'
# prefixo do diff fora do padrão na config do usuário (diff.noprefix) e caminho entre aspas
git -C "$repo" config diff.noprefix true
printf 'class B {\n  // TODO x\n}\n' > "$repo/src/B.cs"
git -C "$repo" add src/B.cs
printf 'class C {\n  // TODO y\n}\n' > "$repo/src/a\"c.cs"
git -C "$repo" add 'src/a"c.cs'
run --text
grep -q '^MARCADOR *src/B.cs:2' <<< "$out" || fail "diff.noprefix: caminho errado ($out)"
grep -qF 'MARCADOR         src/a"c.cs:2' <<< "$out" || fail "caminho entre aspas: não foi lido ($out)"
git -C "$repo" rm -q --cached src/B.cs 'src/a"c.cs'; rm -f "$repo/src/B.cs" "$repo/src/a\"c.cs"; git -C "$repo" config --unset diff.noprefix
# base ausente (clone raso, sem a branch): a saída diz e o --gate reprova, mesmo sem nenhum sinal
printf 'class A {\n}\n' > "$repo/src/A.cs"
printf 'base = nao-existe\n' > "$repo/.claude/risk.conf"
run --gate --text
[ "$code" = 1 ] || fail "base ausente: --gate não reprovou (código $code, $out)"
grep -q 'BASE nao-existe não encontrada: comparado só com HEAD' <<< "$out" || fail "base ausente: saída não diz ($out)"
run
node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit(j.base_missing==="nao-existe"?0:1)' <<< "$out" 2> /dev/null || fail "base ausente: JSON sem base_missing ($out)"
printf 'base = main\nsmell_comment_limit = 1\n' > "$repo/.claude/risk.conf"

# falha e entrada malformada: fora de repositório é 3, argumento desconhecido é 2, limite inválido no risk.conf é 3
mkdir -p "$work/fora"
out=$(cd "$work/fora" && GIT_CEILING_DIRECTORIES=$work node "$script" --text 2>&1); code=$?
[ "$code" = 3 ] || fail "fora do git: código $code, esperado 3 ($out)"
run --xpto; [ "$code" = 2 ] || fail "argumento desconhecido: código $code, esperado 2"
run --base; [ "$code" = 2 ] || fail "--base sem valor: código $code, esperado 2"
printf 'smell_comment_limit = muitos\n' > "$repo/.claude/risk.conf"
run --text; [ "$code" = 3 ] || fail "limite inválido: código $code, esperado 3 ($err)"

if [ "$fails" -eq 0 ]; then echo 'test-diff-smells: todos os casos passaram'; exit 0; fi
echo "test-diff-smells: $fails falha(s)"
exit 1
