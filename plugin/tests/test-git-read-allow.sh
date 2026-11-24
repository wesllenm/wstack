#!/usr/bin/env bash
# Casos do git-read-allow (hook PreToolUse em Bash que libera git log/diff/show só num formato fechado), sem rede.
# Para cada caso liberado, prova diferencial: o mesmo texto roda no bash (com extglob, globstar e nullglob ligados, o
# pior caso do shell do desenvolvedor) com um git falso no PATH que grava os argumentos recebidos; o teste reprova se
# o git recebeu outra coisa que não as palavras do texto (alguma expansão do bash que o formato deixou passar).
# Uso: test-git-read-allow.sh [<git-read-allow.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

top=$(git rev-parse --show-toplevel 2> /dev/null)
hook=${1:-$top/.claude/hooks/git-read-allow.sh}
[ -f "$hook" ] || { echo "git-read-allow.sh não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
hook=$(cd "$(dirname "$hook")" && pwd -P)/$(basename "$hook")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-gra-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0

# git falso: grava um argumento por linha
mkdir -p "$work/bin" "$work/cwd"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$ARGV_OUT"\nfor a in "$@"; do [ "$a" = - ] && cat > "$ARGV_OUT.in"; done\nexit 0\n' > "$work/bin/git"
chmod +x "$work/bin/git"
# iscas para glob e extglob: se o bash expandir, o argumento muda
touch "$work/cwd/--output=.git" "$work/cwd/HEADx" "$work/cwd/a.cs"

verdict() { # imprime allow ou nada
  jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' |
    bash "$hook" 2> /dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null
}

same_argv() { # 0 se o git recebe exatamente as palavras do texto, até o primeiro redirecionamento ou pipe
  local want got
  want=$(printf '%s\n' "$1" | sed -E 's/ +(2>.*|\|.*)$//' | tr -s ' ' '\n' | tail -n +2)
  (cd "$work/cwd" && PATH="$work/bin:$PATH" ARGV_OUT="$work/argv" bash -O extglob -O globstar -O nullglob -c "$1" > /dev/null 2>&1)
  got=$(cat "$work/argv" 2> /dev/null); rm -f "$work/argv"
  [ "$got" = "$want" ]
}

expect() { # expect <allow|none> <comando>
  local got; got=$(verdict "$2"); got=${got:-none}
  if [ "$got" != "$1" ]; then echo "FALHOU: esperado $1, obtido $got: $2"; fails=$((fails + 1)); return; fi
  [ "$1" = allow ] || return 0
  same_argv "$2" || { echo "FALHOU: o git recebeu argumentos diferentes do texto: $2"; fails=$((fails + 1)); }
}

# a prova diferencial pega expansão de verdade (senão ela não provaria nada)
same_argv 'git log -1 --o*' && { echo "FALHOU: a prova diferencial não viu o glob"; fails=$((fails + 1)); }
same_argv 'git log -1 --o@(u)tput=.git' && { echo "FALHOU: a prova diferencial não viu o extglob"; fails=$((fails + 1)); }
same_argv 'git log -1 --o{u,u}tput' && { echo "FALHOU: a prova diferencial não viu as chaves"; fails=$((fails + 1)); }
same_argv 'git log -1 HEAD~1' || { echo "FALHOU: a prova diferencial recusou um caso literal"; fails=$((fails + 1)); }

# rotina liberada
expect allow 'git log --oneline -20'
expect allow 'git log --oneline -5 HEAD~2..HEAD'
expect allow 'git log -1 --format=%h%x20%s'
expect allow 'git log --stat origin/main..HEAD'
expect allow 'git log --grep=^checkpoint: origin/main..HEAD'
expect allow 'git diff'
expect allow 'git diff --stat'
expect allow 'git diff --staged --stat'
expect allow 'git diff --stat main...HEAD -- .claude docs'
expect allow 'git diff --name-only --diff-filter=AM HEAD'
expect allow 'git diff 96d6229 -- .claude/hooks/push-guard.mjs'
expect allow 'git show HEAD^:docs/x.md | head -5'
expect allow 'git show --stat HEAD'
expect allow 'git log -1 2>/dev/null'
expect allow 'git log -1 2>&1 | tail -3'
expect allow 'git diff --stat | tail -n 5'
expect allow 'git log --author=t@t --since=2026-11-01'
expect allow 'git log --oneline main..HEAD -- src/a.cs'
expect allow 'git stash list'
expect allow 'git stash list --oneline'
expect allow 'git switch -c chore/x-1'
expect allow 'git branch --list'

# ler fora do repositório (no-index explícito ou implícito) mostraria arquivo que o deny de Read protege
expect none 'git diff --no-index /dev/null .env'
expect none 'git diff --no-index a.cs .env'
expect none 'git diff /dev/null .env'
expect none 'git diff -- ../x/.env'
expect none 'git diff HEAD -- ..'
expect none 'git diff .env src/../../x/.env'
expect none 'git log --relative=/x'
expect none 'git log --relative=src/../..'
expect none 'git log --relative=../x'
expect none 'git log -O/etc/passwd'
expect none 'git log -O../x'
# no Git Bash, letra de drive também é caminho absoluto (o git entra no no-index)
expect none 'git diff .env C:/Windows/win.ini'
expect none 'git diff .env c:x'
expect none 'git diff -- .env D:/x'
expect none 'git log -OC:/x'
expect none 'git log --relative=C:/x'
# git stash list aceita as opções do git log
expect none 'git stash list --output=.git/config'
# switch -c com ponto de partida troca a árvore (os hooks inclusive) pela de outro commit
expect none 'git switch -c x 96d6229'
expect none 'git switch -c x --discard-changes'
expect none 'git switch -c -x'
# branch --list com argumento: --no-list -D apaga a branch por cima do deny
expect none 'git branch --list --no-list -D x'
expect none 'git branch --list x'

# fora do formato: nada daqui, vale o pedido de permissão normal
expect none 'git log --output=.git/config'
expect none 'git log -1 --format=%B --outp=.git/config'
expect none 'git diff --output-indicator-new=+'
expect none 'git log -1 --format=%B --o{u,u}tput=.git/config'
expect none 'git log -1 --format=%B -{-o,-o}utput=.git/config'
expect none 'git log -1 --format=%B {--ou,--ou}tput=.git/config'
expect none 'git log -1 --format=%B --o[u]tput=.git/config'
expect none 'git log -1 --format=%B --o?tput=.git/config'
expect none 'git log -1 --format=%B --o*'
expect none 'git log -1 --format=%B --o@(u)tput=.git/config'
expect none 'git log -1 --format=%B --o+(u)tput=.git/config'
expect none "git log -1 --format=%B --\$'o'utput=.git/config"
expect none 'X=utput; git log --o$X=.git/config'
expect none 'git log -1 > .git/config'
expect none 'git log -1 >> /tmp/x'
expect none 'git log -1 >&2'
expect none 'git log -1 2>.git/config'
expect none 'git log -1 1<>.git/config'
expect none 'git log -1 </dev/null'
expect none 'git log -1 <(true)'
expect none 'git log -1 | tee .git/config'
expect none 'git log -1 | tail -3 > x'
expect none 'git log -1; rm -rf x'
expect none 'git log -1 && git status'
expect none 'git log "-1"'
expect none "git log '-1'"
expect none 'git log \-1'
expect none 'git log -1 ~/x'
expect none 'git log -1 a=~/x'
expect none 'git log -1 a:~/x'
expect none 'git log -1 HEAD@{1}'
expect none 'git log -1 #x'
expect none 'git log -1 !x'
expect none "$(printf 'git log -1\nrm x')"
expect none "$(printf 'git log -1\r')"
expect none "$(printf 'git\tlog -1')"
expect none "$(printf 'git log -1\\\n--output=x')"
expect none ' git log -1'
expect none 'git -C x log -1'
expect none 'git -c core.pager=x log -1'
expect none 'git --no-pager log -1'
expect none 'GIT_DIR=x git log -1'
expect none 'cd x && git log -1'
expect none 'git logx -1'
expect none 'git status'

# git add: mesmo formato fechado, sem forçar (o .gitignore esconde o .env; git add -f o poria no índice)
expect allow 'git add src/a.cs docs'
expect allow 'git add -A'
expect allow 'git add -u -- .claude'
expect none 'git add -f .env'
expect none 'git add --force .env'
expect none 'git add --fo .env'
expect none 'git add -nf .env'
expect none 'git add -Af'
expect none 'git add --pathspec-from-file=.env'
expect none 'git add "src/a b.cs"'
expect none 'git add ../x'
expect none 'git add /tmp/x'
expect none 'git add src/*.cs'

# git commit: só o heredoc com delimitador entre aspas ou -F com arquivo literal da pasta temporária
expect_commit() { # expect_commit <allow|none> <comando> [<corpo esperado no stdin do git>]
  local got; got=$(verdict "$2"); got=${got:-none}
  if [ "$got" != "$1" ]; then echo "FALHOU: esperado $1, obtido $got: $2"; fails=$((fails + 1)); return; fi
  [ $# -eq 3 ] || return 0
  # o corpo chega ao git literal (o bash não expande nada num heredoc com delimitador entre aspas)
  (cd "$work/cwd" && PATH="$work/bin:$PATH" ARGV_OUT="$work/argv" bash -O extglob -c "$2" > /dev/null 2>&1)
  [ "$(cat "$work/argv.in" 2> /dev/null)" = "$3" ] || { echo "FALHOU: o corpo do heredoc chegou alterado ao git: $2"; fails=$((fails + 1)); }
  rm -f "$work/argv" "$work/argv.in"
}
body='fix(x): corpo com $HOME, `id`, $(id), * e <a@b.c>
Co-Authored-By: A <a@b.c>'
expect_commit allow "git commit -F - <<'EOF'
$body
EOF" "$body"
expect_commit allow "git commit -q -F - <<'EOF'
$body
EOF
" "$body"
expect_commit allow 'git commit -F /tmp/claude-msg.txt'
expect_commit allow "git commit -q -F ${TMPDIR:-/tmp}/claude-msg.txt"
expect_commit none 'git commit -F .env'
expect_commit none 'git commit -F - < .env'
expect_commit none 'git commit -F /tmp/../root/x'
expect_commit none 'git commit -F /etc/passwd'
expect_commit none 'git commit -m x'
expect_commit none 'git commit -am x'
expect_commit none 'git commit --amend --no-edit'
expect_commit none 'git commit -t .env'
expect_commit none "git commit -F - <<EOF
\$(id)
EOF"
expect_commit none "git commit -F - <<\"EOF\"
x
EOF"
expect_commit none "git commit -F - <<'EOF'
x
EOF
rm -rf x"
expect_commit none "git commit -F - <<'EOF'
x
EOF
git push origin main
EOF"
expect_commit none "git commit -F - <<'EOF' < .env
x
EOF"
expect_commit none "git commit -F - <<'EOF'; rm x
x
EOF"
expect none 'git worktree add ~/.config/git HEAD'
expect none "git log -1 $(printf '\302\240')x"

# varredura com o git real: as opções que o --git-completion-helper lista para log, diff e show (as de diff e as
# próprias do log) nos quatro subcomandos, e as opções longas que aparecem no binário do git (as de revisão, como
# --since e --all, que o helper não lista) no git log, com um valor que seria um arquivo novo; se o hook libera, a
# opção roda num repositório de teste (com uma stash) e o arquivo não pode nascer. Os furos desta série estavam no
# lado do git (--output, no-index), não no shell: a lista à mão não basta.
sweep=$work/sweep
git init -q "$sweep" && git -C "$sweep" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
echo x > "$sweep/f.txt" && git -C "$sweep" add f.txt && git -C "$sweep" -c user.email=t@t -c user.name=t commit -q -m f
echo y > "$sweep/f.txt" && git -C "$sweep" -c user.email=t@t -c user.name=t stash -q
opts=$( { git -C "$sweep" diff --git-completion-helper; git -C "$sweep" log --git-completion-helper; git -C "$sweep" show --git-completion-helper; } 2> /dev/null | tr ' ' '\n' | grep -E '^--[a-z]' | sed 's/=$//' | sort -u)
gitbin=$(command -v git)
binopts=""
command -v strings > /dev/null && binopts=$(strings "$gitbin" 2> /dev/null | grep -E '^--[a-z][a-z0-9-]*=?$' | sed 's/=$//' | sort -u | comm -23 - <(printf '%s\n' $opts))
swept=0
for o in $binopts; do
  c="git log $o=sent.txt"
  [ "$(verdict "$c")" = allow ] || continue
  swept=$((swept + 1))
  (cd "$sweep" && GIT_PAGER=cat timeout 10 bash -c "$c" < /dev/null > /dev/null 2>&1)
  if [ -e "$sweep/sent.txt" ]; then echo "FALHOU: liberado e gravou arquivo: $c"; fails=$((fails + 1)); rm -f "$sweep/sent.txt"; fi
done
for o in $opts; do
  for sub in log diff show 'stash list'; do
    c="git $sub $o=sent.txt"
    [ "$(verdict "$c")" = allow ] || continue
    swept=$((swept + 1))
    (cd "$sweep" && GIT_PAGER=cat timeout 10 bash -c "$c" < /dev/null > /dev/null 2>&1)
    if [ -e "$sweep/sent.txt" ]; then echo "FALHOU: liberado e gravou arquivo: $c"; fails=$((fails + 1)); rm -f "$sweep/sent.txt"; fi
  done
done
[ "$swept" -gt 100 ] || { echo "FALHOU: varredura liberou só $swept formas (lista de opções do git vazia?)"; fails=$((fails + 1)); }

# varredura do git add com o git real: toda opção que o git lista para add, sozinha e com =valor, junto do arquivo
# ignorado; se o hook libera, o arquivo ignorado não pode entrar no índice (uma forma de forçar que a lista à mão
# não conhece)
printf 'sec.env\n' > "$sweep/.gitignore" && echo SECRET > "$sweep/sec.env"
addopts=$(git -C "$sweep" add --git-completion-helper 2> /dev/null | tr ' ' '\n' | grep -E '^--?[a-z]' | sed 's/=$//' | sort -u)
addswept=0
for o in $addopts -f -A -u -N -n -v; do
  for c in "git add $o sec.env" "git add $o=x sec.env"; do
    [ "$(verdict "$c")" = allow ] || continue
    addswept=$((addswept + 1))
    (cd "$sweep" && timeout 10 bash -c "$c" < /dev/null > /dev/null 2>&1)
    if git -C "$sweep" ls-files --error-unmatch sec.env > /dev/null 2>&1; then
      echo "FALHOU: liberado e pôs o arquivo ignorado no índice: $c"; fails=$((fails + 1)); git -C "$sweep" rm -q --cached sec.env
    fi
  done
done
[ "$addswept" -gt 10 ] || { echo "FALHOU: varredura do git add liberou só $addswept formas"; fails=$((fails + 1)); }

# payload ilegível: nada (o pedido normal vale)
got=$(printf 'não é json' | bash "$hook" 2> /dev/null)
[ -z "$got" ] || { echo "FALHOU: payload ilegível liberou algo"; fails=$((fails + 1)); }

if [ "$fails" -eq 0 ]; then echo "test-git-read-allow: todos os casos passaram"; exit 0; fi
echo "test-git-read-allow: $fails falha(s)"
exit 1
