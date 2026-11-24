#!/usr/bin/env bash
# Comparador neutro de stack: lê resultados no formato TSV comum (base e diff) e aponta regressões.
# Uso: compare-bench.sh <base.tsv> <diff.tsv> [risk.conf]
#
# Formato TSV (uma linha por medição, separada por tabulação, "-" quando não houver o dado):
#   kind  name  method  size  mean_ns  bytes  gen2_per_kop  exceptions_per_op  lock_per_op
#   kind = bench (benchmark) | bundle (tamanho de artefato, bytes em "bytes")
#   size = tamanho da entrada, numérico, para o teste de escala; method agrupa os tamanhos
#
# Achados (código de saída 1): ALOCAÇÃO, ESCALA, ORÇAMENTO, EXCEÇÃO, TAMANHO, REMOVIDO.
# Informativos: OK, NOVO, TEMPO, ESCALA OK. Código 3 se o diff não tiver resultados.
set -uo pipefail

[ "$#" -ge 2 ] || { echo "uso: compare-bench.sh <base.tsv> <diff.tsv> [risk.conf]" >&2; exit 2; }
base=$1; diff=$2; conf=${3:-}
[ -s "$diff" ] || { echo "sem resultados em $diff" >&2; exit 3; }
[ -f "$base" ] || base=/dev/null
[ -n "$conf" ] && [ -f "$conf" ] || conf=/dev/null

awk -F"\t" \
  -v ALLOC_TOL=0.05 -v ALLOC_MIN=32 -v TIME_TOL=0.10 \
  -v SCALE_FACTOR=2 -v SCALE_MIN=1024 \
  -v BUNDLE_TOL=0.05 -v BUNDLE_MIN=2048 \
  -v CONF="$conf" -v BASE="$base" '
function num(v) { return v != "-" && v != "" }
function pct(a, b) { return a == 0 ? "a partir de zero" : sprintf("%+.1f%%", (b - a) / a * 100) }
function tm(ns) {
  if (!num(ns)) return "tempo n/d"
  if (ns >= 1e6) return sprintf("%.2f ms", ns / 1e6)
  if (ns >= 1e3) return sprintf("%.2f us", ns / 1e3)
  return sprintf("%.1f ns", ns)
}
function by(b) { return num(b) ? sprintf("%.0f B", b) : "alocação n/d" }
# glob simples: só "*" como curinga, sem regex, igual em qualquer awk
function glob(s, g,   n, parts, i, pos, p) {
  n = split(g, parts, "*")
  if (n == 1) return s == g
  if (substr(s, 1, length(parts[1])) != parts[1]) return 0
  pos = length(parts[1]) + 1
  for (i = 2; i < n; i++) {
    if (parts[i] == "") continue
    p = index(substr(s, pos), parts[i]); if (!p) return 0
    pos += p - 1 + length(parts[i])
  }
  if (parts[n] == "") return 1
  return length(s) - length(parts[n]) + 1 >= pos && substr(s, length(s) - length(parts[n]) + 1) == parts[n]
}

BEGIN {
  while ((getline line < CONF) > 0) {
    if (line !~ /^[ \t]*budget[ \t]*=/) continue
    sub(/^[ \t]*budget[ \t]*=[ \t]*/, "", line); sub(/[ \t]+$/, "", line)
    split(line, kv, /[ \t]*->[ \t]*/)
    nb++; bglob[nb] = kv[1]; blimit[nb] = kv[2] + 0
  }
  while ((getline line < BASE) > 0) {
    n = split(line, f, "\t")
    if (n >= 6 && f[1] != "kind") B[f[1] SUBSEP f[2]] = line
  }
}
{
  if (NF < 6 || $1 == "kind") next
  k = $1 SUBSEP $2; D[k] = $0; order[++nd] = k
  if ($1 == "bench" && num($4) && $4 + 0 > 0) {
    m = $3
    if (!(m in smin) || $4 + 0 < smin[m] + 0) { smin[m] = $4; smin_row[m] = $0 }
    if (!(m in smax) || $4 + 0 > smax[m] + 0) { smax[m] = $4; smax_row[m] = $0 }
    if (!(m in seen_m)) { seen_m[m] = 1; morder[++nm] = m }
  }
}
END {
  flagged = 0
  for (i = 1; i <= nd; i++) {
    k = order[i]; split(D[k], c, "\t"); has_old = (k in B); if (has_old) split(B[k], o, "\t")
    label = has_old ? "OK" : "NOVO"; notes = ""

    if (c[1] == "bundle") {
      notes = by(c[6])
      if (has_old && num(o[6]) && num(c[6]) && c[6] - o[6] > BUNDLE_MIN && c[6] > o[6] * (1 + BUNDLE_TOL)) {
        notes = notes "; " by(o[6]) " -> " by(c[6]) " (" pct(o[6], c[6]) ")"; label = "TAMANHO"; flagged++
      }
    } else {
      notes = tm(c[5]) ", " by(c[6])
      if (num(c[7])) notes = notes sprintf(", Gen2 %.3f/1k op", c[7])
      if (has_old && num(o[6]) && num(c[6]) && c[6] - o[6] > ALLOC_MIN && c[6] > o[6] * (1 + ALLOC_TOL)) {
        notes = notes "; alocação " by(o[6]) " -> " by(c[6]) " (" pct(o[6], c[6]) ")"; label = "ALOCAÇÃO"; flagged++
      }
      if (has_old && num(o[5]) && num(c[5]) && o[5] > 0) {
        d = (c[5] - o[5]) / o[5]; if (d < 0) d = -d
        if (d > TIME_TOL) {
          notes = notes "; tempo " tm(o[5]) " -> " tm(c[5]) " (" pct(o[5], c[5]) ", informativo)"
          if (label == "OK") label = "TEMPO"
        }
      }
      if (num(c[8]) && c[8] > 0 && (!has_old || !num(o[8]) || o[8] < c[8])) {
        notes = notes sprintf("; exceções por operação: %g", c[8])
        if (label == "OK" || label == "NOVO" || label == "TEMPO") label = "EXCEÇÃO"
        flagged++
      }
      if (num(c[9]) && c[9] > 0) notes = notes sprintf("; contenção de lock por operação: %g (informativo)", c[9])
    }

    for (j = 1; j <= nb; j++) {
      if (glob(c[2], bglob[j]) && num(c[6]) && c[6] > blimit[j]) {
        notes = notes "; orçamento " blimit[j] " B (" bglob[j] ") excedido: " by(c[6]); label = "ORÇAMENTO"; flagged++
      }
    }
    printf "%s | %s  %s\n", label, c[2], notes
  }

  for (k in B) {
    if (k in D) continue
    split(B[k], o, "\t")
    if (o[1] == "bench") { printf "%s | %s\n", "REMOVIDO", o[2]; flagged++ }
  }

  for (i = 1; i <= nm; i++) {
    m = morder[i]; if (smin[m] == smax[m]) continue
    split(smin_row[m], s, "\t"); split(smax_row[m], l, "\t")
    grow = l[4] / s[4]
    tgrow = (num(s[5]) && s[5] > 0 && num(l[5])) ? l[5] / s[5] : 0
    agrow = (num(s[6]) && s[6] > 0 && num(l[6])) ? l[6] / s[6] : -1
    bad = (tgrow > SCALE_FACTOR * grow) || (agrow > SCALE_FACTOR * grow && l[6] - s[6] > SCALE_MIN)
    line = sprintf("%s  entrada %s->%s (x%.1f), tempo x%.1f", m, s[4], l[4], grow, tgrow)
    if (agrow >= 0) line = line sprintf(", alocação x%.1f", agrow)
    if (bad) { printf "%s | %s  (cresce mais rápido que a entrada)\n", "ESCALA", line; flagged++ }
    else printf "%s | %s\n", "ESCALA OK", line
  }
  exit (flagged > 0 ? 1 : 0)
}' "$diff"
