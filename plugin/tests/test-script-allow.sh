#!/usr/bin/env bash
# Casos do script-allow (hook PreToolUse em Bash que aprova os scripts do próprio plugin sem regra allow no projeto),
# sem rede e sem modelo. Aprova só formas fechadas: o interpretador fixo de cada script, o caminho da pasta do plugin que
# roda o hook, e argumentos de um alfabeto fechado (palavra simples, texto entre aspas simples, texto entre aspas duplas
# sem $, crase, barra invertida nem !), com a pasta do comando na raiz do projeto. Qualquer outra coisa: o hook não diz
# nada e vale o pedido de permissão normal (os outros hooks continuam conferindo o comando).
# Os hooks rodam de uma cópia instalada onde o Claude Code instala plugins (<home>/.claude/plugins/cache/...).
# Uso: test-script-allow.sh [<script-allow.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
src=${1:-$here/../hooks/script-allow.sh}
[ -f "$src" ] || { echo "script-allow.sh não encontrado: $src" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
src=$(cd "$(dirname "$src")" && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-sa-XXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
fails=0
plug=$work/home/.claude/plugins/cache/wstack/wstack/0.0.0
mkdir -p "$plug/scripts" "$plug/tests" "$plug/cloud" && cp -r "$src" "$plug/hooks"
for s in classify-diff.sh checkpoint.sh sessions.sh enviar-nuvem.sh nova-atividade.sh review-dispatch.mjs recall.mjs; do
  printf '#!/usr/bin/env bash\n' > "$plug/scripts/$s"
done
printf '#!/usr/bin/env bash\n' > "$plug/tests/test-path-guard.sh" && printf '#!/usr/bin/env bash\n' > "$plug/cloud/setup.sh"
hook=$plug/hooks/script-allow.sh
proj=$work/projeto
git init -q "$proj" && git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
mkdir -p "$proj/src" "$work/fora"

verdict() {
  jq -cn --arg c "$1" --arg d "${VCWD:-$proj}" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' |
    env ${NOPROJ:+-u CLAUDE_PROJECT_DIR} ${NOPROJ:-CLAUDE_PROJECT_DIR=$proj} bash "$hook" 2> /dev/null |
    jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null
}
expect() { # expect <allow|nada> <comando>
  local got; got=$(verdict "$2"); got=${got:-nada}
  [ "$got" = "$1" ] || { echo "FALHOU: esperado $1, obtido $got: $2 (cwd ${VCWD:-projeto})"; fails=$((fails + 1)); }
}

# formas aprovadas: script com argumentos livres, pelo interpretador dele (ou direto, onde a origem já liberava)
for c in "bash $plug/scripts/classify-diff.sh" "bash $plug/scripts/classify-diff.sh --paths src/a.cs docs/b.md" \
  "$plug/scripts/classify-diff.sh abc123" "bash $plug/scripts/checkpoint.sh permissoes 1 \"esperando aprovação\"" \
  "bash $plug/scripts/checkpoint.sh permissoes 2 'motivo com \$(id) literal'" "bash $plug/scripts/sessions.sh claim src/a.cs" \
  "$plug/scripts/sessions.sh touch" "node $plug/scripts/review-dispatch.mjs --base main --json" \
  "bash $plug/scripts/classify-diff.sh --base=origin/main" "bash $plug/scripts/classify-diff.sh  --paths   src/a.cs"; do
  expect allow "$c"
done
# formas exatas: os testes sem argumento, o setup da nuvem só em --check e --plan, a conferência de sintaxe
for c in "bash $plug/tests/test-path-guard.sh" "bash $plug/cloud/setup.sh --check" "bash $plug/cloud/setup.sh --plan" \
  "bash -n $plug/hooks/push-guard.sh" "bash -n $plug/scripts/checkpoint.sh" "bash -n $plug/cloud/setup.sh"; do
  expect allow "$c"
done

# fora da lista: o que pede aprovação de propósito e o que a origem nunca liberou
for c in "bash $plug/scripts/enviar-nuvem.sh plano" "bash $plug/scripts/nova-atividade.sh x" "node $plug/scripts/recall.mjs termo" \
  "node $plug/scripts/otlp-sink.mjs" "bash $plug/scripts/inexistente.sh"; do
  expect nada "$c"
done
# interpretador trocado, ou execução direta onde a origem não liberava
for c in "node $plug/scripts/classify-diff.sh" "bash $plug/scripts/review-dispatch.mjs" "sh $plug/scripts/classify-diff.sh" \
  "$plug/scripts/checkpoint.sh a 1 b" "$plug/scripts/review-dispatch.mjs" "bash -x $plug/scripts/classify-diff.sh" \
  "env bash $plug/scripts/classify-diff.sh" "X=1 bash $plug/scripts/classify-diff.sh" " bash $plug/scripts/classify-diff.sh"; do
  expect nada "$c"
done
# argumento fora do alfabeto fechado: operador, redirecionamento, expansão, aspas abertas ou escapadas, quebra de linha
for a in '; rm -rf x' '&& cp a b' '| tail -2' '> out.txt' '2>&1' '$(id)' '`id`' '"$HOME"' '"a\"b"' '"a`id`"' "'aberta" \
  '"aberta' '*' 'src/*.cs' '~/x' '{a,b}' '#comentario' '!x' '"a!b"' 'a\b' $'a\nb' $'a\tb' 'a&' '(x)' 'x;' '<in'; do
  expect nada "bash $plug/scripts/classify-diff.sh $a"
done
expect nada "bash $plug/scripts/checkpoint.sh a 1 b"$'\n'"cp x y"
# caminho que não é a pasta deste plugin: subida, outro lugar com o mesmo formato, prefixo parecido, relativo
for c in "bash $plug/scripts/../hooks/x.sh" "bash $plug/scripts/x/../classify-diff.sh" "bash $plug/scripts/./classify-diff.sh" \
  "bash $work/fora/.claude/plugins/cache/wstack/wstack/0.0.0/scripts/classify-diff.sh" "bash ${plug}x/scripts/classify-diff.sh" \
  "bash $plug/x/scripts/classify-diff.sh" "bash .claude/scripts/classify-diff.sh" "bash scripts/classify-diff.sh" \
  "bash $plug//scripts/classify-diff.sh" "bash $plug/hooks/push-guard.sh"; do
  expect nada "$c"
done
# formas exatas não aceitam argumento nem outra opção
for c in "bash $plug/tests/test-path-guard.sh /tmp/x" "bash $plug/cloud/setup.sh" "bash $plug/cloud/setup.sh --install" \
  "bash $plug/cloud/setup.sh --check x" "bash -n $plug/hooks/../../x" "bash -n $plug/hooks/push-guard.sh x" "bash $plug/tests/inexistente.sh"; do
  expect nada "$c"
done
# a pasta do comando fora da raiz do projeto (o script trataria outro repositório), ou sem projeto de referência
VCWD=$proj/src expect nada "bash $plug/scripts/classify-diff.sh"
VCWD=$work/fora expect nada "bash $plug/scripts/classify-diff.sh"
NOPROJ=1 expect nada "bash $plug/scripts/classify-diff.sh"
nested=$proj/aninhado; git init -q "$nested"
VCWD=$nested expect nada "bash $plug/scripts/classify-diff.sh"
# payload ilegível ou sem comando: nada
got=$(printf 'x' | CLAUDE_PROJECT_DIR=$proj bash "$hook" 2> /dev/null)
[ -z "$got" ] || { echo "FALHOU: payload ilegível aprovou: $got"; fails=$((fails + 1)); }
got=$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{}}' "$proj" | CLAUDE_PROJECT_DIR=$proj bash "$hook" 2> /dev/null)
[ -z "$got" ] || { echo "FALHOU: payload sem comando aprovou: $got"; fails=$((fails + 1)); }
# sem node, o hook não diz nada
nonode=$work/semnode; mkdir -p "$nonode"; for b in bash cat dirname jq printf; do ln -sf "$(command -v $b)" "$nonode/$b"; done
got=$(jq -cn --arg c "bash $plug/scripts/classify-diff.sh" --arg d "$proj" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' |
  PATH=$nonode CLAUDE_PROJECT_DIR=$proj "$nonode/bash" "$hook" 2> /dev/null)
[ -z "$got" ] || { echo "FALHOU: sem node o hook aprovou: $got"; fails=$((fails + 1)); }

if [ "$fails" -eq 0 ]; then echo "test-script-allow: todos os casos passaram"; exit 0; fi
echo "test-script-allow: $fails falha(s)"
exit 1
