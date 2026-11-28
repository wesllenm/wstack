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
stop() { # com TRANSCRIPT, a entrada traz transcript_path, como o Claude Code manda ao Stop; RAW_INPUT a substitui
  { if [ -n "${RAW_INPUT:-}" ]; then printf '%s' "$RAW_INPUT"
    else jq -cn --arg t "${TRANSCRIPT:-}" '{session_id:"s1"} + (if $t == "" then {} else {transcript_path:$t} end)'; fi; } |
    CLAUDE_PROJECT_DIR=$proj bash "$hook" > "$work/out" 2> "$work/err"; echo $?
}
fail_msg() { echo "FALHOU [$1]"; fails=$((fails + 1)); }
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
# exceção de build: vale só com a linha da sessão atual; esquecida de outra sessão não pula build e testes
grep -qF "sessão: s1" "$work/err" || fail_msg 'build-falha: mensagem não mostra a linha sessão: a escrever'
printf 'build quebrado antes da tarefa\nsessão: sessao-da-semana-passada\n' > "$proj/.claude/verify-blocked.md"
expect 2 build-excecao-velha-ignorada 'é de outra sessão'
printf 'build quebrado antes da tarefa\nsessão: s1\n' > "$proj/.claude/verify-blocked.md"
expect 0 build-excecao-da-sessao
grep -q 'Motivo registrado: build quebrado antes da tarefa' "$work/out" || fail_msg 'build-excecao-da-sessao: motivo fora do systemMessage'
# uso único: a exceção é consumida; o próximo encerramento (e o código editado depois) volta ao gate
[ ! -e "$proj/.claude/verify-blocked.md" ] || fail_msg 'build-excecao-da-sessao: exceção não foi consumida'
mark=$proj/.claude/.session/unverified-s1
[ -s "$mark" ] || fail_msg 'build-excecao-da-sessao: sem o marcador de verificação pendente (segura o push)'
grep -q '^head: ' "$mark" || fail_msg 'build-excecao-da-sessao: marcador sem o HEAD que ele cobre'
printf 'editado depois da exceção\n' >> "$proj/a.txt"
expect 2 build-depois-da-excecao 'Verificação falhou'
grep -q 'aprovação dele' "$work/err" || fail_msg 'build-depois-da-excecao: mensagem não diz que a exceção é do desenvolvedor'
[ -e "$mark" ] || fail_msg 'build-depois-da-excecao: encerramento que falhou apagou o marcador'
# o fluxo do lead: commitar e encerrar. Árvore limpa não conta como verde: com o marcador, o build roda no commitado
gitc add a.txt && gitc commit -qm 'código ainda vermelho'
expect 2 arvore-limpa-com-marcador-roda-build 'Verificação falhou'
[ -e "$mark" ] || fail_msg 'arvore-limpa-com-marcador-roda-build: árvore limpa apagou o marcador sem verificação'
# conserto sem commit: o verde é da árvore de trabalho, e o push levaria o HEAD vermelho; o marcador fica, com aviso
sed -i 's/^verify_build = .*/verify_build = true/' "$proj/.claude/risk.conf"
expect 0 verde-com-arvore-suja
[ -e "$mark" ] || fail_msg 'verde-com-arvore-suja: verde sobre conserto sem commit apagou o marcador'
grep -q 'mudança sem commit' "$work/out" || fail_msg 'verde-com-arvore-suja: systemMessage não pede o commit'
# commitado o conserto, o encerramento verde sobre a árvore limpa apaga o marcador (e libera o push)
gitc add -A && gitc commit -qm 'conserto'
expect 0 verde-depois-da-excecao
[ ! -e "$mark" ] || fail_msg 'verde-depois-da-excecao: marcador de verificação pendente não foi apagado'
# sem comandos de verificação não há verde: o marcador fica (o desenvolvedor libera), com aviso
printf 'x (sessão s1)\nhead: %s\n' "$(git -C "$proj" rev-parse HEAD)" > "$mark"
sed -i 's/^verify_build = .*/verify_build = /' "$proj/.claude/risk.conf"
expect 0 sem-comandos-marcador-fica
[ -e "$mark" ] || fail_msg 'sem-comandos-marcador-fica: marcador apagado sem verificação'
grep -q 'Verificação pendente desta sessão' "$work/out" || fail_msg 'sem-comandos-marcador-fica: saída silenciosa com o marcador'
grep -qF 'rm -f .claude/.session/unverified-s1' "$work/out" || fail_msg 'sem-comandos-marcador-fica: aviso sem o comando de destravar'
jq -e .systemMessage "$work/out" > /dev/null 2>&1 || fail_msg 'sem-comandos-marcador-fica: systemMessage não é JSON válido'
sed -i 's/^verify_build = .*/verify_build = true/' "$proj/.claude/risk.conf"
mv "$proj/sol.txt" "$work/sol.bak"
expect 0 sem-solucao-marcador-fica
grep -q 'verify_solution do risk.conf não existe' "$work/out" || fail_msg 'sem-solucao-marcador-fica: saída silenciosa com o marcador'
mv "$work/sol.bak" "$proj/sol.txt"
# marcador de outra sessão não é apagado pelo verde desta
printf 'y (sessão s2)\nhead: %s\n' "$(git -C "$proj" rev-parse HEAD)" > "$proj/.claude/.session/unverified-s2"
expect 0 verde-desta-sessao
[ -e "$proj/.claude/.session/unverified-s2" ] || fail_msg 'verde-desta-sessao: apagou o marcador da sessão s2'
[ ! -e "$mark" ] || fail_msg 'verde-desta-sessao: não apagou o marcador desta sessão'
rm -f "$proj/.claude/.session/unverified-s2"
# commit da exceção reescrito (amend): o HEAD gravado sai do histórico; o verde não apaga e diz como destravar
gitc commit -q --allow-empty -m 'commit da exceção'
printf 'z (sessão s1)\nhead: %s\n' "$(git -C "$proj" rev-parse HEAD)" > "$mark"
gitc commit -q --amend --allow-empty -m 'commit da exceção, reescrito'
expect 0 head-reescrito-marcador-preso
[ -e "$mark" ] || fail_msg 'head-reescrito-marcador-preso: apagou o marcador de um HEAD fora do histórico'
grep -qF "rm -f .claude/.session/unverified-s1" "$work/out" || fail_msg 'head-reescrito-marcador-preso: systemMessage sem o comando de destravar'
jq -e .systemMessage "$work/out" > /dev/null 2>&1 || fail_msg 'head-reescrito-marcador-preso: systemMessage não é JSON válido'
# sem a linha head: (repositório sem commit na hora da exceção), vale o verde sobre a árvore limpa
printf 'w (sessão s1)\n' > "$mark"
printf 'mudou sem commit\n' >> "$proj/a.txt"
expect 0 sem-head-arvore-suja
[ -e "$mark" ] || fail_msg 'sem-head-arvore-suja: apagou sem árvore limpa'
gitc commit -qam 'sem head'
expect 0 sem-head-verde
[ ! -e "$mark" ] || fail_msg 'sem-head-verde: verde sobre a árvore limpa não apagou'
rm -f "$proj/.claude/verify-blocked.md"
# SessionStart avisa quando a exceção existe
printf 'algo\nsessão: s1\n' > "$proj/.claude/verify-blocked.md"
out=$(printf '{"session_id":"s9"}' | CLAUDE_PROJECT_DIR=$proj bash -c "cd '$proj' && bash '$(dirname "$hook")/session-start.sh'" 2>&1)
printf '%s' "$out" | grep -q 'AVISO: .claude/verify-blocked.md existe' || fail_msg "session-start: sem aviso da exceção ($out)"
rm -f "$proj/.claude/verify-blocked.md"
# sem sha1sum e sem xargs GNU (macOS padrão): a impressão digital não pode ficar vazia e casar com um carimbo vazio,
# pulando build e testes na mudança seguinte. sha1sum e xargs falsos que falham, na frente do PATH.
mkdir -p "$work/sem-gnu"
printf '#!/bin/sh\nexit 127\n' > "$work/sem-gnu/sha1sum"; printf '#!/bin/sh\nexit 1\n' > "$work/sem-gnu/xargs"
chmod +x "$work/sem-gnu/sha1sum" "$work/sem-gnu/xargs"
novo 'verify_solution = sol.txt' 'verify_build = true' 'verify_test = true'
printf 's\n' > "$proj/sol.txt"; printf 'mudou\n' >> "$proj/a.txt"; printf 'novo\n' > "$proj/nao-rastreado.txt"
PATH="$work/sem-gnu:$PATH" expect 0 sem-sha1sum-passa
[ -s "$proj/.claude/.verify-ok" ] || fail_msg 'sem-sha1sum-passa: carimbo vazio ou ausente'
sed -i 's/^verify_build = .*/verify_build = false/' "$proj/.claude/risk.conf"
printf 'mudou de novo\n' >> "$proj/a.txt"
PATH="$work/sem-gnu:$PATH" expect 2 sem-sha1sum-mudanca-roda-build 'Verificação falhou'
printf 'conteudo diferente\n' > "$proj/nao-rastreado.txt"
sed -i '$d' "$proj/a.txt"
PATH="$work/sem-gnu:$PATH" expect 2 nao-rastreado-mudou-roda-build 'Verificação falhou'
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
grep -q 'mesma linha de princípios:' "$work/err" || fail_msg 'pedidos-ausente: mensagem não diz onde o campo é procurado'
sed -i '$d' "$proj/docs/review-calibration.md"
printf -- '- t — pedidos: 1 (path-guard 1) — princípios: tdd (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 0 campos-conferem
sed -i '$d' "$proj/docs/review-calibration.md"
# a linha completa no formato da skill lead, com a triagem das lições (aceitas, rejeitadas, backlog) no aprendizado:
printf -- '- 2026-11-26 — t — SIMPLES — achados: 1 confirmados, 0 refutados, 0 recusados, 0 escaparam — aprendizado: aceitas 1 (gotcha), rejeitadas 1, backlog 1 (proposta (escada 2)) — pedidos: 1 (path-guard 1) — princípios: tdd (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 0 registro-com-triagem
sed -i '$d' "$proj/docs/review-calibration.md"
printf -- '- t — pedidos: 1 — princípios: nenhum (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
TRANSCRIPT=$tr expect 0 principios-nenhum
# transcrição indisponível: aviso, não bloqueio (só a presença do campo vale)
TRANSCRIPT=$work/nao-existe.jsonl expect 0 transcricao-ausente-aviso 'Aviso: transcrição da sessão indisponível'
expect 0 sem-transcript-path-aviso 'Aviso: transcrição da sessão indisponível'
# não conseguir ler o caminho bloqueia: entrada que não é JSON, e node ausente (um node falso que sai 127 na frente do
# PATH, porque o node real fica em pastas diferentes aqui e no CI)
RAW_INPUT='{"session_id":"s1", quebrado' expect 2 entrada-nao-json 'não consegui ler transcript_path'
mkdir -p "$work/sem-node" && printf '#!/bin/sh\nexit 127\n' > "$work/sem-node/node" && chmod +x "$work/sem-node/node"
PATH="$work/sem-node:$PATH" TRANSCRIPT=$tr expect 2 node-ausente 'node saiu com código 127'
# node que imprime aviso no stderr e sai 0: o aviso não pode virar caminho (cairia no aviso e pularia a conferência)
real_node=$(command -v node)
mkdir -p "$work/node-falante"
printf '#!/bin/sh\necho "(node) aviso de depreciação" >&2\nexec "%s" "$@"\n' "$real_node" > "$work/node-falante/node"
chmod +x "$work/node-falante/node"
printf -- '- t — pedidos: 1 — princípios: ok (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
PATH="$work/node-falante:$PATH" TRANSCRIPT=$tr expect 2 node-com-aviso-confere 'NÃO CARREGADA: ok'
sed -i '$d' "$proj/docs/review-calibration.md"
# sem session_id, com o gate adotado: bloqueia em vez de pular o gate de aprendizado
RAW_INPUT='{"hook_event_name":"Stop"}' expect 2 sem-session-id 'não traz session_id'
# problema de ambiente registrado em verify-blocked.md libera, com o motivo visível; sem isso o agente ficaria em loop
blk=$proj/.claude/verify-blocked.md
# a exceção só vale com a âncora da sessão: sem session_id, "head: <SHA do HEAD>"; a mensagem de bloqueio a mostra
grep -qF "head: $(git -C "$proj" rev-parse HEAD)" "$work/err" || fail_msg 'sem-session-id: mensagem não mostra a linha head: a escrever'
printf 'entrada do Stop sem session_id neste ambiente\n' > "$blk"
RAW_INPUT='{"hook_event_name":"Stop"}' expect 2 excecao-sem-ancora-ignorada 'é de outra sessão'
printf 'head: %s\n' "$(git -C "$proj" rev-parse HEAD)" >> "$blk"
RAW_INPUT='{"hook_event_name":"Stop"}' expect 0 sem-session-id-com-excecao
grep -q 'Motivo registrado: entrada do Stop sem session_id' "$work/out" || fail_msg 'sem-session-id-com-excecao: motivo fora do systemMessage'
grep -q 'head:' "$work/out" && fail_msg 'sem-session-id-com-excecao: a linha de âncora apareceu no motivo'
[ -s "$proj/.claude/.session/unverified-sem-sessao" ] || fail_msg 'sem-session-id-com-excecao: sem o marcador unverified-sem-sessao'
# session_id fora do alfabeto fechado conta como ausente (vira caminho de arquivo)
rm -f "$blk"
RAW_INPUT='{"session_id":"../../x"}' expect 2 session-id-invalido 'fora do formato esperado'
rm -f "$blk"
# a exceção não libera divergência de conteúdo: isso o agente corrige na linha
printf -- '- t — pedidos: 1 — princípios: ok (carregadas: 1)\n' >> "$proj/docs/review-calibration.md"
printf 'qualquer coisa\nsessão: s1\n' > "$blk"
TRANSCRIPT=$tr expect 2 excecao-nao-libera-conteudo 'NÃO CARREGADA: ok'
rm -f "$blk"; sed -i '$d' "$proj/docs/review-calibration.md"
# motivo com acento cortado em 300 bytes: o systemMessage continua JSON válido
{ printf '%0299d' 0 | tr 0 a; printf 'éééé\n'; printf 'head: %s\n' "$(git -C "$proj" rev-parse HEAD)"; } > "$blk"
RAW_INPUT='{"hook_event_name":"Stop"}' expect 0 excecao-utf8
# o jq e o Node não recusam o byte partido: trocam por U+FFFD. O que se confere é que ele não sobra.
node -e 'process.exit(require("fs").readFileSync(process.argv[1],"utf8").includes("\uFFFD")?1:0)' "$work/out" \
  || fail_msg 'excecao-utf8: caractere partido no systemMessage (vira U+FFFD)'
jq -e .systemMessage "$work/out" > /dev/null 2>&1 || fail_msg 'excecao-utf8: systemMessage não é JSON válido'
printf 'quebra "com aspas" e\ttab\nhead: %s\n' "$(git -C "$proj" rev-parse HEAD)" > "$blk"
RAW_INPUT='{"hook_event_name":"Stop"}' expect 0 excecao-aspas
jq -e .systemMessage "$work/out" > /dev/null 2>&1 || fail_msg 'excecao-aspas: systemMessage não é JSON válido'
rm -f "$blk"
# sem o HEAD do início da sessão: aviso, não silêncio
mv "$proj/.claude/.session/s1.base" "$work/base.bak"
expect 0 sem-base-aviso 'Aviso: sem .claude/.session/s1.base'
mv "$work/base.bak" "$proj/.claude/.session/s1.base"
# script que não roda: bloqueia com "não consegui verificar" (cópia do plugin com o script trocado)
broken=$work/plugin-quebrado
cp -r "$(dirname "$hook")/.." "$broken"
printf 'process.exit(1)\n' > "$broken/scripts/principles.mjs"
hook_ok=$hook; hook=$broken/hooks/verify-on-stop.sh
TRANSCRIPT=$tr expect 2 principles-quebrado 'Não consegui verificar o campo princípios:'
grep -qF "sessão: s1" "$work/err" || fail_msg 'principles-quebrado: mensagem não mostra a linha sessão: a escrever'
printf 'node quebrado no ambiente da nuvem\nsessão: outra-sessao\n' > "$blk"
TRANSCRIPT=$tr expect 2 excecao-de-outra-sessao-ignorada 'é de outra sessão'
printf 'node quebrado no ambiente da nuvem\nsessão: s1\n' > "$blk"
TRANSCRIPT=$tr expect 0 principles-quebrado-com-excecao
grep -q 'sem conferir o campo princípios:' "$work/out" || fail_msg 'principles-quebrado-com-excecao: aviso não diz o que ficou sem conferir'
rm -f "$blk"
# código 3 sem as linhas NÃO CARREGADA/CAMPO AUSENTE: o motivo ainda aparece (fim da saída)
printf 'console.log("saida inesperada do script");process.exit(3)\n' > "$broken/scripts/principles.mjs"
TRANSCRIPT=$tr expect 2 principles-3-sem-linhas 'saida inesperada do script'
cp "$(dirname "$hook_ok")/../scripts/principles.mjs" "$broken/scripts/principles.mjs"
printf 'process.exit(0)\n' > "$broken/scripts/permission-asks.mjs"
TRANSCRIPT=$tr expect 2 permission-asks-saida-vazia 'Não consegui verificar o campo pedidos:'
printf 'process.exit(2)\n' > "$broken/scripts/permission-asks.mjs"
TRANSCRIPT=$tr expect 2 permission-asks-codigo-2 'saiu com código 2'
hook=$hook_ok
# as exceções acima deixaram marcadores; daqui em diante os casos esperam árvore sem pendência
rm -f "$proj/.claude/.session/unverified-"*
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

# destino trocado (doc_calibration do risk.conf): o gate de aprendizado lê e cita o arquivo configurado
novo '# sem verificação' 'doc_calibration = docs/calibracao.md'
mkdir -p "$proj/docs" && printf '# Calibração\n' > "$proj/docs/calibracao.md" && gitc add -A && gitc commit -qm calib
gitc rev-parse HEAD > "$proj/.claude/.session/s1.base"
printf 'codigo\n' >> "$proj/a.txt" && gitc commit -qam codigo
expect 2 doc-calibration-bloqueia 'último registro em docs/calibracao.md'
printf -- '- registro — princípios: nenhum (carregadas: 0)\n' >> "$proj/docs/calibracao.md" && gitc commit -qam registro
expect 0 doc-calibration-registrado
# doc_state: mudança só na pendência versionada não é código, e o build (que falharia) não roda; sem a chave, roda
for c in 'doc_state = docs/onde-paramos.md' '# sem doc_state'; do
  novo 'verify_solution = sol.txt' 'verify_build = false' 'verify_test = true' "$c"
  printf 's\n' > "$proj/sol.txt" && gitc add -A && gitc commit -qm sol
  mkdir -p "$proj/docs" && printf 'onde paramos\n' > "$proj/docs/onde-paramos.md"
  if [ "$c" = '# sem doc_state' ]; then expect 2 sem-doc-state-conta-como-codigo; else expect 0 doc-state-nao-e-codigo; fi
done

# gate de aprendizado: commit só de documentação (o plano da tarefa) não cobra o Registro; o primeiro commit de código cobra
novo '# sem verificação'
mkdir -p "$proj/docs" && printf '# Calibração\n' > "$proj/docs/review-calibration.md" && gitc add -A && gitc commit -qm calib
gitc rev-parse HEAD > "$proj/.claude/.session/s1.base"
mkdir -p "$proj/docs/planos" && printf '# plano\n' > "$proj/docs/planos/ci.md" && printf 'x\n' > "$proj/NOTAS.md" && gitc add -A && gitc commit -qm plano
expect 0 plano-commitado-nao-cobra
printf 'codigo\n' >> "$proj/a.txt" && gitc commit -qam codigo
expect 2 codigo-cobra 'Aprendizado não registrado'
# com subagente em segundo plano rodando (background_tasks da entrada, como o Claude Code manda ao Stop), o fim de turno é
# espera e não cobra o Registro; subagente que terminou, tarefa de outro tipo e campo ilegível cobram
bg() { jq -cn --arg t "$1" --arg s "$2" '{session_id:"s1",background_tasks:[{id:"a1",type:$t,status:$s,agent_type:"wstack:review-critical"}]}'; }
RAW_INPUT=$(bg subagent running) expect 0 subagente-rodando-nao-cobra
RAW_INPUT=$(bg subagent completed) expect 2 subagente-terminado-cobra 'Aprendizado não registrado'
RAW_INPUT=$(bg shell running) expect 2 shell-rodando-cobra 'Aprendizado não registrado'
RAW_INPUT='{"session_id":"s1","background_tasks":"running"}' expect 2 background-ilegivel-cobra 'Aprendizado não registrado'

# pedidos: conta até a gravação da linha de Registro (a última edição do arquivo de calibração na transcrição); o pedido do
# push que publica a linha, depois dela, não reabre o gate
cal="$proj/docs/review-calibration.md"
ask() { jq -cn --arg o "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"$2\"}}" --arg t "$1" --arg id "$3" \
  '{type:"attachment",uuid:$id,timestamp:$t,attachment:{type:"hook_success",hookName:"PreToolUse:Bash",hookEvent:"PreToolUse",toolUseID:$id,stdout:$o,exitCode:0}}'; }
use() { jq -cn --arg t "$1" --arg id "$2" --arg n "$3" --arg f "$4" '{type:"assistant",timestamp:$t,message:{role:"assistant",content:[{type:"tool_use",id:$id,name:$n,input:{command:"x",file_path:$f}}]}}'; }
tr2=$work/sessao-corte.jsonl
{
  use 2026-11-28T10:00:00Z b1 Bash ''; ask 2026-11-28T10:00:01Z 'path-guard: trava' b1
  use 2026-11-28T10:05:00Z e1 Edit "$cal"
  use 2026-11-28T10:06:00Z b2 Bash ''; ask 2026-11-28T10:06:01Z 'push-guard: caminho protegido' b2
} > "$tr2"
printf -- '- t — pedidos: 1 (path-guard 1) — princípios: nenhum (carregadas: 0)\n' >> "$cal"
TRANSCRIPT=$tr2 expect 0 pedidos-ate-a-linha
# sem a edição na transcrição (linha gravada por outro caminho), conta tudo
grep -v '"e1"' "$tr2" > "$tr2.sem" && TRANSCRIPT=$tr2.sem expect 2 pedidos-sem-edicao-conta-tudo 'a transcrição tem 2 pedido'

if [ "$fails" -eq 0 ]; then echo "test-verify-on-stop: todos os casos passaram"; exit 0; fi
echo "test-verify-on-stop: $fails falha(s)"
exit 1
