#!/usr/bin/env bash
# Roda os produtores de sinais de qualidade declarados no .claude/risk.conf e filtra o resultado pelo diff
# com quality-diff.mjs (CRAP por função tocada e duplicação que envolve código do diff).
#   quality = <tipo> -> <comando que grava os relatórios dentro da pasta $QUALITY_OUT>
#   tipos: cobertura | istanbul | eslint | lcov | rca | jscpd     (exemplos por stack na §12.23 do bootstrap)
#   crap_threshold = 30    crap_info = 10                         (opcionais)
# Uso: quality-signals.sh [tipo...]    sem argumento, roda todos os produtores declarados
# Código: 0 sem candidato, 1 com candidato, 2 uso errado, 3 produtor falhou ou não gerou relatório.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 3
root=$(pwd)
CONF="$root/.claude/risk.conf"
[ -f "$CONF" ] || { echo "$CONF ausente" >&2; exit 3; }
key() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONF" | tail -1 | tr -d '[:space:]'; }

base=$(key base); base=${base:-main}
thr=$(key crap_threshold); thr=${thr:-30}
info=$(key crap_info); info=${info:-10}

out=$(mktemp -d "${QUALITY_OUT_DIR:-${TMPDIR:-/tmp}}/claude-quality-XXXX")
# a pasta fica quando algo falha (código 2 ou 3), para o log citado na mensagem continuar existindo
[ "${QUALITY_KEEP:-0}" = "1" ] || trap 'rc=$?; [ "$rc" -ge 2 ] || rm -rf "$out"' EXIT

bad=$(sed -n 's/^[[:space:]]*quality[[:space:]]*=[[:space:]]*\([^ -]*\)[[:space:]]*->.*/\1/p' "$CONF" \
  | grep -vxE 'cobertura|istanbul|eslint|lcov|rca|jscpd' | head -1)
[ -z "$bad" ] || { echo "tipo desconhecido no risk.conf: $bad" >&2; exit 2; }

want=" $* "
args=(--base "$base" --crap-threshold "$thr" --crap-info "$info")
n=0; ran=0
while IFS= read -r line; do
  type=$(printf '%s' "$line" | sed -n 's/^[[:space:]]*quality[[:space:]]*=[[:space:]]*\([a-z]*\)[[:space:]]*->.*/\1/p')
  cmd=$(printf '%s' "$line" | sed -n 's/^[[:space:]]*quality[[:space:]]*=[[:space:]]*[a-z]*[[:space:]]*->[[:space:]]*//p')
  [ -n "$type" ] && [ -n "$cmd" ] || continue
  [ "$#" -eq 0 ] || [[ "$want" == *" $type "* ]] || continue
  n=$((n + 1)); dir="$out/$n-$type"; mkdir -p "$dir"
  # ESLint sai com 1 quando há avisos; o que conta é o relatório gravado, não o código de saída
  ( QUALITY_OUT="$dir" QUALITY_RAW="$out/raw-$n" bash -c "mkdir -p \"\$QUALITY_RAW\"; $cmd" ) > "$out/$n-$type.log" 2>&1
  rc=$?
  case "$type" in
    cobertura) pat='*.xml' ;; lcov) pat='*.info' ;; *) pat='*.json' ;;
  esac
  mapfile -d '' found < <(find "$dir" -type f -name "$pat" -size +0 -print0)
  if [ "${#found[@]}" -eq 0 ]; then
    echo "produtor $type não gerou relatório (código $rc); log: $out/$n-$type.log" >&2
    tail -20 "$out/$n-$type.log" >&2
    exit 3
  fi
  [ "$rc" -eq 0 ] || echo "aviso: produtor $type saiu com código $rc mas gerou relatório; confira $out/$n-$type.log (cobertura de testes que falharam é incompleta)" >&2
  if [ "$type" = rca ]; then args+=(--rca "$dir"); else for f in "${found[@]}"; do args+=("--$type" "$f"); done; fi
  ran=$((ran + 1))
done < "$CONF"

[ "$ran" -gt 0 ] || { echo "nenhum produtor 'quality' no risk.conf${*:+ para: $*}; nada a medir"; exit 0; }
node "$root/.claude/scripts/quality-diff.mjs" "${args[@]}"
