#!/usr/bin/env bash
# Resume pilhas no formato "folded" (uma linha "f1;f2;...;fn contagem") nas funções que mais consomem tempo.
# É o formato intermediário dos flamegraphs: Rust (cargo flamegraph, perf + inferno-collapse-perf), C/C++, Go
# (pprof -raw convertido) e qualquer profiler que exporte pilhas colapsadas.
# Uso: folded-top.sh <arquivo.folded> [top]  > "$BENCH_PROFILE_OUT"
set -uo pipefail

file=${1:-}; top=${2:-15}
[ -f "$file" ] || { echo "uso: folded-top.sh <arquivo.folded> [top]" >&2; exit 2; }

awk -v TOP="$top" '
  {
    n = $NF + 0; if (n <= 0) next
    stack = $0; sub(/[ \t]+[0-9]+$/, "", stack)
    k = split(stack, f, ";"); if (k == 0) next
    total += n; ex[f[k]] += n
    delete seen
    for (i = 1; i <= k; i++) if (!(f[i] in seen)) { seen[f[i]] = 1; inc[f[i]] += n }
  }
  function show(title, arr,   i, j, best, bestk, used) {
    print "-- top " TOP " " title
    for (i = 1; i <= TOP; i++) {
      best = -1; bestk = ""
      for (j in arr) if (!(j in used) && arr[j] > best) { best = arr[j]; bestk = j }
      if (best < 0) break
      used[bestk] = 1
      printf "   %5.1f%%  %s\n", best / total * 100, bestk
    }
  }
  END {
    if (total <= 0) { print "sem amostras" > "/dev/stderr"; exit 3 }
    show("exclusivo", ex); show("inclusivo", inc)
  }' "$file"
