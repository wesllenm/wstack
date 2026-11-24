#!/usr/bin/env bash
# Mede o tamanho do build de frontend (React, Svelte, Blazor WebAssembly) e grava o TSV comum do comparador.
# Uso: bundle-size.sh <pasta do build>  > "$BENCH_TSV"
#   Vite/React/Svelte: dist (ou build)   SvelteKit adapter-static: build   Blazor WASM: bin/Release/<tfm>/publish/wwwroot
# Emite o total comprimido (gzip -9) por tipo: total:js, total:css, total:wasm, total:dll e total:all.
# Totais por tipo, e não por arquivo, porque nomes com hash e a divisão em chunks mudam entre builds;
# o que importa para o usuário é quanto ele baixa. Tamanho em bytes é determinístico: pode virar achado.
# Exemplo de risk.conf (frontend web), com o frontend em web/:
#   hot    = web/src/* -> Bundle
#   bench  = Bundle -> npm --prefix web ci --prefer-offline --no-audit && npm --prefix web run build && bash "$BENCH_SCRIPTS/bundle-size.sh" web/build > "$BENCH_TSV"
#   budget = total:js -> 250000
set -uo pipefail

dir=${1:-dist}
# caminho relativo com ./ na frente: uma pasta chamada -delete viraria predicado do find e apagaria tudo abaixo do cwd
case $dir in /*) ;; *) dir=./$dir ;; esac
[ -d "$dir" ] || { echo "pasta de build não encontrada: $dir" >&2; exit 3; }

find "$dir" -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.css' -o -name '*.wasm' -o -name '*.dll' \) \
  -not -name '*.map' -print0 |
while IFS= read -r -d '' f; do
  ext=${f##*.}; [ "$ext" = "mjs" ] && ext=js
  printf '%s\t%s\n' "$ext" "$(gzip -9 -c "$f" | wc -c | tr -d ' ')"
done |
awk -F'\t' '
  { total[$1] += $2; all += $2; files++ }
  END {
    if (!files) { print "nenhum artefato js, css, wasm ou dll" > "/dev/stderr"; exit 3 }
    split("js css wasm dll", order, " ")
    for (i = 1; i <= 4; i++) if (order[i] in total)
      printf "bundle\ttotal:%s\ttotal:%s\t-\t-\t%d\t-\t-\t-\n", order[i], order[i], total[order[i]]
    printf "bundle\ttotal:all\ttotal:all\t-\t-\t%d\t-\t-\t-\n", all
  }'
