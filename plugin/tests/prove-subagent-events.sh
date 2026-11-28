#!/usr/bin/env bash
# Prova, com o Claude Code real, os eventos de subagente em que o contador do Stop se apoia (subagent-count.sh):
# - SubagentStart e SubagentStop chegam aos hooks, cada um com agent_id, e o mesmo agent_id nos dois;
# - com um subagente em segundo plano, um Stop chega entre o SubagentStart e o SubagentStop (o fim de turno enquanto o
#   subagente roda, que o gate de aprendizado não deve cobrar);
# - depois do SubagentStop chega outro Stop (a entrega, que o gate cobra).
# Roda num repositório de teste, com só as regras do projeto (--setting-sources project) e um hook de log que grava a
# entrada de cada evento com a hora. Custa uma sessão com subagente: não faz parte da suíte; rodar à mão quando o Claude
# Code mudar de versão.
# Uso: prove-subagent-events.sh [<modelo>]     (padrão: haiku)
# Código: 0 como esperado, 1 divergiu ou inconclusivo, 2 uso errado ou claude indisponível.
set -uo pipefail

model=${1:-haiku}
command -v claude > /dev/null || { echo "claude ausente" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-subev-XXXX")
work=$(cd "$work" && pwd -P)
# KEEP=1 mantém a pasta de trabalho (log dos hooks, saída do claude) para investigar uma divergência
trap 'if [ -n "${KEEP:-}" ]; then echo "pasta mantida: $work"; else rm -rf "$work"; fi' EXIT
fails=0
echo "Claude Code: $(claude --version 2> /dev/null)"

p=$work/proj
git init -q "$p" && git -C "$p" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
mkdir -p "$p/.claude/hooks"
# cada linha do log: {"t": <ms>, ...entrada do hook}
printf '#!/usr/bin/env bash\njq -c --argjson t "$(date +%%s%%3N)" %s >> %q\n' "'. + {t: \$t}'" "$work/log.jsonl" > "$p/.claude/hooks/log.sh"
hook='[{hooks:[{type:"command",command:"bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/log.sh",timeout:10}]}]'
jq -n "{permissions:{allow:[\"Bash(sleep:*)\"]}, hooks:{SubagentStart:$hook, SubagentStop:$hook, Stop:$hook}}" > "$p/.claude/settings.json"

(cd "$p" && timeout 900 claude -p --model "$model" --setting-sources project --permission-mode bypassPermissions \
  --output-format json --max-turns 12 \
  "Harness test. Use the Agent tool exactly once, with subagent_type general-purpose and run_in_background true, and give it exactly this instruction: 'Use the Bash tool once to run: sleep 30. Then reply SLEPT.' Right after launching it, reply LAUNCHED and end your turn without waiting. When the agent's completion notification arrives, reply DONE." \
  2> "$work/stderr") > "$work/out.json"
[ -s "$work/log.jsonl" ] || { echo "ERRO: nenhum evento no log (claude -p não rodou? autenticação?): $(tail -3 "$work/stderr")"; exit 2; }

ev() { jq -c --arg e "$1" 'select(.hook_event_name == $e)' "$work/log.jsonl"; }
start=$(ev SubagentStart | head -1); stop=$(ev SubagentStop | head -1)
if [ -z "$start" ]; then echo "DIVERGIU [SubagentStart]: o evento não chegou ao hook"; fails=$((fails + 1)); fi
if [ -z "$stop" ]; then echo "DIVERGIU [SubagentStop]: o evento não chegou ao hook"; fails=$((fails + 1)); fi
if [ -n "$start" ] && [ -n "$stop" ]; then
  echo "campos do SubagentStart: $(jq -c 'keys' <<< "$start")"
  echo "campos do SubagentStop: $(jq -c 'keys' <<< "$stop")"
  a=$(jq -r '.agent_id // ""' <<< "$start"); b=$(jq -r '.agent_id // ""' <<< "$stop")
  if [ -n "$a" ] && [ "$a" = "$b" ]; then echo "ok [agent_id]: o mesmo agent_id no início e no fim ($a)"
  else echo "DIVERGIU [agent_id]: início '$a', fim '$b'"; fails=$((fails + 1)); fi
  ts=$(jq -r .t <<< "$start"); te=$(jq -r .t <<< "$stop")
  during=$(ev Stop | jq -s --argjson a "$ts" --argjson b "$te" '[.[] | select(.t > $a and .t < $b)] | length')
  after=$(ev Stop | jq -s --argjson b "$te" '[.[] | select(.t > $b)] | length')
  if [ "$during" -gt 0 ]; then echo "ok [Stop durante]: $during Stop(s) com o subagente em segundo plano rodando"
  else echo "DIVERGIU [Stop durante]: nenhum Stop entre o SubagentStart e o SubagentStop (o -p esperou o subagente?)"; fails=$((fails + 1)); fi
  if [ "$after" -gt 0 ]; then echo "ok [Stop depois]: $after Stop(s) depois do SubagentStop"
  else echo "DIVERGIU [Stop depois]: nenhum Stop depois do SubagentStop"; fails=$((fails + 1)); fi
fi
echo "ordem: $(jq -r '.hook_event_name' "$work/log.jsonl" | paste -sd' ' -)"

if [ "$fails" -eq 0 ]; then echo "prove-subagent-events: como esperado"; exit 0; fi
echo "prove-subagent-events: $fails divergência(s)"
exit 1
