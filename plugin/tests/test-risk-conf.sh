#!/usr/bin/env bash
# Casos do risk-conf.mjs: o .claude/risk.conf lido é o do PROJETO, nunca um da pasta do plugin. Nos hooks o projeto é
# $CLAUDE_PROJECT_DIR; nos scripts que o agente roda pelo Bash (onde essa variável não existe), é a raiz git da pasta
# atual. Sem nenhum dos dois, nada é lido e o motivo fica em confError (falha fechada para quem depende do arquivo).
# Uso: test-risk-conf.sh [<risk-conf.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

mod=${1:-$(dirname "$0")/../hooks/risk-conf.mjs}
[ -f "$mod" ] || { echo "risk-conf.mjs não encontrado: $mod" >&2; exit 2; }
mod=$(cd "$(dirname "$mod")" && pwd -P)/$(basename "$mod")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-rc-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0

# lê pelo módulo, na pasta e com o ambiente dados: imprime "<valores separados por vírgula>|<confError>"
probe() { # probe <pasta> <chave>
  (cd "$1" && node --input-type=module -e "
    const m = await import(process.argv[1]);
    process.stdout.write(m.confValues(process.argv[2]).join(',') + '|' + m.confError());
  " "$mod" "$2")
}
expect() { # expect <descrição> <obtido> <esperado>
  [ "$2" = "$3" ] || { echo "FALHOU [$1]: esperado '$3', obtido '$2'"; fails=$((fails + 1)); }
}

proj="$work/projeto"; mkdir -p "$proj/.claude" "$proj/sub" && git init -q "$proj"
printf 'activity_branch = feat/\n# activity_branch = x/\nactivity_branch = fix/\r\n' > "$proj/.claude/risk.conf"
outro="$work/outro"; mkdir -p "$outro/.claude" && git init -q "$outro"
printf 'activity_branch = outro/\n' > "$outro/.claude/risk.conf"
solto="$work/solto"; mkdir -p "$solto"

# hook: CLAUDE_PROJECT_DIR manda, qualquer que seja a pasta atual
expect hook-projeto "$(CLAUDE_PROJECT_DIR="$proj" probe "$solto" activity_branch)" 'feat/,fix/|'
expect hook-projeto-outra-pasta "$(CLAUDE_PROJECT_DIR="$proj" probe "$outro" activity_branch)" 'feat/,fix/|'
# script pelo Bash: sem a variável, a raiz git da pasta atual (também de uma subpasta)
expect script-raiz "$(env -u CLAUDE_PROJECT_DIR bash -c "$(declare -f probe); mod='$mod'; probe '$proj' activity_branch")" 'feat/,fix/|'
expect script-subpasta "$(env -u CLAUDE_PROJECT_DIR bash -c "$(declare -f probe); mod='$mod'; probe '$proj/sub' activity_branch")" 'feat/,fix/|'
# sem projeto: nada lido, com motivo
got=$(env -u CLAUDE_PROJECT_DIR bash -c "$(declare -f probe); mod='$mod'; probe '$solto' activity_branch")
[ "${got%%|*}" = '' ] && [ -n "${got#*|}" ] || { echo "FALHOU [sem-projeto]: esperado vazio com motivo, obtido '$got'"; fails=$((fails + 1)); }
# projeto sem risk.conf, ou com risk.conf ilegível (uma pasta): nada lido, com motivo
got=$(CLAUDE_PROJECT_DIR="$solto" probe "$proj" activity_branch)
[ "${got%%|*}" = '' ] && [ -n "${got#*|}" ] || { echo "FALHOU [projeto-sem-conf]: esperado vazio com motivo, obtido '$got'"; fails=$((fails + 1)); }
mkdir -p "$solto/.claude/risk.conf"
got=$(CLAUDE_PROJECT_DIR="$solto" probe "$proj" activity_branch)
[ "${got%%|*}" = '' ] && [ -n "${got#*|}" ] || { echo "FALHOU [conf-pasta]: esperado vazio com motivo, obtido '$got'"; fails=$((fails + 1)); }
# um risk.conf ao lado do módulo (a pasta do plugin) nunca é lido
plug="$work/plugin"; mkdir -p "$plug/hooks" && cp "$mod" "$plug/hooks/" && printf 'activity_branch = plugin/\n' > "$plug/risk.conf"
expect conf-do-plugin "$(mod="$plug/hooks/risk-conf.mjs" CLAUDE_PROJECT_DIR="$proj" probe "$solto" activity_branch)" 'feat/,fix/|'

if [ "$fails" -eq 0 ]; then echo "test-risk-conf: todos os casos passaram"; exit 0; fi
echo "test-risk-conf: $fails falha(s)"
exit 1
