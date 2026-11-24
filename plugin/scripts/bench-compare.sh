#!/usr/bin/env bash
# Mede as categorias quentes no merge-base com a branch base e no working tree atual, compara com o
# comparador neutro e roda o perfil de CPU do diff quando a categoria tiver comando de perfil.
# Uso: bench-compare.sh <categoria>...      (as categorias das linhas "quente:" do classify-diff.sh)
#      BENCH_PROFILE=0 bench-compare.sh ...  pula o perfil de CPU
#
# Cada categoria declara no .claude/risk.conf o comando da sua stack:
#   bench   = <categoria> -> <comando que grava o TSV comum em $BENCH_TSV>
#   profile = <categoria> -> <comando que grava o resumo do perfil em $BENCH_PROFILE_OUT>   (opcional)
# Os comandos rodam com cwd na raiz da versão medida e recebem: BENCH_CATEGORY, BENCH_TSV, BENCH_RAW
# (pasta de rascunho), BENCH_PROFILE_OUT e BENCH_SCRIPTS (a pasta de scripts do plugin, a mesma na base e no diff).
# Código de saída: 0 sem achado, 1 com achado, 2 uso errado, 3 falha de execução.
set -uo pipefail

# os scripts do plugin (os mesmos na base e no diff); antes do cd: $0 pode ser relativo
export BENCH_SCRIPTS=$(cd "$(dirname "$0")" && pwd -P)
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 3
root=$(pwd)
CONF="$root/.claude/risk.conf"

[ "$#" -gt 0 ] || { echo "uso: bench-compare.sh <categoria>..." >&2; exit 2; }
# a categoria entra no s/// do sed em cmd_for: com / ou ; ela fecharia a expressão e injetaria o comando e do GNU sed
for cat in "$@"; do
  [[ $cat =~ ^[A-Za-z0-9._-]+$ ]] || { echo "categoria inválida (só letras, dígitos, . _ -): $cat" >&2; exit 2; }
done
[ -f "$CONF" ] || { echo "$CONF ausente" >&2; exit 3; }

cmd_for() { # cmd_for <chave> <categoria>
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*$2[[:space:]]*->[[:space:]]*//p" "$CONF" | tail -1
}
base=$(sed -n 's/^[[:space:]]*base[[:space:]]*=[[:space:]]*//p' "$CONF" | tail -1 | tr -d '[:space:]'); base=${base:-main}

out=$(mktemp -d "${BENCH_OUT_DIR:-${TMPDIR:-/tmp}}/claude-bench-XXXX")
mkdir -p "$out/base" "$out/diff"

run() { # run <raiz> <lado> <categoria> <comando>
  local dir=$1 side=$2 cat=$3 cmd=$4
  mkdir -p "$out/raw-$side-$cat"
  ( cd "$dir" && BENCH_CATEGORY="$cat" BENCH_TSV="$out/$side/$cat.tsv" BENCH_RAW="$out/raw-$side-$cat" \
      BENCH_PROFILE_OUT="$out/profile-$cat.txt" bash -c "$cmd" ) > "$out/$side-$cat.log" 2>&1
}

cats=()
for cat in "$@"; do
  if [ -z "$(cmd_for bench "$cat")" ]; then
    echo "SEM BENCHMARK | $cat  (caminho quente sem comando 'bench' no risk.conf)"
  else
    cats+=("$cat")
  fi
done
[ "${#cats[@]}" -gt 0 ] || { echo "nenhuma categoria com benchmark; nada a comparar"; exit 0; }

# BENCH_BASE sobrepõe a base do risk.conf (útil depois do commit, quando base = HEAD mediria o mesmo código dos dois lados:
# passe o commit anterior à mudança, por exemplo BENCH_BASE=HEAD~1).
mb=$(git merge-base HEAD "${BENCH_BASE:-$base}" 2> /dev/null) || mb=${BENCH_BASE:-$base}
if [ "$(git rev-parse "$mb" 2> /dev/null)" = "$(git rev-parse HEAD)" ] && [ -z "$(git status --porcelain --untracked-files=no 2> /dev/null)" ]; then
  echo "aviso: a base ($mb) é o próprio HEAD e a árvore está limpa; base e diff medem o mesmo código. Use BENCH_BASE=<commit anterior>."
fi
base_wt="$out/base-src"
# A worktree da base é SEMPRE removida, inclusive em Ctrl+C, timeout ou falha (o build da base pode alterar arquivos rastreados,
# como packages.lock.json, então a remoção usa --force: a worktree é descartável e só nossa).
cleanup_base() { git worktree remove --force "$base_wt" 2> /dev/null; git worktree prune; }
trap cleanup_base EXIT INT TERM
if git worktree add --detach -q "$base_wt" "$mb" 2> "$out/worktree.log"; then
  for cat in "${cats[@]}"; do
    run "$base_wt" base "$cat" "$(cmd_for bench "$cat")" \
      || echo "aviso: base sem benchmark de $cat ou falhou ($out/base-$cat.log)"
  done
  cleanup_base
else
  echo "aviso: não foi possível criar a worktree da base ($out/worktree.log); comparando só o diff"
fi

for cat in "${cats[@]}"; do
  run "$root" diff "$cat" "$(cmd_for bench "$cat")" \
    || { echo "benchmark de $cat falhou no diff: $out/diff-$cat.log" >&2; exit 3; }
done

cat "$out"/base/*.tsv > "$out/base.tsv" 2> /dev/null || : > "$out/base.tsv"
cat "$out"/diff/*.tsv > "$out/diff.tsv" 2> /dev/null
bash "$BENCH_SCRIPTS/compare-bench.sh" "$out/base.tsv" "$out/diff.tsv" "$CONF"
rc=$?

if [ "${BENCH_PROFILE:-1}" != "0" ]; then
  for cat in "${cats[@]}"; do
    pcmd=$(cmd_for profile "$cat"); [ -n "$pcmd" ] || continue
    if run "$root" profile "$cat" "$pcmd" && [ -s "$out/profile-$cat.txt" ]; then
      echo "perfil de CPU de $cat: $out/profile-$cat.txt"
    else
      echo "aviso: perfil de $cat falhou ($out/profile-$cat.log)"
    fi
  done
fi

echo "resultados: $out"
exit $rc
