#!/usr/bin/env bash
# Diz a versão do plugin em uso (a primeira linha da sessão; é como se confere a atualização automática do plugin) e
# registra o HEAD do início da sessão para o gate de aprendizado do Stop.
set -uo pipefail
input=$(cat)
plugin=$(cd "$(dirname "$0")/.." && pwd -P)

version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9A-Za-z.+-]*\)".*/\1/p' "$plugin/.claude-plugin/plugin.json" 2> /dev/null | head -1)
echo "wstack ${version:-?} carregado."

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

# Sem safe.bareRepository=explicit (que o git só respeita a partir do 2.38), um repositório bare montado pela
# ferramenta de escrita faz um git do allow executar a config dele (test-push-guard.sh tem o caso).
git_ge_238() { [[ $(git version) =~ ([0-9]+)\.([0-9]+) ]] && { [ "${BASH_REMATCH[1]}" -gt 2 ] || [ "${BASH_REMATCH[2]}" -ge 38 ]; }; }
if ! git_ge_238 || [ "$(git config --global --get safe.bareRepository 2> /dev/null)" != explicit ]; then
  echo "AVISO de segurança: rode git config --global safe.bareRepository explicit (exige git 2.38 ou mais novo; hoje: $(git version)). Sem isso, um repositório bare forjado faz um git do allow executar comando."
fi

# Projeto sem o wstack (risk-conf.mjs --absent sai 10; a regra mora lá): daqui para baixo é workflow, não trava; nada é gravado.
if [ ! -e .claude/risk.conf ]; then
  node "$plugin/hooks/risk-conf.mjs" --absent
  [ $? = 10 ] && { echo "Projeto sem o wstack: só as travas de segurança estão ativas. Para adotar o workflow, /wstack:bootstrap."; exit 0; }
fi

# Exceção de verificação esquecida: ela só vale para a sessão que a gravou (linha "sessão: <id>"), mas o arquivo parado
# confunde e esconde o motivo; avisar para ler e apagar ao retomar.
if [ -f .claude/verify-blocked.md ]; then
  echo "AVISO: .claude/verify-blocked.md existe (exceção de verificação de uma sessão anterior: vale só para a sessão que a gravou). Ler o motivo e pedir ao desenvolvedor para apagar o arquivo."
fi
# Marcador de verificação pendente de outra sessão: segura o push de todas, e só a sessão dele (verde) ou o desenvolvedor o tira
for f in .claude/.session/unverified*; do
  [ -f "$f" ] && echo "AVISO: verificação pendente em $f ($(head -1 "$f" | cut -c1-200)): o push de branch fica recusado até a sessão dele encerrar com build e testes verdes, ou o desenvolvedor apagar o arquivo."
done

sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[[ $sid =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
head=$(git rev-parse --verify -q HEAD) || exit 0

dir=".claude/.session"
mkdir -p "$dir"
find "$dir" -type f -name '*.base' -mtime +14 -delete 2> /dev/null
[ -f "$dir/$sid.base" ] || echo "$head" > "$dir/$sid.base"

# Telemetria local do workflow: só se .claude/telemetry existir no projeto; nunca grava conteúdo.
if [ -d .claude/telemetry ]; then
  mkdir -p .claude/telemetry/sessions
  printf '{"schema_version":1,"timestamp":"%s","session_id":"%s","event":"session_started"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" >> ".claude/telemetry/sessions/$sid.jsonl" 2> /dev/null || true
  # O receptor (do plugin; grava na pasta do projeto) sai sozinho se a porta já estiver em uso; descritores fechados
  # para não prender o hook.
  if [ -f "$plugin/scripts/otlp-sink.mjs" ] && command -v node > /dev/null 2>&1; then
    ( nohup node "$plugin/scripts/otlp-sink.mjs" < /dev/null > /dev/null 2>&1 & ) 2> /dev/null
  fi
fi
exit 0
