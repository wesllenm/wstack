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
# o limite de comentários conta a restrição junto: separar a categoria não afrouxa o --gate
printf 'class A {\n  // nunca nulo aqui\n  // sempre em UTC\n}\n' > "$repo/src/A.cs"
run --gate --text
[ "$code" = 1 ] || fail "gate: duas restrições acima do limite 1 não reprovaram (código $code)"
grep -q 'COMENTARIO 2 > 1' <<< "$out" || fail "gate: motivo ($out)"
# TODO continua MARCADOR (o gate mais estrito), mesmo com palavra de restrição
printf 'class A {\n  // TODO não esquecer\n}\n' > "$repo/src/A.cs"
run --text
grep -q '^MARCADOR' <<< "$out" || fail "marcador: TODO com 'não' deixou de ser MARCADOR ($out)"
# JSON traz o total novo
run
node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit("RESTRICAO" in j.totals?0:1)' <<< "$out" 2> /dev/null \
  || fail "json: totals sem RESTRICAO ($out)"

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
