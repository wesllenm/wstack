#!/usr/bin/env bash
# Abre uma atividade numa worktree própria: branch task/<nome> a partir da base, worktree em
# .claude/worktrees/<nome> do checkout principal, arquivos locais listados em .worktreeinclude copiados
# (appsettings de desenvolvimento, .env) e runtime isolado com worktree-env.sh.
# Uso: nova-atividade.sh <nome> [--base <ref>] [--start]
#   <nome>   letras minúsculas, números e hífen (vira a branch task/<nome>)
#   --start  abre o claude na worktree ao final
# Código: 0 ok, 2 uso errado, 3 falha do git ou do worktree-env.
set -uo pipefail

name=""; base=""; start=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || { echo "--base sem valor" >&2; exit 2; }; base=$2; shift 2 ;;
    --start) start=1; shift ;;
    -*) echo "opção desconhecida: $1" >&2; exit 2 ;;
    *) [ -z "$name" ] || { echo "mais de um nome" >&2; exit 2; }; name=$1; shift ;;
  esac
done
[[ "$name" =~ ^[a-z0-9][a-z0-9-]{1,48}$ ]] || { echo "uso: nova-atividade.sh <nome> [--base <ref>] [--start]  (nome: a-z, 0-9 e hífen)" >&2; exit 2; }
[[ "$base" != -* ]] || { echo "base inválida" >&2; exit 2; }

cd_common=$(git rev-parse --git-common-dir 2> /dev/null) || { echo "fora de um repositório git" >&2; exit 3; }
common=$(cd "$cd_common" && pwd -P) || exit 3
main=$(dirname "$common")
[ -z "$base" ] && base=$(sed -n 's/^[[:space:]]*base[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' "$main/.claude/risk.conf" 2> /dev/null | tail -1)
base=${base:-main}
branch="task/$name"
path="$main/.claude/worktrees/$name"

git -C "$main" rev-parse --verify -q "$base^{commit}" > /dev/null || { echo "base inexistente: $base" >&2; exit 3; }
git -C "$main" rev-parse --verify -q "refs/heads/$branch" > /dev/null && { echo "a branch $branch já existe; escolha outro nome ou retome a atividade na worktree dela" >&2; exit 3; }
[ -e "$path" ] && { echo "já existe $path" >&2; exit 3; }

git -C "$main" worktree add -q -b "$branch" "$path" "$base" || exit 3

# O runtime isolado vem do worktree-env.sh do checkout principal (nunca o da ref escolhida em --base, que pode ser de
# terceiros e nem existir nela); só depois os arquivos locais com segredos de desenvolvimento são copiados.
if [ -f "$main/.claude/scripts/worktree-env.sh" ]; then
  if ! ( cd "$path" && bash "$main/.claude/scripts/worktree-env.sh" alloc ); then
    # sem runtime isolado a atividade colidiria com as outras: desfaz worktree e branch em vez de deixar meia abertura
    git -C "$main" worktree remove --force "$path" && git -C "$main" branch -D -q "$branch"
    echo "atividade não aberta: sem slot de runtime livre; worktree e branch desfeitas" >&2
    exit 3
  fi
fi

# arquivos locais não versionados de que a aplicação precisa para subir (um caminho ou glob por linha)
if [ -f "$main/.worktreeinclude" ]; then
  ( cd "$main" && shopt -s globstar nullglob
    while IFS= read -r pat || [ -n "$pat" ]; do
      pat=${pat%$'\r'}; [ -z "$pat" ] || [[ "$pat" == \#* ]] && continue
      for f in $pat; do
        [ -f "$f" ] || continue
        mkdir -p "$path/$(dirname "$f")" && cp -p "$f" "$path/$f" && echo "copiado: $f"
      done
    done < .worktreeinclude )
fi

echo
echo "atividade $name pronta em $path (branch $branch, base $base)"
if [ "$start" = 1 ]; then cd "$path" && exec claude; fi
echo "para começar: cd \"$path\" && claude"
