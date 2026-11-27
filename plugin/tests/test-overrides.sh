#!/usr/bin/env bash
# Casos das substituições do projeto (overrides.mjs, chave override do risk.conf) e do SessionStart que as lista. A lista
# Agent(...) da lead com os nomes sem prefixo é conferida em test-skills-agents.sh. Sem rede.
# Uso: test-overrides.sh [<pasta do plugin>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

plugin=$(cd "${1:-$(dirname "$0")/..}" && pwd -P)
[ -f "$plugin/hooks/overrides.mjs" ] || { echo "overrides.mjs não encontrado" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-ovr-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU [$1]: $2"; fails=$((fails + 1)); }

proj() { # proj <nome> <linha do risk.conf>...: repositório com o risk.conf dado
  local p="$work/$1"; shift
  git init -q "$p" && mkdir -p "$p/.claude/skills" "$p/.claude/agents"
  : > "$p/.claude/risk.conf"; local l; for l in "$@"; do printf '%s\n' "$l" >> "$p/.claude/risk.conf"; done
  printf '%s' "$p"
}
skill() { mkdir -p "$1/.claude/skills/$2" && printf -- '---\nname: %s\ndescription: x\n---\n' "$2" > "$1/.claude/skills/$2/SKILL.md"; }
agent() { printf -- '---\nname: %s\ndescription: x\n---\n' "$2" > "$1/.claude/agents/$2.md"; }
list() { (cd "$1" && CLAUDE_PROJECT_DIR=$1 node "$plugin/hooks/overrides.mjs"); }
session() { (cd "$1" && CLAUDE_PROJECT_DIR=$1 node "$plugin/hooks/overrides.mjs" --session); }

# sem override e sem item de mesmo nome: nada a dizer
p=$(proj vazio 'base = HEAD')
[ -z "$(list "$p")$(session "$p")" ] || fail vazio-calado "$(session "$p")"

# substituições válidas: skill de mesmo nome, skill com outro nome, agente de mesmo nome
p=$(proj valido 'override = tdd' 'override = test-audit -> auditoria-de-testes' 'override = review-agent')
skill "$p" tdd; skill "$p" auditoria-de-testes; agent "$p" review-agent
want=$'skill\ttdd\ttdd\nskill\ttest-audit\tauditoria-de-testes\nagente\treview-agent\treview-agent'
[ "$(list "$p")" = "$want" ] || fail validas "$(list "$p" | tr '\t\n' ' |')"
s=$(session "$p")
for t in 'skill tdd do projeto no lugar do wstack:tdd' 'skill auditoria-de-testes do projeto no lugar do wstack:test-audit' \
  'agente review-agent do projeto no lugar do wstack:review-agent'; do
  grep -qF -- "$t" <<< "$s" || fail "session: $t" "$s"
done
grep -q AVISO <<< "$s" && fail validas-sem-aviso "$s"

# inválidas: nome fora do alfabeto, item que o plugin não tem, arquivo do projeto ausente, agente com outro nome
p=$(proj invalido 'override = Tdd' 'override = nao-existe' 'override = clean-code' 'override = simplify -> enxugar' 'override = a b')
agent "$p" enxugar
[ -z "$(list "$p")" ] || fail invalidas-fora-da-lista "$(list "$p" | tr '\t\n' ' |')"
s=$(session "$p")
for t in 'override "Tdd" ignorado' 'override = nao-existe ignorado: o plugin não tem' \
  'override = clean-code: o projeto não tem .claude/skills/clean-code/SKILL.md' 'agente do projeto só substitui o do plugin com o mesmo nome' \
  'override "a b" ignorado'; do
  grep -qF -- "$t" <<< "$s" || fail "aviso: $t" "$s"
done

# mesmo nome no projeto sem override: aviso (os agentes do plugin já pré-carregam a skill do projeto)
p=$(proj sombra 'override = tdd'); skill "$p" tdd; skill "$p" security; agent "$p" planner; skill "$p" minha-skill
s=$(session "$p")
grep -qF 'o projeto tem skill security, agente planner com o mesmo nome de item do plugin, sem override' <<< "$s" || fail sombra "$s"
grep -qF 'minha-skill' <<< "$s" && fail sombra-so-mesmo-nome "$s"

# o SessionStart imprime as trocas (o hook chama o overrides.mjs)
p=$(proj inicio 'override = tdd'); skill "$p" tdd
out=$(printf '{"session_id":"s1"}' | CLAUDE_PLUGIN_ROOT=$plugin CLAUDE_PROJECT_DIR=$p bash "$plugin/hooks/session-start.sh" 2> /dev/null)
grep -qF 'skill tdd do projeto no lugar do wstack:tdd' <<< "$out" || fail session-start "$out"

if [ "$fails" -eq 0 ]; then echo "test-overrides: todos os casos passaram"; exit 0; fi
echo "test-overrides: $fails falha(s)"
exit 1
