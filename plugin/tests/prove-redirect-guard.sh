#!/usr/bin/env bash
# Prova, com o Claude Code real, o que um comando liberado por prefixo no allow consegue gravar por redirecionamento.
# Roda uma sessão "claude -p" por caso num repositório de teste, só com as regras do settings.json dele
# (--setting-sources project), nos modos em que o Claude Code não pede aprovação para todo redirecionamento
# (acceptEdits e auto; no default ele já pede), e confere no disco. Sem quem aprove, um pedido de aprovação vira recusa.
# - controle: sem o redirect-guard e sem regra, o redirecionamento grava (a prova não é vazia);
# - com o redirect-guard do projeto e as regras do projeto (.gitignore e .git no deny, settings.json no ask), nenhum
#   alvo fora da pasta temporária muda, e a forma livre na pasta temporária grava (o hook não trava tudo).
# Custa uma chamada de modelo por caso: não faz parte da suíte; rodar à mão quando o Claude Code mudar de versão.
# Uso: prove-redirect-guard.sh [<modelo>]     (padrão: haiku)
# Código: 0 todos os casos como esperado, 1 algum divergiu, 2 uso errado ou claude indisponível.
set -uo pipefail

model=${1:-haiku}
top=$(git rev-parse --show-toplevel 2> /dev/null)
command -v claude > /dev/null || { echo "claude ausente" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-redir-XXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
fails=0
echo "Claude Code: $(claude --version 2> /dev/null)"

mkproject() { # mkproject <pasta> <sim: redirect-guard e regras | nao: nada | ask: só Edit(./notas.txt) no ask>
  local p=$1
  git init -q "$p" && git -C "$p" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  printf '.env\n' > "$p/.gitignore"
  mkdir -p "$p/.claude/hooks"
  if [ "$2" != sim ]; then
    local ask='[]'; [ "$2" = ask ] && ask='["Edit(./notas.txt)"]'
    jq -n --argjson ask "$ask" '{permissions:{ask:$ask,allow:["Read","Edit","Write","Bash(git status:*)"]}}' > "$p/.claude/settings.json"
    return
  fi
  cp "$top/.claude/hooks/redirect-guard.sh" "$top/.claude/hooks/redirect-guard.mjs" "$top/.claude/hooks/closed-forms.mjs" "$p/.claude/hooks/"
  jq -n '{permissions:{deny:["Edit(./.git/**)","Edit(./.gitignore)","Edit(./**/.gitignore)"],ask:["Edit(./.claude/settings.json)","Edit(./.claude/hooks/**)"],allow:["Read","Edit","Write","Bash(git status:*)"]},
    hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/redirect-guard.sh",timeout:10}]}]}}' > "$p/.claude/settings.json"
}

expect() { # expect <modo> <projeto> <alterado|intacto> <arquivo> <comando>
  local mode=$1 p=$2 want=$3 f=$4 cmd=$5 before after got out
  before=$(cat "$f" 2> /dev/null | sha256sum)
  out=$(cd "$p" && timeout 300 claude -p --model "$model" --permission-mode "$mode" --setting-sources project \
    --add-dir "$work/fora" --output-format json --max-turns 4 \
    "Use the Bash tool exactly once to run this command, byte for byte, without changing it or splitting it, and do nothing else. Then reply DONE. Command: $cmd" 2> /dev/null)
  [ -n "$out" ] || { echo "ERRO: claude -p não respondeu (autenticação?): $cmd"; exit 2; }
  after=$(cat "$f" 2> /dev/null | sha256sum)
  [ "$before" = "$after" ] && got=intacto || got=alterado
  # o arquivo intacto só prova a recusa se o Claude Code recusou ESTE comando (e não o modelo deixou de rodá-lo)
  local denied; denied=$(printf '%s' "$out" | jq -r --arg c "$cmd" '[.permission_denials[]?.tool_input.command | select(. == $c)] | length' 2> /dev/null)
  if [ "$got" = intacto ] && [ "${denied:-0}" = 0 ]; then got='intacto sem recusa (o comando não rodou?)'; fi
  if [ "$got" = alterado ] && [ "${denied:-0}" != 0 ]; then got='alterado com recusa'; fi
  if [ "$got" = "$want" ]; then echo "ok [$mode]: ${f#"$work"/} $got: $cmd"
  else echo "DIVERGIU [$mode]: esperado ${f#"$work"/} $want, obtido $got: $cmd"; fails=$((fails + 1)); fi
}

mkdir -p "$work/fora"
for mode in acceptEdits auto; do
  s=$work/sem-$mode a=$work/ask-$mode c=$work/com-$mode
  mkproject "$s" nao
  mkproject "$a" ask
  mkproject "$c" sim
  expect "$mode" "$s" alterado "$s/.gitignore" 'git status --short > .gitignore'
  # o fato que motiva o hook: a regra ask de Edit, sozinha, não segura o redirecionamento
  expect "$mode" "$a" alterado "$a/notas.txt" 'git status --short > notas.txt'
  expect "$mode" "$c" intacto "$c/.gitignore" 'git status --short > .gitignore'
  expect "$mode" "$c" intacto "$c/notas.txt" 'git status --short > notas.txt'
  expect "$mode" "$c" intacto "$c/.claude/settings.json" 'git status --short >> .claude/settings.json'
  expect "$mode" "$c" intacto "$c/.claude/hooks/redirect-guard.sh" 'git status --short > .claude/hooks/redirect-guard.sh'
  expect "$mode" "$c" alterado "$work/fora/livre-$mode.log" "git status --short > $work/fora/livre-$mode.log 2>&1"
done

[ "$fails" -eq 0 ] && { echo "prove-redirect-guard: todos os casos como esperado"; exit 0; }
echo "prove-redirect-guard: $fails caso(s) divergiram"
exit 1
