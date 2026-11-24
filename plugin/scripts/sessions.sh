#!/usr/bin/env bash
# Registro das sessões ativas do Claude Code no repositório, no diretório comum do git, que todas as
# worktrees enxergam. Uma sessão por worktree; cada uma declara os arquivos que o plano prevê tocar.
#   sessions.sh register      hook SessionStart: registra a sessão e devolve avisos para o contexto
#   sessions.sh touch         hook Stop: renova o registro (a sessão continua viva)
#   sessions.sh unregister    hook SessionEnd: apaga o registro e as declarações
#   sessions.sh claim <caminho>...   o lead declara arquivos, pastas ou globs que o plano prevê tocar
#   sessions.sh check [<caminho>...] sobreposição com as declarações das outras sessões ativas
#   sessions.sh list          sessões ativas
# risk.conf (opcional): session_stale_hours = 8 (registro sem renovação há mais tempo que isso é considerado morto)
# Código: 0 ok ou sem sobreposição, 1 sobreposição encontrada (check), 2 uso errado, 3 fora de repositório git.
# Os hooks nunca falham a sessão: register, touch e unregister saem com 0 mesmo com erro.
set -uo pipefail

cmd=${1:-}; shift || true
hook=0; case "$cmd" in register|touch|unregister) hook=1 ;; esac
fail() { echo "sessions: $1" >&2; [ "$hook" = 1 ] && exit 0; exit "${2:-3}"; }

input=""; [ "$hook" = 1 ] && input=$(cat)
sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

self_dir=$(cd "$(dirname "$0")" && pwd -P) # antes do cd: $0 pode ser relativo
cd "${CLAUDE_PROJECT_DIR:-.}" 2> /dev/null || fail "diretório do projeto inacessível"
top=$(git rev-parse --show-toplevel 2> /dev/null) || fail "fora de um repositório git"
top=$(cd "$top" && pwd -P)
common=$(cd "$(git rev-parse --git-common-dir)" && pwd -P) || fail "diretório comum do git inacessível"
gitdir=$(cd "$(git rev-parse --git-dir)" && pwd -P)
is_main=0; [ "$gitdir" = "$common" ] && is_main=1
dir="$common/claude-sessions"; mkdir -p "$dir" || fail "não foi possível criar $dir"

stale_h=$(sed -n 's/^[[:space:]]*session_stale_hours[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$top/.claude/risk.conf" 2> /dev/null | tail -1)
stale=$(( ${stale_h:-8} * 3600 ))
now=$(date +%s)
keyof() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
me=$(keyof "$top")
field() { sed -n "s/^$2=//p" "$1" 2> /dev/null | head -1; }
# Valor numérico de um campo: só dígitos; qualquer outra coisa vale 0. A aritmética do bash reavalia subscritos de array
# (a[$(cmd)]), então valor lido de arquivo nunca entra em $(( )) sem passar por aqui.
numfield() { local v; v=$(field "$1" "$2"); [[ "$v" =~ ^[0-9]{1,12}$ ]] && echo "$v" || echo 0; }
branch=$(git symbolic-ref --short -q HEAD || git rev-parse --short HEAD)

gc() {   # remove registro sem renovação ou de worktree que não existe mais
  local f wt seen
  for f in "$dir"/*.session; do
    [ -f "$f" ] || continue
    wt=$(field "$f" worktree); seen=$(numfield "$f" seen)
    if [ ! -d "$wt" ] || [ $(( now - ${seen:-0} )) -gt "$stale" ]; then rm -f "$f" "${f%.session}.claims"; fi
  done
}
write_me() {
  printf 'sid=%s\nworktree=%s\nbranch=%s\nstarted=%s\nseen=%s\n' "$1" "$top" "$branch" "$2" "$now" > "$dir/$me.session.tmp" \
    && mv "$dir/$me.session.tmp" "$dir/$me.session"
}
others() { for f in "$dir"/*.session; do [ -f "$f" ] && [ "$f" != "$dir/$me.session" ] && echo "$f"; done; }
age() { local m=$(( (now - $1) / 60 )); [ "$m" -lt 60 ] && echo "${m} min" || echo "$(( m / 60 )) h"; }
norm() { local p=${1#./}; echo "${p%/}"; }
overlap() {   # mesmo caminho, um dentro do outro, ou um casando com o glob do outro
  local a b; a=$(norm "$1"); b=$(norm "$2")
  [ "$a" = "$b" ] && return 0
  [[ "$a" == "$b"/* || "$b" == "$a"/* ]] && return 0
  # shellcheck disable=SC2053
  [[ "$a" == $b || "$b" == $a ]] && return 0
  return 1
}

gc
case "$cmd" in
  register)
    [ -n "$sid" ] || exit 0
    if [ -f "$dir/$me.session" ]; then
      prev=$(field "$dir/$me.session" sid)
      if [ "$prev" != "$sid" ]; then
        echo "ATENÇÃO: outra sessão do Claude Code está ativa nesta mesma worktree ($top), vista há $(age "$(numfield "$dir/$me.session" seen)")."
        echo "Duas sessões na mesma worktree editam os mesmos arquivos e misturam os gates. Encerre uma delas, ou abra esta atividade numa worktree própria (bash $self_dir/nova-atividade.sh <nome>)."
      fi
    fi
    write_me "$sid" "$now"
    mapfile -t oth < <(others)
    if [ "${#oth[@]}" -gt 0 ]; then
      if [ "$is_main" = 1 ]; then
        echo "Esta sessão está no checkout principal e há ${#oth[@]} atividade(s) em paralelo em outras worktrees. Para uma atividade nova, independente dessas, use bash $self_dir/nova-atividade.sh <nome> em vez de trabalhar aqui."
      fi
      echo "Atividades em paralelo neste repositório (declare os arquivos do plano com sessions.sh claim e confira com sessions.sh check):"
      for f in "${oth[@]}"; do
        n=0; [ -f "${f%.session}.claims" ] && n=$(grep -c . "${f%.session}.claims")
        echo "- $(field "$f" branch) em $(field "$f" worktree), ativa há $(age "$(numfield "$f" started)"), $n caminho(s) declarado(s)"
      done
    fi
    [ "$is_main" = 0 ] && [ -f "$top/.claude/worktree.env" ] && echo "Atividade em worktree própria: branch $branch, runtime em .claude/worktree.env ($(grep -E '^PORT_BASE=' "$top/.claude/worktree.env"))."
    exit 0 ;;
  touch)
    [ -n "$sid" ] || exit 0
    if [ -f "$dir/$me.session" ] && [ "$(field "$dir/$me.session" sid)" = "$sid" ]; then write_me "$sid" "$(numfield "$dir/$me.session" started)"
    else write_me "$sid" "$now"; fi
    exit 0 ;;
  unregister)
    if [ -f "$dir/$me.session" ] && { [ -z "$sid" ] || [ "$(field "$dir/$me.session" sid)" = "$sid" ]; }; then rm -f "$dir/$me.session" "$dir/$me.claims"; fi
    exit 0 ;;
  claim)
    [ $# -gt 0 ] || fail "uso: sessions.sh claim <caminho>..." 2
    for p in "$@"; do norm "$p"; done | sort -u > "$dir/$me.claims"
    [ -f "$dir/$me.session" ] || write_me "manual" "$now"
    echo "$(grep -c . "$dir/$me.claims") caminho(s) declarado(s) para $branch" ;;
  check)
    if [ $# -gt 0 ]; then mine=$(for p in "$@"; do norm "$p"; done)
    else [ -f "$dir/$me.claims" ] || fail "nada declarado; use sessions.sh claim ou passe os caminhos" 2; mine=$(cat "$dir/$me.claims"); fi
    found=0
    while IFS= read -r f; do
      c="${f%.session}.claims"; [ -f "$c" ] || continue
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        while IFS= read -r b; do
          [ -n "$b" ] || continue
          if overlap "$a" "$b"; then echo "SOBREPOSIÇÃO: $a ↔ $b (atividade $(field "$f" branch) em $(field "$f" worktree))"; found=1; fi
        done < "$c"
      done <<< "$mine"
    done < <(others)
    [ "$found" = 0 ] && echo "sem sobreposição com as outras atividades ativas"
    exit "$found" ;;
  list)
    any=0
    for f in "$dir"/*.session; do
      [ -f "$f" ] || continue; any=1
      n=0; [ -f "${f%.session}.claims" ] && n=$(grep -c . "${f%.session}.claims")
      mark=""; [ "$f" = "$dir/$me.session" ] && mark=" (esta)"
      echo "$(field "$f" branch)$mark  $(field "$f" worktree)  ativa há $(age "$(numfield "$f" started)"), última atividade há $(age "$(numfield "$f" seen)"), $n caminho(s)"
    done
    [ "$any" = 0 ] && echo "nenhuma sessão ativa" ;;
  *) fail "uso: sessions.sh register | touch | unregister | claim <caminho>... | check [<caminho>...] | list" 2 ;;
esac
