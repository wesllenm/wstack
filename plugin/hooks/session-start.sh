#!/usr/bin/env bash
# Sonda do wstack (SessionStart): prova que o plugin carregou e de onde lê a configuração do projeto.
# A saída vai para o contexto da sessão; só texto fixo, a versão do plugin e o valor da chave `sonda`
# (alfabeto fechado), nunca texto livre do repositório.
set -u
root=${CLAUDE_PLUGIN_ROOT:-}
project=${CLAUDE_PROJECT_DIR:-}
version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9.]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" 2> /dev/null | head -1)
conf="$project/.claude/risk.conf"
value=""
[ -n "$project" ] && [ -f "$conf" ] && [ ! -L "$conf" ] && value=$(sed -n 's/^[[:space:]]*sonda[[:space:]]*=[[:space:]]*//p' "$conf" | head -1 | tr -d '\r')
[[ $value =~ ^[A-Za-z0-9._-]{1,40}$ ]] || value=""
echo "wstack ${version:-?} carregado."
if [ -n "$root" ]; then echo "- plugin: definido (CLAUDE_PLUGIN_ROOT)"; else echo "- plugin: AUSENTE"; fi
if [ -n "$project" ]; then echo "- projeto: definido (CLAUDE_PROJECT_DIR)"; else echo "- projeto: AUSENTE"; fi
if [ -n "$value" ]; then echo "- risk.conf do projeto: lido, sonda = $value"; else echo "- risk.conf do projeto: não lido"; fi
exit 0
