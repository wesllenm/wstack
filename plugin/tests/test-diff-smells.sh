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
