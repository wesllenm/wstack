#!/usr/bin/env bash
# Casos dos destinos de documento (doc-paths.mjs, chaves doc_* do risk.conf) e dos que os leem: o SessionStart, o
# pr-risk-gate, o summarize-runs e o bootstrap. O verify-on-stop tem os casos dele em test-verify-on-stop.sh. Sem rede.
# Uso: test-doc-paths.sh [<pasta do plugin>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

plugin=$(cd "${1:-$(dirname "$0")/..}" && pwd -P)
[ -f "$plugin/hooks/doc-paths.mjs" ] || { echo "doc-paths.mjs não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-docp-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU [$1]: $2"; fails=$((fails + 1)); }

proj() { # proj <nome> <linha do risk.conf>...: repositório com o risk.conf dado
  local p="$work/$1"; shift
  git init -q "$p" && mkdir -p "$p/.claude"
  : > "$p/.claude/risk.conf"; local l; for l in "$@"; do printf '%s\n' "$l" >> "$p/.claude/risk.conf"; done
  printf '%s' "$p"
}
paths() { (cd "$1" && CLAUDE_PROJECT_DIR=$1 node "$plugin/hooks/doc-paths.mjs"); }
session() { (cd "$1" && CLAUDE_PROJECT_DIR=$1 node "$plugin/hooks/doc-paths.mjs" --session); }

# sem chave: os padrões, e o SessionStart não diz nada
p=$(proj padrao 'base = HEAD')
want=$'decisions=docs/decisions.md\ngotchas=docs/gotchas.md\ngotchas_dir=docs/gotchas\ncalibration=docs/review-calibration.md\nrubric=docs/review-rubric.md\nstate='
[ "$(paths "$p")" = "$want" ] || fail padroes "$(paths "$p" | tr '\n' ' ')"
[ -z "$(session "$p")" ] || fail padrao-calado "$(session "$p")"
# chave apontada: vale a última linha; barra no fim sai; valor fora da forma é ignorado e avisado
p=$(proj trocado 'doc_decisions = docs/x.md' 'doc_decisions = .claude/decisions.md' 'doc_gotchas = docs/SINTOMAS.md' \
  'doc_gotchas_dir = docs/sintomas/' 'doc_state = docs/ESTADO.md' 'doc_rubric = ../fora.md' 'doc_calibration = /etc/x' \
  'doc_gotchas_dir = docs/sintomas/')
mkdir -p "$p/docs" && touch "$p/.claude/decisions.md" "$p/docs/ESTADO.md"
out=$(paths "$p")
for l in decisions=.claude/decisions.md gotchas=docs/SINTOMAS.md gotchas_dir=docs/sintomas state=docs/ESTADO.md \
  rubric=docs/review-rubric.md calibration=docs/review-calibration.md; do
  grep -qxF "$l" <<< "$out" || fail "destino $l" "$(tr '\n' ' ' <<< "$out")"
done
s=$(session "$p")
for t in 'doc_rubric do risk.conf ignorado' 'doc_calibration do risk.conf ignorado' 'doc_gotchas = docs/SINTOMAS.md do risk.conf não existe' \
  'decisões em .claude/decisions.md' 'pendência e onde paramos em docs/ESTADO.md' 'o .claude/SESSION.md guarda só o estado local'; do
  grep -qF -- "$t" <<< "$s" || fail "session: $t" "$s"
done
grep -qF 'doc_decisions = .claude/decisions.md do risk.conf não existe' <<< "$s" && fail session-existe-nao-avisa "$s"
for c in 'doc_decisions = a/../b.md' 'doc_decisions = -x.md' 'doc_decisions = a b.md' 'doc_decisions = $(id).md'; do
  q=$(proj "inv-$RANDOM" "$c")
  grep -qx 'decisions=docs/decisions.md' <<< "$(paths "$q")" || fail "inválido vale o padrão: $c" "$(paths "$q" | head -1)"
done
# o SessionStart imprime os destinos (o hook chama o doc-paths)
out=$(printf '{"session_id":"s1"}' | CLAUDE_PLUGIN_ROOT=$plugin CLAUDE_PROJECT_DIR=$p bash "$plugin/hooks/session-start.sh" 2> /dev/null)
grep -qF 'decisões em .claude/decisions.md' <<< "$out" || fail session-start "$out"

# pr-risk-gate: o núcleo dos gotchas configurado nunca é "só documentação", então não entra sozinho como TRIVIAL
gate() { # gate <projeto> <arquivo alterado>: o auto_merge do veredito
  printf '%s\n' "$2" > "$work/files.txt"; printf '{"author":"a","labels":["risco:trivial"]}' > "$work/pr.json"; : > "$work/rev.jsonl"
  (cd "$1" && node "$plugin/scripts/pr-risk-gate.mjs" --files "$work/files.txt" --pr "$work/pr.json" --reviews "$work/rev.jsonl" | jq -r .auto_merge)
}
[ "$(gate "$p" docs/SINTOMAS.md)" = false ] || fail gate-gotchas-configurado "$(gate "$p" docs/SINTOMAS.md)"
[ "$(gate "$p" docs/gotchas.md)" = false ] || fail gate-gotchas-padrao "$(gate "$p" docs/gotchas.md)"
[ "$(gate "$p" docs/guia.md)" = true ] || fail gate-doc-comum "$(gate "$p" docs/guia.md)"

# summarize-runs: o Registro vem do doc_calibration
r=$(proj resumo 'doc_calibration = docs/calibracao.md'); mkdir -p "$r/docs"
printf -- '- 2026-11-20 — tarefa — SIMPLES — 1 confirmados\n' > "$r/docs/calibracao.md"
printf -- '- 2026-11-20 — outra — COMPLEXA\n- 2026-11-21 — mais — TRIVIAL\n' > "$r/docs/review-calibration.md"
n=$(cd "$r" && CLAUDE_PROJECT_DIR=$r node "$plugin/scripts/summarize-runs.mjs" --json | jq -r '.tasks.total')
[ "$n" = 1 ] || fail summarize-registro-configurado "tarefas: $n"

# bootstrap: com doc_* num risk.conf que já existe, o modelo vai para o destino e as citações do padrão viram o destino
b=$(proj boot 'doc_decisions = .claude/decisions.md' 'doc_gotchas = docs/SINTOMAS.md')
git -C "$b" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
(cd "$b" && bash "$plugin/scripts/bootstrap.sh" > "$work/boot.out" 2>&1)
[ -f "$b/.claude/decisions.md" ] || fail bootstrap-decisoes "$(grep -i decis "$work/boot.out")"
[ -f "$b/docs/SINTOMAS.md" ] || fail bootstrap-gotchas "$(grep -i gotcha "$work/boot.out")"
[ -e "$b/docs/decisions.md" ] && fail bootstrap-sem-padrao 'criou docs/decisions.md também'
grep -qx '@docs/SINTOMAS.md' "$b/CLAUDE.md" || fail bootstrap-import "$(grep -n '^@' "$b/CLAUDE.md")"
grep -qF '`.claude/decisions.md`' "$b/CLAUDE.md" || fail bootstrap-citacao "$(grep -n decis "$b/CLAUDE.md")"

if [ "$fails" -eq 0 ]; then echo "test-doc-paths: todos os casos passaram"; exit 0; fi
echo "test-doc-paths: $fails falha(s)"
exit 1
