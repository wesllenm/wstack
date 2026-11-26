#!/usr/bin/env bash
# Casos do map-staleness.mjs (aviso de mapa de features da verify-<app> desatualizado), num repositório git
# temporário. Sem rede.
# Uso: test-map-staleness.sh [<map-staleness.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

script=${1:-$(dirname "$0")/../scripts/map-staleness.mjs}
[ -f "$script" ] || { echo "map-staleness.mjs não encontrado" >&2; exit 2; }
script=$(cd "$(dirname "$script")" && pwd)/$(basename "$script")
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-ms-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

repo=$work/repo
git init -q "$repo"
gitc() { git -C "$repo" -c user.email=t@t -c user.name=t "$@"; }
run() { out=$(CLAUDE_PROJECT_DIR=$repo node "$script" "$@" 2>&1); code=$?; }
mkdir -p "$repo/.claude/skills/verify-web/features" "$repo/src/Endpoints" "$repo/src/Interno"
printf 'feature_surface = src/**/Endpoints/**\n' > "$repo/.claude/risk.conf"
printf '# Mapa\n' > "$repo/.claude/skills/verify-web/features/README.md"
printf 'x\n' > "$repo/src/Endpoints/Pedidos.cs"
gitc add -A && gitc commit -qm mapa

# em dia: silencioso, e --verbose diz que está em dia
run; [ "$code" = 0 ] && [ -z "$out" ] || fail "em dia: código $code, saída ($out)"
run --verbose; grep -q 'Mapa de features de verify-web em dia' <<< "$out" || fail "em dia --verbose: ($out)"
# commit fora da superfície não avisa
printf 'y\n' > "$repo/src/Interno/Calculo.cs" && gitc add -A && gitc commit -qm interno
run; [ -z "$out" ] || fail "fora da superfície: avisou ($out)"
# commit na superfície avisa, com o arquivo, o comando de manutenção e o commit de partida
sha=$(git -C "$repo" log -1 --format=%H -- .claude/skills/verify-web/features)
printf 'z\n' >> "$repo/src/Endpoints/Pedidos.cs" && gitc commit -qam endpoint
run; [ "$code" = 0 ] || fail "desatualizado: código $code"
grep -q 'pode estar desatualizado: 1 commit(s)' <<< "$out" || fail "desatualizado: contagem ($out)"
grep -q 'src/Endpoints/Pedidos.cs' <<< "$out" || fail "desatualizado: sem o arquivo ($out)"
grep -qF '/verify-web manutenção' <<< "$out" || fail "desatualizado: sem o comando de manutenção ($out)"
grep -qF "a partir de ${sha:0:12}" <<< "$out" || fail "desatualizado: sem o commit de partida ($out)"
# mapa atualizado depois volta a ficar em dia
printf -- '- pedidos\n' >> "$repo/.claude/skills/verify-web/features/README.md" && gitc commit -qam 'mapa em dia'
run; [ -z "$out" ] || fail "mapa atualizado: ainda avisa ($out)"

# mapa nunca commitado: avisa para provar e commitar
mkdir -p "$repo/.claude/skills/verify-api/features" && printf '# Mapa\n' > "$repo/.claude/skills/verify-api/features/README.md"
run; grep -q 'Mapa de features de verify-api ainda não commitado' <<< "$out" || fail "não commitado: ($out)"
rm -rf "$repo/.claude/skills/verify-api"

# falha e entrada malformada nunca derrubam a sessão: fora de repositório e risk.conf com linha estranha saem 0
mkdir -p "$work/fora"
out=$(cd "$work/fora" && CLAUDE_PROJECT_DIR=$work/fora GIT_CEILING_DIRECTORIES=$work node "$script" 2>&1); code=$?
[ "$code" = 0 ] && [ -z "$out" ] || fail "fora do git: código $code, saída ($out)"
printf 'feature_surface = [[[\nlixo sem igual\n' > "$repo/.claude/risk.conf"
run; [ "$code" = 0 ] || fail "risk.conf malformado: código $code ($out)"
# sem feature_surface, conta todo código fora de testes e diz isso
: > "$repo/.claude/risk.conf"
printf 'w\n' > "$repo/src/Interno/Outro.cs" && gitc add -A && gitc commit -qm outro
run; grep -q 'feature_surface não configurado' <<< "$out" || fail "sem feature_surface: não disse ($out)"

if [ "$fails" -eq 0 ]; then echo 'test-map-staleness: todos os casos passaram'; exit 0; fi
echo "test-map-staleness: $fails falha(s)"
exit 1
