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
# Sem session_id não há como achar o HEAD do início da sessão: com o arquivo de calibração (gate adotado), bloqueia em
# vez de pular o gate inteiro. O Claude Code sempre manda o campo; vazio é entrada quebrada.
if [ -z "$sid" ] && [ -f "$LEARN_FILE" ]; then
  echo "Não consegui verificar o aprendizado: a entrada do Stop não traz session_id, então não dá para achar o início da sessão." >&2
  echo "Se for do ambiente, registre o motivo em $BLOCKED e reporte ao desenvolvedor." >&2
  exit 2
fi
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
    # O conteúdo do campo, conferido contra a transcrição da sessão (transcript_path da entrada do Stop; os subagentes
    # ficam em <sessão>/subagents): cada skill de "princípios:" precisa ter sido carregada (principles.mjs --cited), e
    # "pedidos:" não pode ser menor que os pedidos de hook da transcrição (permission-asks.mjs). Menor, e não diferente:
    # a transcrição pode estar atrasada em relação ao turno atual, o que só diminui a contagem.
    # Falha fechada: script que não roda, ou sai com código inesperado, e caminho que não dá para ler bloqueiam com "não
    # consegui verificar". Só a transcrição ausente (entrada sem transcript_path, arquivo que não existe) fica como aviso,
    # porque bloquear ali travaria sessões legítimas; nesse caso vale só a presença do campo, conferida acima.
    unverified() { # unverified <o que> <detalhe>: bloqueia por não conseguir conferir
      emit learning_blocked
      {
        echo "Não consegui verificar o campo $1 da linha de Registro contra a transcrição da sessão: $2"
        echo "Corrija a causa (node, o script do plugin, a transcrição) e tente encerrar de novo; se for do ambiente, registre em .claude/verify-blocked.md."
      } >&2
      exit 2
    }
    # Ler o caminho é parte da conferência: node ausente ou entrada que não é JSON bloqueia (sai diferente de 0); só a
    # entrada válida sem transcript_path, ou o arquivo que não existe, vira aviso.
    # stdout é só o caminho; o stderr vai para outro arquivo (aviso do node na saída viraria caminho falso)
    node_err=$(mktemp)
    transcript=$(printf '%s' "$input" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{let j;try{j=JSON.parse(d)}catch{process.exit(2)}process.stdout.write(String(j?.transcript_path??""))})' 2> "$node_err"); rc=$?
    node_msg=$(tail -1 "$node_err"); rm -f "$node_err"
    [ "$rc" -eq 0 ] || unverified 'princípios: e pedidos:' "não consegui ler transcript_path da entrada do Stop (node saiu com código $rc: node ausente ou entrada que não é JSON${node_msg:+; $node_msg})"
    transcript=${transcript/#\~/$HOME}
    if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
      emit registry_unverified
      echo "Aviso: transcrição da sessão indisponível (${transcript:-sem transcript_path}); os campos princípios: e pedidos: foram conferidos só pela presença." >&2
    else
      scripts="$(cd "$(dirname "$0")/.." && pwd)/scripts"
      subdir="${transcript%.jsonl}/subagents"
      sub=(); [ -d "$subdir" ] && sub=("$subdir")
      line=$(grep 'princípios:' <<< "$added" | tail -1)
      cited=$(sed -e 's/.*princípios:[[:space:]]*//' -e 's/[[:space:]]*(.*//' -e 's/[[:space:]]*—.*//' <<< "$line")
      out=$(node "$scripts/principles.mjs" "$transcript" ${sub[@]+"${sub[@]}"} --cited "$cited" 2>&1); rc=$?
      case "$rc" in
        0) ;;
        3)
          emit learning_blocked
          {
            echo "O campo princípios: da linha de Registro não confere com a transcrição da sessão:"
            grep '^NÃO CARREGADA\|^CAMPO AUSENTE' <<< "$out"
            echo "Cite só skill carregada nesta sessão (ou 'nenhum'), na forma que o principles.mjs devolve; não carregue a skill agora só para citá-la."
          } >&2
          exit 2 ;;
        *) unverified 'princípios:' "principles.mjs saiu com código $rc: $(tail -1 <<< "$out")" ;;
      esac
      registered=$(grep -o 'pedidos:[[:space:]]*[0-9]\+' <<< "$line" | grep -o '[0-9]\+' | tail -1)
      out=$(node "$scripts/permission-asks.mjs" "$transcript" ${sub[@]+"${sub[@]}"} 2>&1); rc=$?
      asks=$(sed -n '1s/^pedidos: \([0-9]\+\).*/\1/p' <<< "$out")
      [ "$rc" -eq 0 ] && [ -n "$asks" ] || unverified 'pedidos:' "permission-asks.mjs saiu com código $rc: $(tail -1 <<< "$out")"
      if [ -z "$registered" ] || [ "$registered" -lt "$asks" ]; then
        emit learning_blocked
        {
          echo "O campo pedidos: da linha de Registro está ausente ou abaixo da transcrição: registrado '${registered:-ausente}', a transcrição tem $asks pedido(s) de hook."
          echo "O campo é procurado na mesma linha de princípios: (a última linha acrescentada com ele): '— pedidos: N — princípios: ...' numa linha só."
          echo "Rode o permission-asks.mjs como manda o fechamento.md da skill lead e corrija a linha."
        } >&2
        exit 2
      fi
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

# Impressão digital do working tree (diff e conteúdo dos não rastreados), calculada pelo próprio git: sha1sum e xargs -r
# não existem no macOS padrão. Vazia é falha no cálculo: roda a verificação e não grava carimbo, em vez de casar com
# um carimbo vazio e pular build e testes.
untracked=$(git ls-files --others --exclude-standard "${CODE[@]}")
fingerprint=$( { git diff HEAD "${CODE[@]}" 2> /dev/null; printf '%s\n' "$untracked"
  [ -z "$untracked" ] || printf '%s\n' "$untracked" | git hash-object --stdin-paths; } | git hash-object --stdin 2> /dev/null )
if [ -n "$fingerprint" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$fingerprint" ]; then
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
[ -z "$fingerprint" ] || echo "$fingerprint" > "$STAMP"
emit verification_passed
exit 0
