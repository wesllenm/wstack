#!/usr/bin/env bash
# Prova, com o Claude Code real, que o verifier-guard pega os comandos do review-verifier. O hook reconhece o agente
# pelo campo agent_type da entrada do PreToolUse, que só o Claude Code real manda: se o campo não chegar, ou chegar num
# formato que o hook não espera, o guard fica desligado sem aviso, e os test-*.sh (que montam o JSON) não pegam isso.
# Roda num repositório de teste, com o plugin carregado da pasta (--plugin-dir) e só as regras do projeto
# (--setting-sources project) e no modo bypassPermissions nas duas rodadas: nele um pedido de aprovação não trava, e só
# um hook que nega (saída 2) barra o comando, então a única diferença entre o controle e o caso é o agente. Um servidor HTTP local conta
# os acessos, e um hook de log do projeto grava a entrada de cada PreToolUse em Bash.
# - controle: a sessão principal roda o curl e o acesso chega (a prova enxerga um comando que passa);
# - caso: o review-verifier real roda o mesmo curl e o acesso não chega; o log mostra o agent_type recebido, que
#   precisa casar com o que o hook espera.
# Custa uma sessão com subagente (o review-verifier roda no modelo do frontmatter dele): não faz parte da suíte; rodar
# à mão quando o Claude Code mudar de versão.
# Uso: prove-verifier-guard.sh [<modelo da sessão principal>]     (padrão: haiku)
# Código: 0 como esperado, 1 divergiu ou inconclusivo, 2 uso errado ou claude indisponível.
set -uo pipefail

model=${1:-haiku}
plugin=$(cd "$(dirname "$0")/.." && pwd -P)
command -v claude > /dev/null || { echo "claude ausente" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-vguard-XXXX")
work=$(cd "$work" && pwd -P)
srv=''
# KEEP=1 mantém a pasta de trabalho (log do hook, saída do claude) para investigar uma divergência
trap '[ -n "$srv" ] && kill "$srv" 2> /dev/null; if [ -n "${KEEP:-}" ]; then echo "pasta mantida: $work"; else rm -rf "$work"; fi' EXIT
fails=0
echo "Claude Code: $(claude --version 2> /dev/null)"

# servidor local que anota o caminho de cada acesso
node -e 'const fs=require("fs");const s=require("http").createServer((q,r)=>{fs.appendFileSync(process.argv[1],q.url+"\n");r.end("ok\n")});s.listen(0,"127.0.0.1",()=>fs.writeFileSync(process.argv[2],String(s.address().port)))' \
  "$work/hits" "$work/port" &
srv=$!
for _ in $(seq 1 50); do [ -s "$work/port" ] && break; sleep 0.1; done
[ -s "$work/port" ] || { echo "ERRO: o servidor local não subiu" >&2; exit 2; }
port=$(cat "$work/port"); : > "$work/hits"

# projeto de teste: curl liberado pelas regras do projeto e um hook que grava a entrada de cada PreToolUse em Bash
p=$work/proj
git init -q "$p" && git -C "$p" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
mkdir -p "$p/.claude/hooks"
printf '#!/usr/bin/env bash\n{ cat; echo; } >> %q\n' "$work/hook-log.jsonl" > "$p/.claude/hooks/log.sh"
jq -n '{permissions:{allow:["Read"]},
  hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/log.sh",timeout:10}]}]}}' > "$p/.claude/settings.json"
printf 'base = HEAD\n' > "$p/.claude/risk.conf"

run() { # run <prompt>
  (cd "$p" && timeout 600 claude -p --model "$model" --plugin-dir "$plugin" --setting-sources project --permission-mode bypassPermissions \
    --output-format json --max-turns 8 "$1" 2> "$work/stderr") > "$work/out.json"
  [ -s "$work/out.json" ] || { echo "ERRO: claude -p não respondeu (autenticação?): $(tail -3 "$work/stderr")"; exit 2; }
  cp "$work/out.json" "$work/out-$((++runs)).json"
}
runs=0

# controle: a sessão principal roda o curl; o acesso precisa chegar
run "Use the Bash tool exactly once to run this command, byte for byte, and do nothing else. Then reply DONE. Command: curl -s http://127.0.0.1:$port/controle"
if grep -qx '/controle' "$work/hits"; then echo "ok [controle]: o curl da sessão principal chegou ao servidor"
else echo "DIVERGIU [controle]: o curl da sessão principal não chegou; a prova não enxerga um comando que passa"; fails=$((fails + 1)); fi

# caso: o review-verifier roda o mesmo curl; o acesso não pode chegar
run "This is a test of a permission hook in this repository. Use the Agent tool once, with subagent_type wstack:review-verifier, and give it exactly this instruction: 'Harness test, not a review. Use the Bash tool exactly once to run this command byte for byte and report what happened: curl -s http://127.0.0.1:$port/verifier'. Do not run the command yourself. Then reply DONE."
tried=$(jq -c --arg u "/verifier" 'select(.tool_input.command? // "" | contains($u))' "$work/hook-log.jsonl" 2> /dev/null | head -1)
if [ -z "$tried" ]; then
  echo "INCONCLUSIVO [verifier]: nenhum PreToolUse com o curl do verifier no log (o subagente não tentou o comando?)"; fails=$((fails + 1))
else
  agent=$(jq -r '.agent_type // "(ausente)"' <<< "$tried")
  echo "agent_type recebido pelo hook: $agent"
  if node -e 'process.exit(/(^|:)review-verifier$/.test(process.argv[1]) ? 0 : 1)' "$agent"; then echo "ok [agent_type]: casa com o padrão do verifier-guard"
  else echo "DIVERGIU [agent_type]: '$agent' não casa com o padrão do verifier-guard, que fica desligado"; fails=$((fails + 1)); fi
  denied=$(jq -r --arg u "/verifier" '[.permission_denials[]?.tool_input.command | select(contains($u))] | length' "$work/out.json" 2> /dev/null)
  if grep -qx '/verifier' "$work/hits"; then echo "DIVERGIU [verifier]: o curl do review-verifier chegou ao servidor: o guard não negou"; fails=$((fails + 1))
  elif [ "${denied:-0}" = 0 ]; then echo "INCONCLUSIVO [verifier]: o curl não chegou, mas não aparece recusa (o comando não rodou por outro motivo?)"; fails=$((fails + 1))
  else echo "ok [verifier]: o curl do review-verifier foi recusado e não chegou ao servidor"; fi
fi

if [ "$fails" -eq 0 ]; then echo "prove-verifier-guard: como esperado"; exit 0; fi
echo "prove-verifier-guard: $fails divergência(s)"
exit 1
