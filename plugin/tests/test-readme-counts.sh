#!/usr/bin/env bash
# Confere as afirmações do README sobre a árvore do plugin contra a própria árvore: a contagem de subagentes, de skills
# e de playbooks, que cada agente e cada skill aparece pelo nome, e que a versão citada no README e na matriz de
# garantias é a do plugin.json. Uma afirmação sobre a árvore precisa ser verdadeira no commit que a introduz; este
# teste é o comando que a confere de novo (roda no CI com os demais).
# Uso: test-readme-counts.sh [<raiz do repositório>]
# Código: 0 tudo confere, 1 alguma divergência, 2 uso errado.
set -uo pipefail

root=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
readme=$root/README.md
caps=$root/docs/harness-capabilities.md
manifest=$root/plugin/.claude-plugin/plugin.json
for f in "$readme" "$caps" "$manifest"; do [ -f "$f" ] || { echo "não encontrado: $f" >&2; exit 2; }; done
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

agents=$(find "$root/plugin/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
skills=$(find "$root/plugin/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
playbooks=$(find "$root/plugin/skills/lead/playbooks" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')

# número citado no README, na linha da árvore do plugin
cited() { grep -oE "$1" "$readme" | head -1 | grep -oE '[0-9]+'; }
n=$(cited 'agents/ +[0-9]+ subagentes'); [ "$n" = "$agents" ] || fail "README diz ${n:-nada} subagentes; plugin/agents tem $agents"
n=$(cited 'skills/ +[0-9]+ skills'); [ "$n" = "$skills" ] || fail "README diz ${n:-nada} skills; plugin/skills tem $skills"
n=$(cited '[0-9]+ playbooks por tipo de tarefa'); [ "$n" = "$playbooks" ] || fail "README diz ${n:-nada} playbooks; lead/playbooks tem $playbooks"

# cada agente e cada skill aparece pelo nome, entre crases
for f in "$root"/plugin/agents/*.md; do
  a=$(basename "$f" .md); grep -qF "\`$a\`" "$readme" || fail "agente $a não aparece no README"
done
for d in "$root"/plugin/skills/*/; do
  s=$(basename "$d"); grep -qF "\`$s\`" "$readme" || fail "skill $s não aparece no README"
done

# a versão do README e da matriz é a do plugin.json
v=$(jq -r .version "$manifest")
grep -qF "versão $v." "$readme" || fail "README não cita a versão $v do plugin.json (Estado: versão X.)"
grep -qF "Versão $v:" "$caps" || fail "docs/harness-capabilities.md não cita a versão $v do plugin.json"

if [ "$fails" -eq 0 ]; then echo "test-readme-counts: tudo confere ($agents agentes, $skills skills, $playbooks playbooks, versão $v)"; exit 0; fi
echo "test-readme-counts: $fails divergência(s)"
exit 1
