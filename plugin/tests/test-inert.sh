#!/usr/bin/env bash
# Casos do plugin num projeto que não adotou o wstack (sem .claude/risk.conf na árvore nem no HEAD; docs/decisions.md,
# plugin inerte sem risk.conf): os hooks de workflow do SessionStart, do PostToolUse e do registro de sessões não gravam
# nada no projeto nem no diretório comum do git; o session-start continua dizendo a versão. O risk.conf que está no HEAD e
# foi apagado da árvore não torna o projeto inerte. As travas (push-guard e protected-paths) têm casos no test-push-guard.
# Uso: test-inert.sh
# Código: 0 todos passaram, 1 algum falhou.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
plugin=$(cd "$here/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-inert-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

payload='{"session_id":"s-inerte","hook_event_name":"SessionStart"}'
hooks() { # hooks <projeto>: os hooks de workflow como o hooks.json os roda, com a pasta do projeto
  local p=$1
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$p" bash "$plugin/hooks/session-start.sh" > "$work/start.out" 2>&1
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$p" bash "$plugin/scripts/sessions.sh" register > /dev/null 2>&1
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$p" bash "$plugin/scripts/sessions.sh" touch > /dev/null 2>&1
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$p" bash "$plugin/hooks/iteration-guard.sh" > /dev/null 2>&1
}
commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$2"; }

# sem risk.conf: nada gravado, versão dita
cru="$work/cru"; mkdir -p "$cru" && git init -q "$cru" && printf 'a\n' > "$cru/a.txt" && commit "$cru" base
hooks "$cru"
[ -e "$cru/.claude" ] && fail "projeto sem risk.conf ganhou .claude/: $(find "$cru/.claude" | tr '\n' ' ')"
[ -e "$cru/.git/claude-sessions" ] && fail "projeto sem risk.conf ganhou registro de sessão no diretório do git"
grep -q '^wstack .* carregado\.$' "$work/start.out" || fail "session-start sem risk.conf não disse a versão: $(cat "$work/start.out")"
grep -q '/wstack:bootstrap' "$work/start.out" || fail "session-start sem risk.conf não indicou o bootstrap: $(cat "$work/start.out")"
[ -z "$(git -C "$cru" status --porcelain)" ] || fail "projeto sem risk.conf ficou com mudança: $(git -C "$cru" status --porcelain)"
# repositório ainda sem commit também
vazio="$work/vazio"; mkdir -p "$vazio" && git init -q "$vazio"
hooks "$vazio"
[ -e "$vazio/.claude" ] && fail "repositório sem commit ganhou .claude/"

# com risk.conf versionado: os hooks trabalham (base da sessão, contagem de edições, registro)
ativo="$work/ativo"; mkdir -p "$ativo/.claude" && git init -q "$ativo" && printf 'default_branch = main\n' > "$ativo/.claude/risk.conf" && commit "$ativo" base
hooks "$ativo"
[ -f "$ativo/.claude/.session/s-inerte.base" ] || fail "projeto com risk.conf sem a base da sessão"
[ -f "$ativo/.claude/.session/s-inerte.iter" ] || fail "projeto com risk.conf sem a contagem de edições"
grep -q '/wstack:bootstrap' "$work/start.out" && fail "session-start com risk.conf indicou o bootstrap"
ls "$ativo/.git/claude-sessions/"*.session > /dev/null 2>&1 || fail "projeto com risk.conf sem registro de sessão"
# apagado da árvore, com o arquivo no HEAD: continua ativo (apagar não desliga o workflow)
rm -rf "$ativo/.claude" "$ativo/.git/claude-sessions"
hooks "$ativo"
[ -f "$ativo/.claude/.session/s-inerte.base" ] || fail "risk.conf apagado da árvore desligou o session-start"
ls "$ativo/.git/claude-sessions/"*.session > /dev/null 2>&1 || fail "risk.conf apagado da árvore desligou o registro de sessão"
# HEAD num commit anterior ao bootstrap (o arquivo está na branch de origem): continua ativo
velho="$work/velho"; mkdir -p "$velho" && git init -q -b main "$velho" && printf 'a\n' > "$velho/a.txt" && commit "$velho" pre
pre=$(git -C "$velho" rev-parse HEAD)
mkdir -p "$velho/.claude" && printf 'default_branch = main\n' > "$velho/.claude/risk.conf" && commit "$velho" bootstrap
git -C "$velho" checkout -q -b antiga "$pre"
hooks "$velho"
[ -f "$velho/.claude/.session/s-inerte.base" ] || fail "HEAD anterior ao bootstrap desligou o session-start"
ls "$velho/.git/claude-sessions/"*.session > /dev/null 2>&1 || fail "HEAD anterior ao bootstrap desligou o registro de sessão"

if [ "$fails" -eq 0 ]; then echo "test-inert: todos os casos passaram"; exit 0; fi
echo "test-inert: $fails falha(s)"
exit 1
