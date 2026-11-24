#!/usr/bin/env bash
# Converte resultados do criterion (Rust) para o TSV comum do comparador.
# Uso: criterion-to-tsv.sh [target/criterion]  > "$BENCH_TSV"
# Lê <grupo>/<função>[/<parâmetro>]/new/estimates.json. Parâmetro numérico vira a coluna size (teste de escala),
# então use BenchmarkId::new("funcao", tamanho) para benchmarks com volume. O criterion não mede alocação:
# a coluna bytes sai "-" e alocação em Rust é medida nos testes (contador de alocação, reference/rust.md).
set -uo pipefail

dir=${1:-target/criterion}
[ -d "$dir" ] || { echo "pasta do criterion não encontrada: $dir" >&2; exit 3; }

rows=0
while IFS= read -r -d '' f; do
  rel=${f#"$dir"/}; rel=${rel%/new/estimates.json}
  mean=$(tr -d '\n ' < "$f" | sed -n 's/.*"mean":{"confidence_interval":{[^}]*},"point_estimate":\([0-9.eE+-]*\).*/\1/p')
  [ -n "$mean" ] || continue
  last=${rel##*/}
  if [[ "$last" =~ ^[0-9]+$ ]] && [ "$last" != "$rel" ]; then
    method=${rel%/*}; size=$last
  else
    method=$rel; size="-"
  fi
  printf 'bench\t%s\t%s\t%s\t%s\t-\t-\t-\t-\n' "$rel" "$method" "$size" "$mean"
  rows=$((rows + 1))
done < <(find "$dir" -path '*/new/estimates.json' -not -path '*/report/*' -print0 | sort -z)

[ "$rows" -gt 0 ] || { echo "nenhum estimates.json em $dir" >&2; exit 3; }
