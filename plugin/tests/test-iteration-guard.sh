#!/usr/bin/env bash
# Casos do iteration-guard.sh (PostToolUse: limite de edições sem commit), num repositório git temporário. Sem rede.
# Uso: test-iteration-guard.sh [<iteration-guard.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

hook=${1:-$(dirname "$0")/../hooks/iteration-guard.sh}
[ -f "$hook" ] || { echo "iteration-guard.sh não encontrado" >&2; exit 2; }
hook=$(cd "$(dirname "$hook")" && pwd)/$(basename "$hook")
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-ig-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

repo=$work/repo
git init -q "$repo" && mkdir -p "$repo/.claude"
printf 'iteration_limit = 3\n' > "$repo/.claude/risk.conf"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
edit() { printf '%s' "${1:-{\"session_id\":\"s1\",\"tool_name\":\"Edit\"\}}" | CLAUDE_PROJECT_DIR=$repo bash "$hook"; }

# abaixo do limite: silencioso
out=$(edit); out="$out$(edit)"
[ -z "$out" ] || fail "abaixo do limite: falou ($out)"
# no limite: block em JSON válido, com a regra das três tentativas, a premissa e o esboço
out=$(edit)
jq -e '.decision == "block"' <<< "$out" > /dev/null 2>&1 || fail "no limite: sem block em JSON válido ($out)"
reason=$(jq -r .reason <<< "$out" 2> /dev/null)
grep -q 'ataque a premissa' <<< "$reason" || fail "no limite: sem a regra da premissa ($reason)"
grep -q 'attack-the-premise' <<< "$reason" || fail "no limite: sem a skill attack-the-premise ($reason)"
grep -q 'descarte o esboço e volte ao plano' <<< "$reason" || fail "no limite: sem o descarte do esboço ($reason)"
# commit zera a contagem
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m unidade
out=$(edit); [ -z "$out" ] || fail "depois do commit: não zerou ($out)"

# entrada malformada: sem session_id, id fora do alfabeto (vira caminho) ou entrada que não é JSON saem 0 calados
for i in '{"tool_name":"Edit"}' '{"session_id":"../../fora"}' 'lixo'; do
  out=$(edit "$i"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ] || fail "entrada '$i': código $rc, saída ($out)"
done
[ ! -e "$work/fora.iter" ] && [ ! -e "$repo/fora.iter" ] || fail "session_id com ../ gravou fora de .claude/.session"
# limite 0 desliga
printf 'iteration_limit = 0\n' > "$repo/.claude/risk.conf"
for _ in 1 2 3 4; do out=$(edit); done
[ -z "$out" ] || fail "limite 0: avisou ($out)"

if [ "$fails" -eq 0 ]; then echo 'test-iteration-guard: todos os casos passaram'; exit 0; fi
echo "test-iteration-guard: $fails falha(s)"
exit 1
