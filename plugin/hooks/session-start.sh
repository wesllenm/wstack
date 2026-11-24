#!/usr/bin/env bash
# Registra o HEAD do início da sessão para o gate de aprendizado do Stop.
set -uo pipefail
input=$(cat)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

# Sem safe.bareRepository=explicit (que o git só respeita a partir do 2.38), um repositório bare montado pela
# ferramenta de escrita faz um git do allow executar a config dele (decisions.md, 2026-11-18).
git_ge_238() { [[ $(git version) =~ ([0-9]+)\.([0-9]+) ]] && { [ "${BASH_REMATCH[1]}" -gt 2 ] || [ "${BASH_REMATCH[2]}" -ge 38 ]; }; }
if ! git_ge_238 || [ "$(git config --global --get safe.bareRepository 2> /dev/null)" != explicit ]; then
  echo "AVISO de segurança: rode git config --global safe.bareRepository explicit (exige git 2.38 ou mais novo; hoje: $(git version)). Sem isso, um repositório bare forjado faz um git do allow executar comando."
fi

sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$sid" ] || exit 0
head=$(git rev-parse --verify -q HEAD) || exit 0

dir=".claude/.session"
mkdir -p "$dir"
find "$dir" -type f -name '*.base' -mtime +14 -delete 2> /dev/null
[ -f "$dir/$sid.base" ] || echo "$head" > "$dir/$sid.base"

# Telemetria local do workflow (§6.8): só se .claude/telemetry existir; nunca grava conteúdo.
if [ -d .claude/telemetry ]; then
  mkdir -p .claude/telemetry/sessions
  printf '{"schema_version":1,"timestamp":"%s","session_id":"%s","event":"session_started"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" >> ".claude/telemetry/sessions/$sid.jsonl" 2> /dev/null || true
  # O receptor sai sozinho se a porta já estiver em uso; descritores fechados para não prender o hook.
  if [ -f .claude/scripts/otlp-sink.mjs ] && command -v node > /dev/null 2>&1; then
    ( nohup node .claude/scripts/otlp-sink.mjs < /dev/null > /dev/null 2>&1 & ) 2> /dev/null
  fi
fi
exit 0
