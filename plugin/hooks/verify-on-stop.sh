#!/usr/bin/env bash
# Gates determinísticos do Stop: aprendizado registrado e build, formato e testes passando.
set -uo pipefail
input=$(cat)

SOLUTION="<arquivo que existe quando há o que compilar: solution, package.json, Cargo.toml...>"
BUILD_CMD="<comando de build>"
LINT_CMD="<comando de verificação de formatação, ou vazio>"
TEST_CMD="<comando de testes rápidos e relevantes>"

LEARN_FILE="docs/review-calibration.md"
LEARN_PATHS=("$LEARN_FILE" "docs/gotchas.md" "docs/patterns.md" "docs/decisions.md" ".claude/agent-memory" ".claude/SESSION.md")

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

BLOCKED=".claude/verify-blocked.md"
STAMP=".claude/.verify-ok"
CODE=(-- .)
for p in "${LEARN_PATHS[@]}"; do CODE+=(":(exclude)$p"); done

sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Telemetria do workflow (§6.8): só se .claude/telemetry existir; nunca falha o hook nem grava conteúdo.
emit() {
  [ -d .claude/telemetry ] && [ -n "$sid" ] || return 0
  mkdir -p .claude/telemetry/sessions 2> /dev/null
  printf '{"schema_version":1,"timestamp":"%s","session_id":"%s","event":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$1" >> ".claude/telemetry/sessions/$sid.jsonl" 2> /dev/null || true
}

# Gate 1: aprendizado registrado depois do último commit de código da sessão.
base_file=".claude/.session/$sid.base"
if [ -n "$sid" ] && [ -f "$base_file" ]; then
  base=$(cat "$base_file")
  if git cat-file -e "$base^{commit}" 2> /dev/null && [ "$(git rev-list --count "$base"..HEAD "${CODE[@]}")" -gt 0 ]; then
    learned=0
    git diff --quiet HEAD -- "$LEARN_FILE" 2> /dev/null || learned=1
    [ -n "$(git ls-files --others --exclude-standard -- "$LEARN_FILE")" ] && learned=1
    last=$(git log -1 --format=%H "$base"..HEAD -- "$LEARN_FILE")
    if [ -n "$last" ] && [ "$(git rev-list --count "$last"..HEAD "${CODE[@]}")" -eq 0 ]; then
      learned=1
    fi
    if [ "$learned" -eq 0 ]; then
      emit learning_blocked
      {
        echo "Aprendizado não registrado: há commit de código nesta sessão depois do último registro em $LEARN_FILE."
        echo "Faça o passo Aprendizado da skill lead (uma linha em Registro, mesmo que seja 'sem aprendizado') e tente encerrar de novo."
        echo "Se esses commits não são desta sessão (troca de branch, commit manual), regrave $base_file com o HEAD atual."
      } >&2
      exit 2
    fi
  fi
fi

# Exceção de verificação (só depois do gate de aprendizado: ela dispensa build e testes, não o registro).
if [ -f "$BLOCKED" ]; then
  emit verification_exception
  reason=$(head -c 300 "$BLOCKED" | tr '\n"\\' '   ')
  printf '{"systemMessage": "⚠ Turno encerrado sem verificação verde. Motivo registrado: %s"}\n' "$reason"
  exit 0
fi

# Gate 2: build, formato e testes no working tree atual, ignorando mudanças só em arquivos de aprendizado.
[ -z "$(git status --porcelain "${CODE[@]}")" ] && exit 0

# Greenfield: enquanto o arquivo do projeto não existir, não há o que compilar.
[ -f "$SOLUTION" ] || exit 0

fingerprint=$( { git diff HEAD "${CODE[@]}" 2> /dev/null; git ls-files --others --exclude-standard -z "${CODE[@]}" | xargs -0 -r sha1sum; } | sha1sum | cut -d' ' -f1 )
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$fingerprint" ]; then
  exit 0
fi

log=$(mktemp)
if ! { bash -c "$BUILD_CMD" && { [ -z "$LINT_CMD" ] || bash -c "$LINT_CMD"; } && bash -c "$TEST_CMD"; } > "$log" 2>&1; then
  emit verification_failed
  {
    echo "Verificação falhou: a stop condition não foi atingida. Corrija e tente encerrar de novo."
    echo "Se a falha for preexistente ou um bloqueio real (skill lead, Interrupções), registre o motivo em $BLOCKED e reporte ao desenvolvedor."
    echo "--- últimas linhas ---"
    tail -n 60 "$log"
  } >&2
  rm -f "$log"
  exit 2
fi

rm -f "$log"
echo "$fingerprint" > "$STAMP"
emit verification_passed
exit 0
