#!/usr/bin/env bash
# Casos do prune-merged.sh, sem rede: um repositório local com remoto github.com falso e um `gh` falso no PATH que aplica o
# filtro --jq do script (com o jq de verdade) sobre a lista de PRs da fixture e confere os parâmetros da consulta.
# Uso: test-prune-merged.sh [<prune-merged.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

top=$(git rev-parse --show-toplevel 2> /dev/null)
script=${1:-$top/.claude/scripts/prune-merged.sh}
[ -f "$script" ] || { echo "prune-merged.sh não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente: o gh falso precisa dele" >&2; exit 2; }
script=$(cd "$(dirname "$script")" && pwd -P)/$(basename "$script")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-prune-merged-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0

mkdir -p "$work/bin"
cat > "$work/bin/gh" << 'EOF'
#!/usr/bin/env bash
# gh falso: só "api -X GET repos/<repo>/pulls -f head=... -f state=closed -f per_page=100 --jq <filtro>".
[ "${FAKE_GH_FAIL:-}" = 1 ] && { echo "HTTP 403: API rate limit exceeded" >&2; exit 1; }
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
[ "$1 $2 $3 $4" = "api -X GET repos/acme/app/pulls" ] || { echo "gh falso: chamada inesperada: $*" >&2; exit 9; }
shift 4
head='' state='' filter=''
while [ $# -gt 0 ]; do
  case $1 in
    -f) case $2 in head=*) head=${2#head=} ;; state=*) state=${2#state=} ;; per_page=*) ;; *) exit 9 ;; esac; shift 2 ;;
    --jq) filter=$2; shift 2 ;;
    *) echo "gh falso: argumento inesperado: $1" >&2; exit 9 ;;
  esac
done
[ "$state" = closed ] && [ -n "$filter" ] || exit 9
file="$FAKE_GH_DIR/${head//[:\/]/_}.json"
if [ -f "$file" ]; then jq -r "$filter" "$file"; else jq -r "$filter" <<< '[]'; fi
EOF
chmod +x "$work/bin/gh"

repo=$work/repo
git init -q -b main "$repo"
git -C "$repo" config user.email t@t && git -C "$repo" config user.name t
git -C "$repo" commit -q --allow-empty -m base
git -C "$repo" remote add origin https://github.com/acme/app.git
mkdir -p "$work/prs"

branch() { # branch <nome>: cria a branch com um commit próprio e imprime o sha
  git -C "$repo" branch -q "$1" main
  git -C "$repo" -c advice.detachedHead=false checkout -q "$1"
  git -C "$repo" commit -q --allow-empty -m "$1"
  git -C "$repo" checkout -q main
  git -C "$repo" rev-parse "$1"
}
pr() { # pr <branch> <número> <sha> <merged|closed|open>
  local merged=null
  [ "$4" = merged ] && merged='"2026-11-18T00:00:00Z"'
  local f="$work/prs/acme_${1//\//_}.json"
  [ -f "$f" ] || echo '[]' > "$f"
  jq --arg n "$2" --arg s "$3" --arg b "$1" --argjson m "$merged" \
    '. + [{number: ($n|tonumber), merged_at: $m, head: {ref: $b, sha: $s}}]' "$f" > "$f.new" && mv "$f.new" "$f"
}
run() { # run <rc esperado> <padrão esperado na saída> <args...>
  local want=$1 pat=$2 out rc
  shift 2
  out=$(cd "$repo" && PATH="$work/bin:$PATH" FAKE_GH_DIR="$work/prs" FAKE_GH_LOG="$work/gh.log" bash "$script" "$@" 2>&1); rc=$?
  if [ "$rc" != "$want" ] || ! grep -Eq -- "$pat" <<< "$out"; then
    echo "FALHOU: prune-merged.sh $* — esperado rc=$want e /$pat/, obtido rc=$rc:"
    sed 's/^/    /' <<< "$out"
    fails=$((fails + 1))
  fi
}
exists() { git -C "$repo" show-ref -q --verify "refs/heads/$1"; }
expect_kept() { exists "$1" || { echo "FALHOU: a branch $1 foi apagada"; fails=$((fails + 1)); }; }
expect_gone() { ! exists "$1" || { echo "FALHOU: a branch $1 continua"; fails=$((fails + 1)); }; }

# apaga: PR mesclado cujo commit recebido é o da branch local (também com squash: a main não tem os commits)
s=$(branch feat/1-ok); pr feat/1-ok 1 "$s" merged
git -C "$repo" config branch.feat/1-ok.remote origin
run 0 '^apagada feat/1-ok .*PR #1' feat/1-ok
expect_gone feat/1-ok
[ -z "$(git -C "$repo" config --get branch.feat/1-ok.remote)" ] || { echo "FALHOU: config da branch ficou"; fails=$((fails + 1)); }
grep -q -- '-f head=acme:feat/1-ok' "$work/gh.log" || { echo "FALHOU: a consulta não filtrou por acme:feat/1-ok"; fails=$((fails + 1)); }

# mantém: commit local depois do que o PR recebeu
s=$(branch fix/2-mais); pr fix/2-mais 2 "$s" merged
git -C "$repo" checkout -q fix/2-mais && git -C "$repo" commit -q --allow-empty -m depois && git -C "$repo" checkout -q main
run 3 '^mantida fix/2-mais: .*commit' fix/2-mais
expect_kept fix/2-mais

# mantém: PR fechado sem merge, PR aberto e branch sem PR
s=$(branch chore/3-fechado); pr chore/3-fechado 3 "$s" closed
run 3 '^mantida chore/3-fechado: ' chore/3-fechado
expect_kept chore/3-fechado
s=$(branch task/4-aberto); pr task/4-aberto 4 "$s" open
run 3 '^mantida task/4-aberto: ' task/4-aberto
expect_kept task/4-aberto
branch feat/5-sem-pr > /dev/null
run 3 '^mantida feat/5-sem-pr: ' feat/5-sem-pr
expect_kept feat/5-sem-pr

# mantém: um PR mesclado antigo não cobre o commit novo, mesmo com outro PR do mesmo nome
s=$(branch feat/6-dois); pr feat/6-dois 6 0000000000000000000000000000000000000000 merged; pr feat/6-dois 7 "$s" open
run 3 '^mantida feat/6-dois: ' feat/6-dois
expect_kept feat/6-dois

# mantém: a branch em uso, a main e a branch aberta em outra worktree, mesmo com PR mesclado
s=$(branch feat/7-atual); pr feat/7-atual 8 "$s" merged
git -C "$repo" checkout -q feat/7-atual
run 3 '^mantida feat/7-atual: .*em uso' feat/7-atual
expect_kept feat/7-atual
git -C "$repo" checkout -q main
pr main 9 "$(git -C "$repo" rev-parse main)" merged
git -C "$repo" checkout -q feat/5-sem-pr
run 3 '^mantida main: branch principal' main
expect_kept main
git -C "$repo" checkout -q main
s=$(branch task/8-wt); pr task/8-wt 10 "$s" merged
git -C "$repo" worktree add -q "$work/wt" task/8-wt
run 3 '^mantida task/8-wt: .*worktree' task/8-wt
expect_kept task/8-wt
git -C "$repo" worktree remove "$work/wt"

# mantém: branch em rebase parado numa worktree e no checkout principal (HEAD destacado; o worktree list não a mostra)
conflict() { # conflict <branch>: a branch e a main mudam o mesmo arquivo; imprime o sha da ponta da branch
  git -C "$repo" branch -q "$1" main
  git -C "$repo" checkout -q "$1" && echo "$1" > "$repo/c.txt" && git -C "$repo" add c.txt && git -C "$repo" commit -q -m "$1"
  git -C "$repo" checkout -q main && echo "main $1" > "$repo/c.txt" && git -C "$repo" add c.txt && git -C "$repo" commit -q -m "main $1"
  git -C "$repo" rev-parse "$1"
}
s=$(conflict task/13-rebase-wt); pr task/13-rebase-wt 15 "$s" merged
git -C "$repo" worktree add -q "$work/wt-rb" task/13-rebase-wt
git -C "$work/wt-rb" rebase -q main > /dev/null 2>&1
git -C "$work/wt-rb" rev-parse -q --verify REBASE_HEAD > /dev/null || { echo "FALHOU: o rebase na worktree não parou"; fails=$((fails + 1)); }
run 3 '^mantida task/13-rebase-wt: em uso' task/13-rebase-wt
expect_kept task/13-rebase-wt
s=$(conflict task/14-rebase-aqui); pr task/14-rebase-aqui 16 "$s" merged
git -C "$repo" checkout -q task/14-rebase-aqui && git -C "$repo" rebase -q main > /dev/null 2>&1
git -C "$repo" rev-parse -q --verify REBASE_HEAD > /dev/null || { echo "FALHOU: o rebase no checkout principal não parou"; fails=$((fails + 1)); }
run 0 '^mantida task/14-rebase-aqui: em uso' --all
expect_kept task/14-rebase-aqui
git -C "$repo" rebase --abort && git -C "$repo" checkout -q main
git -C "$work/wt-rb" rebase --abort && git -C "$repo" worktree remove "$work/wt-rb"

# mantém: branch em bisect parado numa worktree
s=$(branch task/15-bisect); pr task/15-bisect 19 "$s" merged
git -C "$repo" worktree add -q "$work/wt-bi" task/15-bisect
git -C "$work/wt-bi" bisect start task/15-bisect main > /dev/null
run 3 '^mantida task/15-bisect: em uso' task/15-bisect
expect_kept task/15-bisect
git -C "$work/wt-bi" bisect reset > /dev/null 2>&1 && git -C "$repo" worktree remove "$work/wt-bi"

# --all com uma ref cujo nome parece opção (refs/heads/-m): não vira argumento do git e a main continua a branch atual
git -C "$repo" update-ref refs/heads/-m main
run 0 '^mantida -m: nome fora do alfabeto' --all
expect_kept main
[ "$(git -C "$repo" branch --show-current)" = main ] || { echo "FALHOU: a branch atual deixou de ser a main"; fails=$((fails + 1)); }
git -C "$repo" update-ref -d refs/heads/-m

# mantém: a branch padrão do origin, mesmo que não se chame main
s=$(branch develop); pr develop 17 "$s" merged
git -C "$repo" update-ref refs/remotes/origin/develop "$s"
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
run 3 '^mantida develop: branch principal' develop
expect_kept develop
git -C "$repo" symbolic-ref -d refs/remotes/origin/HEAD

# falha do gh: não apaga, sai 3 e mostra a causa que o gh deu
s=$(branch feat/9-gh); pr feat/9-gh 11 "$s" merged
FAKE_GH_FAIL=1 run 3 "rate limit" feat/9-gh
expect_kept feat/9-gh

# remoto com credencial na URL: recusa sem imprimir o token
git -C "$repo" remote set-url origin https://x-access-token:TOKEN_FALSO_123@github.com/acme/app.git
run 3 'github.com' feat/9-gh
out=$(cd "$repo" && PATH="$work/bin:$PATH" bash "$script" feat/9-gh 2>&1)
! grep -q TOKEN_FALSO_123 <<< "$out" || { echo "FALHOU: o token do origin apareceu na saída"; fails=$((fails + 1)); }
git -C "$repo" remote set-url origin https://github.com/acme/app.git

# uso errado: nome fora do alfabeto, opção desconhecida, sem argumento, branch inexistente
run 2 'alfabeto' 'feat/x;rm'
run 2 'alfabeto' '-x'
run 2 'uso'
run 3 '^mantida nao/existe: .*não existe' nao/existe

# --all: apaga só as mescladas e sai 0 mesmo mantendo as outras
s=$(branch feat/10-a); pr feat/10-a 12 "$s" merged
s=$(branch feat/11-b); pr feat/11-b 13 "$s" merged
run 0 'apagada feat/10-a.*' --all
expect_gone feat/10-a
expect_gone feat/11-b
expect_kept fix/2-mais
expect_kept main
expect_kept feat/5-sem-pr

# --all com o gh falhando: sai 3, nada apagado
s=$(branch feat/12-c); pr feat/12-c 14 "$s" merged
FAKE_GH_FAIL=1 run 3 "rate limit" --all
expect_kept feat/12-c

# remoto fora do github.com: recusa tudo
git -C "$repo" remote set-url origin https://gitlab.example.com/acme/app.git
run 3 'github.com' feat/12-c
expect_kept feat/12-c

if [ "$fails" -eq 0 ]; then echo "prune-merged: todos os casos passaram"; exit 0; fi
echo "prune-merged: $fails falha(s)"
exit 1
