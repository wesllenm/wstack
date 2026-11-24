#!/usr/bin/env bash
# Manda para a nuvem a execução de um plano aprovado localmente: planejar no terminal com o lead,
# aprovar, commitar o plano com a linha de aprovação, fazer push, e então este script abre a sessão na nuvem.
# Confere antes o que faria a sessão nascer errada: plano não commitado, sem aprovação, branch sem push.
# Uso: enviar-nuvem.sh <plano.md> [--dry-run]
#   o plano tem uma linha "Aprovado: <data> por <nome>" escrita por quem aprovou
# Código: 0 sessão criada (ou comando mostrado em --dry-run), 2 uso errado, 3 pré-condição falhou.
set -uo pipefail

plan=""; dry=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    -*) echo "opção desconhecida: $a" >&2; exit 2 ;;
    *) [ -z "$plan" ] || { echo "mais de um plano" >&2; exit 2; }; plan=$a ;;
  esac
done
[ -n "$plan" ] || { echo "uso: enviar-nuvem.sh <plano.md> [--dry-run]" >&2; exit 2; }

root=$(git rev-parse --show-toplevel 2> /dev/null) || { echo "fora de um repositório git" >&2; exit 3; }
[ -f "$plan" ] || { echo "plano não encontrado: $plan" >&2; exit 3; }
abs=$(cd "$(dirname "$plan")" && pwd -P)/$(basename "$plan")
rootp=$(cd "$root" && pwd -P)
case "$abs" in "$rootp"/*) rel=${abs#"$rootp"/} ;; *) echo "o plano precisa estar dentro do repositório" >&2; exit 3 ;; esac
cd "$root" || exit 3

git ls-files --error-unmatch -- "$rel" > /dev/null 2>&1 || { echo "plano não commitado: $rel (a sessão na nuvem clona o GitHub, não o seu disco)" >&2; exit 3; }
git diff --quiet HEAD -- "$rel" || { echo "plano com mudança não commitada: $rel" >&2; exit 3; }
grep -Eq '^[[:space:]>*-]*Aprovado:[[:space:]]*[^[:space:]]' "$rel" || { echo "plano sem a linha \"Aprovado: <data> por <nome>\": a sessão na nuvem só executa plano aprovado" >&2; exit 3; }

branch=$(git symbolic-ref --short -q HEAD) || { echo "HEAD destacado: faça checkout de uma branch" >&2; exit 3; }
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2> /dev/null) || { echo "branch $branch sem upstream: git push -u origin $branch" >&2; exit 3; }
ahead=$(git rev-list --count '@{u}..HEAD' 2> /dev/null || echo 1)
[ "$ahead" = 0 ] || { echo "branch $branch tem $ahead commit(s) sem push para $upstream" >&2; exit 3; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || echo "aviso: há mudanças locais não commitadas; elas não vão para a nuvem" >&2
remote=${upstream%%/*}
url=$(git remote get-url "$remote" 2> /dev/null || true)
case "$url" in *github.com*) ;; *) echo "aviso: remoto $remote não é GitHub ($url); a sessão sobe o checkout local e não consegue fazer push de volta" >&2 ;; esac

sha=$(git rev-parse --short HEAD)
# A linha "Aprovado:" sozinha não prova o que foi aprovado: o plano pode ter sido reescrito depois. O hash do conteúdo
# vai na mensagem, e a sessão na nuvem recusa o plano se o hash dele divergir (skill lead, Execução na nuvem).
phash=$(git hash-object -- "$rel")
msg="Execute o plano aprovado em $rel (branch $branch, commit $sha, hash do plano $phash). A aprovação está no próprio plano: confira que git hash-object $rel dá exatamente $phash (senão recuse e devolva), siga a skill lead, seção Execução na nuvem, e entregue por PR."
if [ "$dry" = 1 ]; then
  printf 'claude --cloud %q\n' "$msg"
  exit 0
fi
command -v claude > /dev/null || { echo "claude não encontrado no PATH" >&2; exit 3; }
echo "Plano: $rel"; echo "Hash: $phash"; git log -1 --format='Último commit do plano: %h %an, %ad' -- "$rel"
grep -E '^[[:space:]>*-]*Aprovado:' "$rel" | head -3
printf 'Enviar este plano para a nuvem? [s/N] '
read -r answer || answer=""
[ "$answer" = s ] || [ "$answer" = S ] || { echo "cancelado" >&2; exit 3; }
exec claude --cloud "$msg"
