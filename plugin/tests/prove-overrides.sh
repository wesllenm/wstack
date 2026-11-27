#!/usr/bin/env bash
# Prova, com o Claude Code real, o que a chave override do risk.conf supõe sobre skills e agentes de mesmo nome:
# - pré-carregamento: o skills: sem prefixo de um agente do plugin (o wstack:implementer pré-carrega tdd) recebe a skill
#   tdd do projeto, não a wstack:tdd;
# - lista da lead: numa sessão como wstack:lead, o review-agent do projeto (mesmo nome de um agente do plugin, que a
#   lista Agent(...) traz sem prefixo) é chamado;
# - controle: um agente do projeto com outro nome (revisor-proprio) não é chamado, porque está fora da lista.
# Cada item do projeto devolve um marcador que só existe no arquivo dele. Roda num repositório de teste, com o plugin
# carregado da pasta (--plugin-dir) e só as regras do projeto. Custa três sessões curtas: não faz parte da suíte;
# rodar à mão quando o Claude Code mudar de versão.
# Uso: prove-overrides.sh [<modelo>]     (padrão: haiku)
# Código: 0 como esperado, 1 divergiu ou inconclusivo, 2 uso errado ou claude indisponível.
set -uo pipefail

model=${1:-haiku}
plugin=$(cd "$(dirname "$0")/.." && pwd -P)
command -v claude > /dev/null || { echo "claude ausente" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-ovrprove-XXXX")
work=$(cd "$work" && pwd -P)
# KEEP=1 mantém a pasta de trabalho (saída do claude) para investigar uma divergência
trap 'if [ -n "${KEEP:-}" ]; then echo "pasta mantida: $work"; else rm -rf "$work"; fi' EXIT
fails=0
echo "Claude Code: $(claude --version 2> /dev/null)"

p=$work/proj
git init -q "$p" && git -C "$p" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
mkdir -p "$p/.claude/skills/tdd" "$p/.claude/agents"
printf -- '---\nname: tdd\ndescription: TDD do projeto de teste.\n---\n\nMARCADOR-TDD-DO-PROJETO-7731\n' > "$p/.claude/skills/tdd/SKILL.md"
for a in review-agent:4410 revisor-proprio:5520; do
  printf -- '---\nname: %s\ndescription: Agente do projeto de teste.\ntools: Read\n---\n\nResponda só: MARCADOR-AGENTE-%s\n' "${a%%:*}" "${a#*:}" > "$p/.claude/agents/${a%%:*}.md"
done
printf 'base = HEAD\noverride = tdd\noverride = review-agent\n' > "$p/.claude/risk.conf"

run() { # run <rótulo> <settings em JSON> <prompt>
  printf '%s' "$2" > "$p/.claude/settings.json"
  (cd "$p" && timeout 600 claude -p --model "$model" --plugin-dir "$plugin" --setting-sources project --permission-mode bypassPermissions \
    --output-format json --max-turns 6 "$3" 2> "$work/$1.err") > "$work/$1.json"
  [ -s "$work/$1.json" ] || { echo "ERRO: claude -p não respondeu (autenticação?): $(tail -3 "$work/$1.err")"; exit 2; }
  jq -r '.result // ""' "$work/$1.json"
}
plain='{"permissions":{"allow":["Read"]}}'
lead='{"agent":"wstack:lead","permissions":{"allow":["Read"]}}'

out=$(run preload "$plain" "Use the Agent tool once with subagent_type wstack:implementer and this exact instruction: 'Do not edit or read anything. Look at the content of the skill named tdd that was preloaded into your context at startup. Reply with the first non-empty line after its frontmatter, verbatim.' Then reply with exactly what it said.")
if grep -q 'MARCADOR-TDD-DO-PROJETO-7731' <<< "$out"; then echo "ok [pré-carregamento]: o wstack:implementer recebeu a tdd do projeto"
else echo "DIVERGIU [pré-carregamento]: o marcador da tdd do projeto não voltou: $(head -c 200 <<< "$out")"; fails=$((fails + 1)); fi

out=$(run mesmo-nome "$lead" "Harness test, not a task: skip the lead workflow. Use the Agent tool exactly once with subagent_type review-agent (without the wstack: prefix) and the instruction 'responda'. Report verbatim what came back, or the exact error.")
if grep -q 'MARCADOR-AGENTE-4410' <<< "$out"; then echo "ok [mesmo nome]: a lead chamou o review-agent do projeto"
else echo "DIVERGIU [mesmo nome]: o review-agent do projeto não respondeu: $(head -c 200 <<< "$out")"; fails=$((fails + 1)); fi

out=$(run outro-nome "$lead" "Harness test, not a task: skip the lead workflow. Use the Agent tool exactly once with subagent_type revisor-proprio and the instruction 'responda'. Report verbatim what came back, or the exact error.")
if grep -q 'MARCADOR-AGENTE-5520' <<< "$out"; then echo "DIVERGIU [outro nome]: a lead chamou um agente fora da lista Agent(...)"; fails=$((fails + 1))
elif grep -qi 'not found\|não encontrado\|não existe\|available agents' <<< "$out"; then echo "ok [outro nome]: o agente fora da lista não foi chamado"
else echo "INCONCLUSIVO [outro nome]: sem marcador e sem recusa: $(head -c 200 <<< "$out")"; fails=$((fails + 1)); fi

if [ "$fails" -eq 0 ]; then echo "prove-overrides: como esperado"; exit 0; fi
echo "prove-overrides: $fails divergência(s)"
exit 1
