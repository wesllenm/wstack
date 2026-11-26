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
stop() { # com TRANSCRIPT, a entrada traz transcript_path, como o Claude Code manda ao Stop
  jq -cn --arg t "${TRANSCRIPT:-}" '{session_id:"s1"} + (if $t == "" then {} else {transcript_path:$t} end)' |
    CLAUDE_PROJECT_DIR=$proj bash "$hook" > "$work/out" 2> "$work/err"; echo $?
}
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
expect 2 aprendizado-sem-principios 'Registro sem o campo princípios'
printf -- '- registro — princípios: nenhum (carregadas: 0)\n' >> "$proj/docs/review-calibration.md"
expect 0 aprendizado-principios-pendente
gitc commit -qam registro-principios
expect 0 aprendizado-registrado
# conteúdo dos campos contra a transcrição: princípios só de skill carregada; pedidos não abaixo dos da transcrição
tr=$work/sessao.jsonl
{
  jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"s",name:"Skill",input:{skill:"wstack:tdd"}}]}}'
  jq -cn '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"s",content:"ok"}]}}'
  jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"b",name:"Bash",input:{command:"ls .claude/hooks"}}]}}'
  jq -cn --arg o '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"path-guard: trava"}}' \
    '{type:"attachment",uuid:"u1",attachment:{type:"hook_success",hookName:"PreToolUse:Bash",hookEvent:"PreToolUse",toolUseID:"b",stdout:$o,exitCode:0}}'
} > "$tr"
gitc rev-parse HEAD > "$proj/.claude/.session/s1.base"
printf 'codigo2\n' >> "$proj/a.txt" && gitc commit -qam codigo2
printf -- '- t — princípios: ok (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 2 principios-conteudo-falso 'NÃO CARREGADA: ok'
expect 0 principios-sem-transcricao-so-campo
sed -i '$d' "$proj/docs/review-calibration.md"
printf -- '- t — pedidos: 1 — princípios: security (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 2 principios-skill-nao-carregada 'NÃO CARREGADA: security'
sed -i '$d' "$proj/docs/review-calibration.md"
printf -- '- t — pedidos: 0 — princípios: tdd (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 2 pedidos-abaixo 'a transcrição tem 1 pedido'
sed -i '$d' "$proj/docs/review-calibration.md"
printf -- '- t — princípios: tdd (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 2 pedidos-ausente "registrado 'ausente'"
sed -i '$d' "$proj/docs/review-calibration.md"
printf -- '- t — pedidos: 1 (path-guard 1) — princípios: tdd (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 0 campos-conferem
sed -i '$d' "$proj/docs/review-calibration.md"
printf -- '- t — pedidos: 1 — princípios: nenhum (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 0 principios-nenhum
# transcrição indisponível: aviso, não bloqueio (só a presença do campo vale)
TRANSCRIPT=$work/nao-existe.jsonl expect 0 transcricao-ausente-aviso 'Aviso: transcrição da sessão indisponível'
# script que não roda: bloqueia com "não consegui verificar" (cópia do plugin com o script trocado)
broken=$work/plugin-quebrado
cp -r "$(dirname "$hook")/.." "$broken"
printf 'process.exit(1)\n' > "$broken/scripts/principles.mjs"
hook_ok=$hook; hook=$broken/hooks/verify-on-stop.sh
TRANSCRIPT=$tr expect 2 principles-quebrado 'Não consegui verificar o campo princípios:'
cp "$(dirname "$hook_ok")/../scripts/principles.mjs" "$broken/scripts/principles.mjs"
printf 'process.exit(0)\n' > "$broken/scripts/permission-asks.mjs"
TRANSCRIPT=$tr expect 2 permission-asks-saida-vazia 'Não consegui verificar o campo pedidos:'
printf 'process.exit(2)\n' > "$broken/scripts/permission-asks.mjs"
TRANSCRIPT=$tr expect 2 permission-asks-codigo-2 'saiu com código 2'
hook=$hook_ok
gitc commit -qam registro3
# os arquivos que a escada de aprendizado grava (gotchas por área, complemento da rubrica) não contam como código:
# commitados depois do registro não pedem outro, e pendentes não rodam o build
mkdir -p "$proj/docs/gotchas" && printf -- '- fato\n' > "$proj/docs/gotchas/area.md" && printf '## Projeto\n' > "$proj/docs/review-rubric.md"
gitc add -A && gitc commit -qm gotcha
expect 0 aprendizado-arquivos-de-area
printf 'verify_solution = a.txt\nverify_build = false\nverify_test = false\n' >> "$proj/.claude/risk.conf" && gitc commit -qam conf
printf 'registro\n' >> "$proj/docs/review-calibration.md" && gitc commit -qam registro2
printf -- '- outro\n' >> "$proj/docs/gotchas/area.md" && printf -- '- item\n' >> "$proj/docs/review-rubric.md"
expect 0 aprendizado-pendente-sem-build
# sem o arquivo de calibração (projeto que não adotou o workflow), o gate de aprendizado não bloqueia
novo '# sem verificação'
printf 'codigo\n' >> "$proj/a.txt" && gitc commit -qam codigo
expect 0 sem-calibracao

if [ "$fails" -eq 0 ]; then echo "test-verify-on-stop: todos os casos passaram"; exit 0; fi
echo "test-verify-on-stop: $fails falha(s)"
exit 1
