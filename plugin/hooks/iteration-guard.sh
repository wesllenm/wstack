#!/usr/bin/env bash
# PostToolUse em Edit/Write/MultiEdit/NotebookEdit: conta edições desde o último commit da sessão. A cada
# iteration_limit edições sem commit, devolve "block" com a ordem do §16, que o Claude Code entrega ao modelo
# como instrução. Não desfaz nada nem impede a próxima edição: instrui o modelo a parar e decidir, sem garantir
# que ele obedeça. Edições feitas por Bash, scripts ou geradores não passam aqui. Commit zera a contagem.
set -uo pipefail
input=$(cat)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$sid" ] || exit 0

limit=$(sed -n 's/^[[:space:]]*iteration_limit[[:space:]]*=[[:space:]]*\([0-9]\+\).*/\1/p' .claude/risk.conf 2> /dev/null | tail -1)
limit=${limit:-40}
[ "$limit" -gt 0 ] || exit 0

head=$(git rev-parse --verify -q HEAD || echo none)
state=".claude/.session/$sid.iter"
mkdir -p .claude/.session
last_head=""; count=0
[ -f "$state" ] && read -r last_head count < "$state"
[[ "$count" =~ ^[0-9]+$ ]] || count=0
[ "$last_head" = "$head" ] || count=0
count=$((count + 1))
echo "$head $count" > "$state"

[ $((count % limit)) -eq 0 ] || exit 0

if [ -d .claude/telemetry ]; then
  mkdir -p .claude/telemetry/sessions
  printf '{"schema_version":1,"timestamp":"%s","session_id":"%s","event":"iteration_limit","edits":%d}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$count" >> ".claude/telemetry/sessions/$sid.jsonl" 2> /dev/null || true
fi

reason="Limite de iteração: $count edições desde o último commit, sem uma unidade verde commitada. Pare antes da próxima edição e aplique o §16 (três tentativas sem progresso): (1) se existe uma unidade verde, commite-a; (2) senão, ataque a premissa: escreva em .claude/SESSION.md, numa frase, a suposição que as tentativas que falharam têm em comum, e a evidência que a confirma ou não; se ela não foi verificada, verifique-a (teste, log, leitura do código) antes de qualquer nova correção; se foi refutada, descarte a linha de ataque inteira, não só a última tentativa; (3) se a premissa se sustenta e não há saída, registre o que foi tentado e reporte ao desenvolvedor com a decisão necessária. Outra variação da mesma correção, sem esse passo, é desvio do workflow."
printf '{"decision":"block","reason":"%s"}\n' "$reason"
exit 0
