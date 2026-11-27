#!/usr/bin/env bash
# Prova, com o Claude Code real, como o allow do dotnet-allow convive com as regras do settings.json. O hook devolve
# permissionDecision allow para dotnet na forma fechada quando o risk.conf declara allow_module = dotnet válido; o que o
# Claude Code faz com esse allow diante do deny e do ask do projeto é dele, e os test-*.sh (que só leem a saída do hook)
# não pegam uma mudança nisso.
# Roda num repositório de teste, com o plugin carregado da pasta (--plugin-dir), só as regras do projeto
# (--setting-sources project) e no modo default do -p, em que um pedido de aprovação vira recusa: "rodou" quer dizer
# que nada pediu. O comando é dotnet build App.slnx; sem o dotnet instalado ele falha ao rodar, o que basta.
# - sem allow_module: recusado (o hook fica calado e vale o pedido normal);
# - com allow_module = dotnet válido e sem regra: roda (o allow do hook vale);
# - com o mesmo allow_module e deny de dotnet build no settings.json: recusado (o deny vence);
# - com o mesmo allow_module e ask de dotnet build: recusado (o ask vence; o allow de hook não passa por cima dele).
# Custa quatro sessões curtas: não faz parte da suíte; rodar à mão quando o Claude Code mudar de versão.
# Uso: prove-dotnet-allow.sh [<modelo>]     (padrão: haiku)
# Código: 0 como esperado, 1 divergiu ou inconclusivo, 2 uso errado ou claude indisponível.
set -uo pipefail

model=${1:-haiku}
plugin=$(cd "$(dirname "$0")/.." && pwd -P)
command -v claude > /dev/null || { echo "claude ausente" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-dnallow-XXXX")
work=$(cd "$work" && pwd -P)
# KEEP=1 mantém a pasta de trabalho (saída do claude) para investigar uma divergência
trap 'if [ -n "${KEEP:-}" ]; then echo "pasta mantida: $work"; else rm -rf "$work"; fi' EXIT
fails=0
echo "Claude Code: $(claude --version 2> /dev/null)"

p=$work/proj
git init -q "$p" && git -C "$p" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
mkdir -p "$p/.claude"
cmd='dotnet build App.slnx'
valid='allow_module = dotnet | vence: 2099-12-31 | motivo: prova do dotnet-allow'

case_() { # case_ <rótulo> <rodou|recusado> <linha extra do risk.conf> <permissions em JSON>
  printf 'base = HEAD\n%s\n' "$3" > "$p/.claude/risk.conf"
  jq -n --argjson perm "$4" '{permissions:$perm}' > "$p/.claude/settings.json"
  (cd "$p" && timeout 600 claude -p --model "$model" --plugin-dir "$plugin" --setting-sources project --permission-mode default \
    --output-format json --max-turns 4 "Use the Bash tool exactly once to run this command byte for byte, then reply DONE: $cmd" \
    2> "$work/$1.err") > "$work/$1.json"
  [ -s "$work/$1.json" ] || { echo "ERRO: claude -p não respondeu (autenticação?): $(tail -3 "$work/$1.err")"; exit 2; }
  local denied tried
  denied=$(jq -r --arg c "$cmd" '[.permission_denials[]?.tool_input.command | select(. == $c)] | length' "$work/$1.json")
  tried=$(jq -r '.num_turns // 0' "$work/$1.json")
  local got=rodou; [ "${denied:-0}" != 0 ] && got=recusado
  if [ "$got" = "$2" ]; then echo "ok [$1]: $got"
  elif [ "$got" = rodou ] && [ "$tried" -le 1 ]; then echo "INCONCLUSIVO [$1]: sem recusa, mas o modelo pode não ter tentado o comando"; fails=$((fails + 1))
  else echo "DIVERGIU [$1]: esperado $2, obtido $got"; fails=$((fails + 1)); fi
}

case_ sem-modulo recusado '' '{"allow":["Read"]}'
case_ com-modulo rodou "$valid" '{"allow":["Read"]}'
case_ deny recusado "$valid" '{"allow":["Read"],"deny":["Bash(dotnet build:*)"]}'
case_ ask recusado "$valid" '{"allow":["Read"],"ask":["Bash(dotnet build:*)"]}'

if [ "$fails" -eq 0 ]; then echo "prove-dotnet-allow: como esperado"; exit 0; fi
echo "prove-dotnet-allow: $fails divergência(s)"
exit 1
