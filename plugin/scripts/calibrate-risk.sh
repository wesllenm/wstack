#!/usr/bin/env bash
# Calibra o classificador no histórico real: classifica os últimos N commits (sem merges) com o risk.conf atual
# e mostra a distribuição por nível, os motivos de CRITICA e exemplos. Somente leitura.
# Uso: calibrate-risk.sh [N]   (padrão 100)
# Sinal de alerta: CRITICA acima de ~15% dos commits indica globs ou sinais largos demais; o caminho pesado
# na sessão vira regra e o incentivo a contornar volta. Código 1 quando passa do limite.
set -uo pipefail

n=${1:-100}
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 1
classify=".claude/scripts/classify-diff.sh"
[ -f "$classify" ] || { echo "$classify não encontrado" >&2; exit 2; }

declare -A count reason
total=0; examples=()
while IFS= read -r sha; do
  out=$(bash "$classify" --commit "$sha")
  level=$(head -1 <<< "$out")
  count[$level]=$(( ${count[$level]:-0} + 1 )); total=$((total + 1))
  if [ "$level" = "CRITICA" ]; then
    # só os motivos que impõem CRITICA; os de nível menor não explicam a classificação
    while IFS= read -r line; do
      key=$(sed -e 's/^motivo: CRITICA — //' -e 's/:.*//' -e 's/[0-9]\+/N/g' <<< "$line")
      reason[$key]=$(( ${reason[$key]:-0} + 1 ))
    done < <(grep '^motivo: CRITICA — ' <<< "$out")
    [ "${#examples[@]}" -lt 10 ] && examples+=("$(git log -1 --format='%h %s' "$sha" | cut -c1-60) | $(grep -m1 '^motivo: CRITICA — ' <<< "$out" | sed 's/^motivo: CRITICA — //' | cut -c1-80)")
  fi
done < <(git rev-list --no-merges -n "$n" HEAD)

[ "$total" -gt 0 ] || { echo "nenhum commit para classificar"; exit 0; }
echo "Commits classificados: $total (risk.conf atual, sem merges)"
for l in TRIVIAL SIMPLES COMPLEXA CRITICA; do
  c=${count[$l]:-0}
  printf '  %-9s %4d  %5.1f%%\n' "$l" "$c" "$(awk -v c="$c" -v t="$total" 'BEGIN {print c / t * 100}')"
done

if [ "${#reason[@]}" -gt 0 ]; then
  echo "Motivos que impuseram CRITICA (contados por arquivo; um commit pode ter vários):"
  for k in "${!reason[@]}"; do printf '  %4d  %s\n' "${reason[$k]}" "$k"; done | sort -rn
  echo "Exemplos de CRITICA:"
  printf '  %s\n' "${examples[@]}"
fi

crit=${count[CRITICA]:-0}
if [ $((crit * 100)) -gt $((total * 15)) ]; then
  echo "ALERTA: CRITICA em mais de 15% dos commits. Revisar os motivos acima: estreitar globs 'critical' ou desligar sinais que não se aplicam ao projeto."
  exit 1
fi
