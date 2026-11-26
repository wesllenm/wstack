#!/usr/bin/env bash
# Gates determinísticos do Stop: aprendizado registrado e build, formato e testes passando.
# Os comandos vêm do .claude/risk.conf do projeto (o hook é do plugin, igual em todo projeto), uma linha cada, vale a
# última:
#   verify_solution = <arquivo que existe quando há o que compilar: solution, package.json, Cargo.toml...>
#   verify_build    = <comando de build>
#   verify_lint     = <comando de verificação de formatação; vazio ou ausente, não roda>
#   verify_test     = <comando de testes rápidos e relevantes>
# Sem verify_solution, verify_build e verify_test, o gate de verificação não roda (como num projeto ainda sem código).
# O gate de aprendizado só vale no projeto que tem o arquivo de calibração (o bootstrap o cria): o plugin pode estar
# instalado para todos os repositórios da máquina, e um repositório que não adotou o workflow não fica preso no Stop.
set -uo pipefail
input=$(cat)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

conf() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" .claude/risk.conf 2> /dev/null | tr -d '\r' | tail -1; }
SOLUTION=$(conf verify_solution)
BUILD_CMD=$(conf verify_build)
LINT_CMD=$(conf verify_lint)
TEST_CMD=$(conf verify_test)

LEARN_FILE="docs/review-calibration.md"
# onde a escada de aprendizado da skill lead grava: núcleo e arquivos de área dos gotchas, complemento da rubrica
LEARN_PATHS=("$LEARN_FILE" "docs/gotchas.md" "docs/gotchas" "docs/review-rubric.md" "docs/patterns.md" "docs/decisions.md" ".claude/agent-memory" ".claude/SESSION.md")

BLOCKED=".claude/verify-blocked.md"
STAMP=".claude/.verify-ok"
CODE=(-- .)
for p in "${LEARN_PATHS[@]}"; do CODE+=(":(exclude)$p"); done

sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Telemetria do workflow: só se .claude/telemetry existir; nunca falha o hook nem grava conteúdo.
emit() {
  [ -d .claude/telemetry ] && [ -n "$sid" ] || return 0
  mkdir -p .claude/telemetry/sessions 2> /dev/null
  printf '{"schema_version":1,"timestamp":"%s","session_id":"%s","event":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$1" >> ".claude/telemetry/sessions/$sid.jsonl" 2> /dev/null || true
}

# Gate 1: aprendizado registrado depois do último commit de código da sessão.
base_file=".claude/.session/$sid.base"
if [ -n "$sid" ] && [ -f "$base_file" ] && [ -f "$LEARN_FILE" ]; then
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
    # A linha de Registro precisa do campo "princípios:", que o principles.mjs produz no fechamento (fechamento.md da
    # skill lead): linha sem ele é Registro escrito sem a conferência. Vale para as linhas acrescentadas desde o início
    # da sessão, commitadas ou não; arquivo de calibração novo, ainda fora do git, conta inteiro.
    if [ -n "$(git ls-files --others --exclude-standard -- "$LEARN_FILE")" ]; then
      added=$(cat "$LEARN_FILE")
    else
      added=$(git diff "$base" -- "$LEARN_FILE" | sed -n 's/^+//p')
    fi
    if ! grep -q 'princípios:' <<< "$added"; then
      emit learning_blocked
      {
        echo "Registro sem o campo princípios: a linha desta tarefa em $LEARN_FILE não traz '— princípios: ...'."
        echo "Rode o principles.mjs como manda o fechamento.md da skill lead e complete a linha; 'princípios: nenhum' é válido quando nenhuma regra mudou decisão."
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

# Sem os comandos no risk.conf, ou enquanto o arquivo do projeto não existir, não há o que verificar.
[ -n "$SOLUTION" ] && [ -n "$BUILD_CMD" ] && [ -n "$TEST_CMD" ] || exit 0
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
