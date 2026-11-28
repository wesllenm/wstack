#!/usr/bin/env bash
# Checkpoint da sessão na nuvem (skill lead, Execução na nuvem): grava o estado atual da árvore de trabalho (arquivos
# novos incluídos, .gitignore respeitado) num commit avulso, fora de qualquer branch, e o envia para uma ref NOVA
# refs/heads/wip/<atividade>-<n>. Não toca a branch, o índice nem a árvore; nunca sobrescreve uma ref existente.
# Não é commit de unidade: não passa pela skill commit; a retomada sem commit está na skill lead.
# A ref wip/ não passa pelo gitleaks do CI (que só roda em PR): arquivo novo ou alterado com nome de credencial ou com
# conteúdo que parece segredo recusa o checkpoint. É uma rede grossa, não o gitleaks.
# Recusa também, sem publicar, se a árvore do checkpoint altera caminho protegido (hooks, scripts, settings, workflows, ci...)
# em relação ao merge-base com origin/<branch padrão>, ou se não der para conferir (sem essa base): protected-paths.mjs.
# Com --aprovado, a mudança em caminho protegido não recusa (o segredo continua recusando). A aprovação é do
# desenvolvedor no pedido de permissão do Claude Code: o script-allow do plugin não aprova a chamada com --aprovado,
# e ela cai no pedido normal. Num projeto cujo CI roda em push de qualquer branch, uma ref wip/ com workflow dispara o
# Actions: o workflow do projeto deve ter branches-ignore: ['wip/**'].
# Uso: checkpoint.sh [--aprovado] <atividade> <n> <motivo>     ex.: checkpoint.sh permissoes 1 "esperando aprovação"
# Código: 0 enviado (imprime a ref e o sha); 2 uso errado; 3 falha (git, ref já existe, caminho protegido, push recusado).
set -uo pipefail

aprovado=0
[ "${1:-}" = --aprovado ] && { aprovado=1; shift; }
[ $# -eq 3 ] || { echo "uso: checkpoint.sh [--aprovado] <atividade> <n> <motivo>" >&2; exit 2; }
atividade=$1 n=$2 motivo=$3
[[ $atividade =~ ^[a-z0-9][a-z0-9-]{0,48}$ ]] || { echo "atividade fora do alfabeto (a-z, 0-9, hífen)" >&2; exit 2; }
[[ $n =~ ^[0-9]{1,4}$ ]] || { echo "n precisa ser um número" >&2; exit 2; }
[[ $motivo =~ ^[^[:cntrl:]]{1,200}$ ]] || { echo "motivo vazio, longo demais ou com caractere de controle" >&2; exit 2; }

git rev-parse --verify -q HEAD > /dev/null || { echo "sem HEAD: nada para servir de base" >&2; exit 3; }
ref="refs/heads/wip/$atividade-$n"
if git ls-remote --exit-code origin "$ref" > /dev/null 2>&1; then
  echo "a ref $ref já existe no remoto: use outro <n> (checkpoint nunca sobrescreve)" >&2
  exit 3
fi

idx=$(mktemp) || exit 3
trap 'rm -f "$idx"' EXIT
cp "$(git rev-parse --git-path index)" "$idx" || exit 3
GIT_INDEX_FILE="$idx" git add -A || exit 3
tree=$(GIT_INDEX_FILE="$idx" git write-tree) || exit 3

ident=()
[ -n "$(git config user.email 2> /dev/null)" ] || ident=(-c user.name=checkpoint -c user.email=checkpoint@localhost)
sha=$(git "${ident[@]}" commit-tree "$tree" -p HEAD -m "checkpoint: $motivo") || exit 3

# Caminho protegido (hooks, scripts, settings, workflows, ci...) alterado desde o merge-base com origin/<branch padrão>: a ref wip/ não
# é publicada (um workflow alterado numa ref wip/ dispararia o GitHub Actions com segredos). Falha da conferência vale o mesmo.
if ! command -v node > /dev/null; then
  echo "checkpoint recusado: node ausente, não dá para conferir caminho protegido (registrar 'checkpoint não gravado', skill lead)" >&2
  exit 3
fi
protegidos=$(node "$(dirname "${BASH_SOURCE[0]}")/../hooks/protected-paths.mjs" "$sha"); rc=$?
case $rc in
  0) [ "$protegidos" = OK ] || { echo "checkpoint recusado: a conferência de caminho protegido não respondeu OK (registrar 'checkpoint não gravado', skill lead)" >&2; exit 3; } ;;
  1) if [ "$aprovado" = 1 ]; then echo "checkpoint com mudança protegida, publicado com aprovação: $(printf '%s' "$protegidos" | tr '\n' ' ')" >&2
     else echo "checkpoint com mudança protegida: $(printf '%s' "$protegidos" | tr '\n' ' '); publicar só com aprovação do desenvolvedor, rodando de novo com --aprovado (o Claude Code pede a aprovação) ou registrando 'checkpoint não gravado' (skill lead)" >&2; exit 3; fi ;;
  *) echo "checkpoint recusado: não foi possível conferir caminho protegido ($protegidos); registrar 'checkpoint não gravado', skill lead" >&2; exit 3 ;;
esac

suspeitos=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [[ ${f##*/} =~ ^(\.env.*|.*\.(pem|key|pfx|p12|jks|keystore|kdbx)|id_(rsa|dsa|ecdsa|ed25519).*|\.npmrc|\.pypirc|\.netrc|credentials.*|.*secret.*|kubeconfig.*|.*\.local\.json)$ ]]; then
    suspeitos+=("$f (nome)")
  elif [ -f "$f" ] && grep -Eq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}' "$f" 2> /dev/null; then
    suspeitos+=("$f (conteúdo)")
  fi
done < <(GIT_INDEX_FILE="$idx" git diff --cached --name-only --diff-filter=AM HEAD)
if [ "${#suspeitos[@]}" -gt 0 ]; then
  echo "checkpoint recusado: arquivo que pode conter segredo (registrar 'checkpoint não gravado', skill lead):" >&2
  printf -- '- %s\n' "${suspeitos[@]}" >&2
  exit 3
fi

git push origin "$sha:$ref" || { echo "push do checkpoint recusado; registrar 'checkpoint não gravado' (skill lead)" >&2; exit 3; }
echo "$ref $sha"
