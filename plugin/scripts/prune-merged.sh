#!/usr/bin/env bash
# Apaga a branch LOCAL de uma atividade cujo PR já foi mesclado no GitHub, só quando nada se perde: existe PR mesclado da
# branch, vindo do próprio repositório, e o commit que o PR recebeu é exatamente a ponta da branch local (com squash, a main
# nunca contém os commits da branch; por isso a prova é o commit do PR, não a main). Nunca apaga a main nem a branch padrão
# do origin; a branch em uso em qualquer worktree (checkout, rebase ou bisect) é recusada pela checagem do próprio git. Não
# toca o remoto. O `git branch -D` continua no deny: este script é a via do agente.
# Uso: prune-merged.sh <branch>...   apaga as indicadas; qualquer uma mantida sai 3
#      prune-merged.sh --all         tenta todas as branches locais; manter as não mescladas é normal (sai 0)
# Código: 0 feito; 2 uso errado; 3 branch indicada mantida, ou falha ao consultar o GitHub ou ao apagar.
set -uo pipefail

usage() { echo "uso: prune-merged.sh <branch>... | --all" >&2; exit 2; }
name_ok() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$ ]]; }
[ $# -ge 1 ] || usage
all=0
if [ "$1" = --all ]; then
  [ $# -eq 1 ] || usage
  all=1
else
  for b in "$@"; do
    name_ok "$b" || { echo "nome de branch fora do alfabeto (A-Z, a-z, 0-9, . _ / -): $b" >&2; exit 2; }
  done
fi

git rev-parse --git-dir > /dev/null 2>&1 || { echo "fora de um repositório git" >&2; exit 3; }
# Antes do 2.35 o `git branch -f` só recusava a branch atual da worktree atual: a sonda de uso abaixo não valeria.
[[ $(git version) =~ ([0-9]+)\.([0-9]+) ]] && { [ "${BASH_REMATCH[1]}" -gt 2 ] || [ "${BASH_REMATCH[2]}" -ge 35 ]; } \
  || { echo "git 2.35 ou mais novo é necessário ($(git version))" >&2; exit 3; }
url=$(git remote get-url origin 2> /dev/null) || { echo "sem remoto origin" >&2; exit 3; }
if [[ $url =~ ^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9-]{1,39})/([A-Za-z0-9._-]{1,100})$ ]]; then
  owner=${BASH_REMATCH[2]} name=${BASH_REMATCH[3]%.git}
else
  # Sem a URL na mensagem: ela pode levar credencial (https://<usuário>:<token>@github.com/...).
  echo "o origin não é um repositório do github.com na forma https://github.com/<dono>/<repo> ou git@github.com:<dono>/<repo>: nada a conferir" >&2
  exit 3
fi
command -v gh > /dev/null || { echo "gh ausente: não há como consultar o GitHub" >&2; exit 3; }

default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2> /dev/null || true)
default=${default#origin/}
err=$(mktemp) || exit 3
trap 'rm -f "$err"' EXIT

if [ "$all" = 1 ]; then
  mapfile -t branches < <(git for-each-ref --format='%(refname:short)' refs/heads)
else
  branches=("$@")
fi

failed=0 kept=0
for b in "${branches[@]}"; do
  # No --all o nome vem do for-each-ref; uma ref como refs/heads/-m viraria opção do git (renomearia a branch atual).
  if ! name_ok "$b"; then
    echo "mantida $b: nome fora do alfabeto"; kept=1; continue
  fi
  if ! tip=$(git rev-parse -q --verify "refs/heads/$b^{commit}"); then
    echo "mantida $b: a branch local não existe"; kept=1; continue
  fi
  if [ "$b" = main ] || [ "$b" = master ] || [ "$b" = "$default" ]; then
    echo "mantida $b: branch principal"; kept=1; continue
  fi
  # Reaplicar a mesma ponta não muda nada, mas passa pela checagem do git de branch em uso em qualquer worktree, que inclui
  # rebase e bisect parados (o `worktree list` mostra esses casos como HEAD destacado, sem a branch).
  if ! LC_ALL=C git branch -f -- "$b" "$tip" > /dev/null 2> "$err"; then
    echo "mantida $b: em uso numa worktree (checkout, rebase ou bisect): $(head -n 1 "$err")"; kept=1; continue
  fi

  # PRs fechados desta branch no próprio repositório (head=<dono>:<branch>); só o mesclado cujo commit é a ponta local vale.
  if ! prs=$(gh api -X GET "repos/$owner/$name/pulls" -f "head=$owner:$b" -f state=closed -f per_page=100 \
    --jq '.[] | select(.merged_at != null) | "\(.head.sha) \(.number)"' 2> "$err"); then
    echo "falha ao consultar o GitHub sobre $b, nada apagado: $(head -n 2 "$err" | tr '\n' ' ')" >&2
    failed=1; continue
  fi
  pr=$(awk -v t="$tip" '$1 == t { print $2; exit }' <<< "$prs")
  if [ -z "$pr" ]; then
    if [ -n "$prs" ]; then
      echo "mantida $b: há commit local que nenhum PR mesclado recebeu"
    else
      echo "mantida $b: nenhum PR mesclado desta branch"
    fi
    kept=1; continue
  fi

  # Apaga só se a ponta ainda é a conferida (update-ref com o valor antigo); a config da branch sai junto.
  if git update-ref -d "refs/heads/$b" "$tip"; then
    git config --remove-section "branch.$b" 2> /dev/null || true
    echo "apagada $b (${tip:0:7}, PR #$pr mesclado)"
  else
    echo "falha ao apagar $b: a branch mudou durante a conferência" >&2
    failed=1
  fi
done

[ "$failed" = 0 ] || exit 3
[ "$all" = 1 ] || [ "$kept" = 0 ] || exit 3
exit 0
