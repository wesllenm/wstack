#!/usr/bin/env bash
# Casos do verify-on-stop (hook Stop), sem rede: os comandos de build, formato e teste vêm do .claude/risk.conf do
# projeto (verify_solution, verify_build, verify_lint, verify_test), não do arquivo do hook; sem eles, o gate de
# verificação não roda. O gate de aprendizado (commit de código na sessão exige registro no arquivo de calibração) só
# vale no projeto que tem esse arquivo: o plugin pode estar instalado para todos os repositórios da máquina.
# Uso: test-verify-on-stop.sh [<verify-on-stop.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

hook=${1:-$(dirname "$0")/../hooks/verify-on-stop.sh}
[ -f "$hook" ] || { echo "verify-on-stop.sh não encontrado: $hook" >&2; exit 2; }
hook=$(cd "$(dirname "$hook")" && pwd -P)/$(basename "$hook")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-vos-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
gitc() { git -C "$proj" -c user.email=t@t -c user.name=t "$@"; }

# projeto novo: risk.conf com as chaves dadas, um commit base e a sessão s1 registrada nele
novo() { # novo <linha do risk.conf>...
  proj=$(mktemp -d "$work/p-XXXX"); git init -q "$proj"; mkdir -p "$proj/.claude/.session"
  : > "$proj/.claude/risk.conf"; local l; for l in "$@"; do printf '%s\n' "$l" >> "$proj/.claude/risk.conf"; done
  printf 'x\n' > "$proj/a.txt"; gitc add -A; gitc commit -qm base
  gitc rev-parse HEAD > "$proj/.claude/.session/s1.base"
}
stop() { printf '{"session_id":"s1"}' | CLAUDE_PROJECT_DIR=$proj bash "$hook" > "$work/out" 2> "$work/err"; echo $?; }
expect() { # expect <código> <caso> [texto que o stderr precisa ter]
  local rc; rc=$(stop)
  [ "$rc" = "$1" ] || { echo "FALHOU [$2]: esperado código $1, obtido $rc: $(head -c 300 "$work/err")"; fails=$((fails + 1)); return; }
  [ $# -lt 3 ] || grep -qF -- "$3" "$work/err" || { echo "FALHOU [$2]: o motivo não cita '$3': $(head -c 300 "$work/err")"; fails=$((fails + 1)); }
}

# gate de verificação: os comandos do risk.conf rodam quando há mudança de código e o arquivo da solução existe
novo 'verify_solution = sol.txt' 'verify_build = true' 'verify_lint = ' 'verify_test = echo TESTE-RODOU; false'
printf 's\n' > "$proj/sol.txt"; printf 'mudou\n' >> "$proj/a.txt"
expect 2 verificacao-falha 'TESTE-RODOU'
sed -i 's/^verify_test = .*/verify_test = true/' "$proj/.claude/risk.conf"
expect 0 verificacao-passa
[ -s "$proj/.claude/.verify-ok" ] || { echo "FALHOU [verificacao-passa]: sem o carimbo .verify-ok"; fails=$((fails + 1)); }
novo 'verify_solution = sol.txt' 'verify_build = false' 'verify_test = true'
printf 's\n' > "$proj/sol.txt"; printf 'mudou\n' >> "$proj/a.txt"
expect 2 build-falha 'Verificação falhou'
novo 'verify_solution = sol.txt' 'verify_build = true' 'verify_lint = false' 'verify_test = true'
printf 's\n' > "$proj/sol.txt"; printf 'mudou\n' >> "$proj/a.txt"
expect 2 formato-falha 'Verificação falhou'
# sem o arquivo da solução (projeto ainda sem código) ou sem as chaves, não há o que verificar
novo 'verify_solution = sol.txt' 'verify_build = false' 'verify_test = false'
printf 'mudou\n' >> "$proj/a.txt"
expect 0 sem-solucao
novo '# nada de verificação'
printf 'mudou\n' >> "$proj/a.txt"
expect 0 sem-chaves
# a chave repetida vale a última linha (como nos outros hooks)
novo 'verify_solution = sol.txt' 'verify_build = false' 'verify_build = true' 'verify_test = true'
printf 's\n' > "$proj/sol.txt"; printf 'mudou\n' >> "$proj/a.txt"
expect 0 ultima-linha

# gate de aprendizado: com o arquivo de calibração no projeto, commit de código na sessão sem registro bloqueia
novo '# sem verificação'
mkdir -p "$proj/docs" && printf '# Calibração\n' > "$proj/docs/review-calibration.md" && gitc add -A && gitc commit -qm calib
gitc rev-parse HEAD > "$proj/.claude/.session/s1.base"
printf 'codigo\n' >> "$proj/a.txt" && gitc commit -qam codigo
expect 2 aprendizado-bloqueia 'Aprendizado não registrado'
printf -- '- registro\n' >> "$proj/docs/review-calibration.md" && gitc commit -qam registro
expect 0 aprendizado-registrado
# sem o arquivo de calibração (projeto que não adotou o workflow), o gate de aprendizado não bloqueia
novo '# sem verificação'
printf 'codigo\n' >> "$proj/a.txt" && gitc commit -qam codigo
expect 0 sem-calibracao

if [ "$fails" -eq 0 ]; then echo "test-verify-on-stop: todos os casos passaram"; exit 0; fi
echo "test-verify-on-stop: $fails falha(s)"
exit 1
