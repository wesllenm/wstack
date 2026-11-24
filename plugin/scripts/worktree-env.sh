#!/usr/bin/env bash
# Isola o runtime de cada worktree (§14.10): reserva um slot no diretório comum do git, visível a todas as worktrees,
# e grava .claude/worktree.env na worktree com a faixa de portas, o sufixo do banco e o nome do projeto do Compose.
# O checkout principal é sempre o slot 0 e não precisa de reserva; worktrees usam os slots 1..worktree_slots.
#   worktree-env.sh alloc     reserva (ou reaproveita) o slot desta worktree e grava .claude/worktree.env
#   worktree-env.sh release   devolve o slot desta worktree e apaga .claude/worktree.env
#   worktree-env.sh list      mostra os slots em uso
# risk.conf (opcional): worktree_port_base = 20000, worktree_port_step = 10, worktree_slots = 8
# Código: 0 ok, 2 uso errado, 3 fora de repositório git ou sem slot livre.
set -uo pipefail

top=$(git rev-parse --show-toplevel 2> /dev/null) || { echo "worktree-env: fora de um repositório git" >&2; exit 3; }
common=$(cd "$(git rev-parse --git-common-dir)" && pwd -P) || exit 3
gitdir=$(cd "$(git rev-parse --git-dir)" && pwd -P) || exit 3
top=$(cd "$top" && pwd -P)
slots="$common/claude-slots"
mkdir -p "$slots"

conf="$top/.claude/risk.conf"
key() { [ -f "$conf" ] && sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$conf" | tail -1; }
base=$(key worktree_port_base); base=${base:-20000}
step=$(key worktree_port_step); step=${step:-10}
max=$(key worktree_slots); max=${max:-8}

repo=$(basename "$(dirname "$common")" | tr -c 'a-zA-Z0-9\n' '-' | tr 'A-Z' 'a-z')
is_main=0; [ "$gitdir" = "$common" ] && is_main=1

live_worktrees() { git worktree list --porcelain | sed -n 's/^worktree //p' | while read -r p; do (cd "$p" 2> /dev/null && pwd -P); done; }

reclaim() {   # libera slots cuja worktree não existe mais
  local live f p; live=$(live_worktrees)
  for f in "$slots"/[0-9]*; do
    [ -f "$f" ] || continue
    p=$(cat "$f")
    printf '%s\n' "$live" | grep -qxF "$p" || rm -f "$f"
  done
}

write_env() {
  local slot=$1 name; name=$(basename "$top")
  mkdir -p "$top/.claude"
  cat > "$top/.claude/worktree.env" <<EOF
# gerado por .claude/scripts/worktree-env.sh; não versionar
WORKTREE_SLOT=$slot
WORKTREE_NAME=$name
PORT_BASE=$((base + slot * step))
PORT_LAST=$((base + slot * step + step - 1))
DB_SUFFIX=_wt$slot
COMPOSE_PROJECT_NAME=$repo-wt$slot
EOF
  cat "$top/.claude/worktree.env"
}

case "${1:-}" in
  alloc)
    if [ "$is_main" = 1 ]; then write_env 0; exit 0; fi
    for f in "$slots"/[0-9]*; do
      [[ "$(basename "$f")" =~ ^[0-9]{1,3}$ ]] || continue
      [ -f "$f" ] && [ "$(cat "$f")" = "$top" ] && { write_env "$(basename "$f")"; exit 0; }
    done
    reclaim
    for ((n = 1; n <= max; n++)); do
      # criação atômica: duas worktrees disputando o mesmo número, só uma ganha
      if ( set -o noclobber; printf '%s\n' "$top" > "$slots/$n" ) 2> /dev/null; then write_env "$n"; exit 0; fi
    done
    echo "worktree-env: os $max slots estão em uso; remova worktrees encerradas (git worktree remove) ou aumente worktree_slots" >&2
    exit 3 ;;
  release)
    for f in "$slots"/[0-9]*; do [ -f "$f" ] && [ "$(cat "$f")" = "$top" ] && rm -f "$f"; done
    rm -f "$top/.claude/worktree.env"
    echo "slot liberado: $top" ;;
  list)
    reclaim
    echo "0  $(dirname "$common")  (checkout principal, portas $base-$((base + step - 1)))"
    for f in "$slots"/[0-9]*; do
      [ -f "$f" ] || continue
      n=$(basename "$f"); [[ "$n" =~ ^[0-9]{1,3}$ ]] || continue
      echo "$n  $(cat "$f")  (portas $((base + n * step))-$((base + n * step + step - 1)))"
    done ;;
  *) echo "uso: worktree-env.sh alloc | release | list" >&2; exit 2 ;;
esac
