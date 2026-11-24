#!/usr/bin/env bash
# Casos do redirect-guard (hook PreToolUse em Bash que pede aprovação para redirecionamento para arquivo), sem rede e
# sem modelo. Para cada forma livre, prova diferencial: o comando roda no bash (com extglob, globstar e nullglob) numa
# pasta de teste, e nenhum arquivo pode nascer ou mudar fora do alvo declarado na pasta temporária. A prova com o
# Claude Code real está em prove-redirect-guard.sh (custa modelo; roda à mão).
# Uso: test-redirect-guard.sh [<redirect-guard.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

top=$(git rev-parse --show-toplevel 2> /dev/null)
hook=${1:-$top/.claude/hooks/redirect-guard.sh}
[ -f "$hook" ] || { echo "redirect-guard.sh não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
hook=$(cd "$(dirname "$hook")" && pwd -P)/$(basename "$hook")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-rg-XXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
fails=0
tmp=$(cd "${TMPDIR:-/tmp}" && pwd -P)
mkdir -p "$work/projeto" "$work/cwd" "$work/bin"
printf '#!/usr/bin/env bash\necho saida\necho erro >&2\n' > "$work/bin/git" && chmod +x "$work/bin/git"
touch "$work/cwd/.gitignore" "$work/cwd/HEADx"

# REMOTE=<valor> define CLAUDE_CODE_REMOTE; vazio deixa a variável ausente, qualquer que seja a do ambiente de quem testa
# (na VM da nuvem ela vale true e mudaria todos os vereditos do modo local)
verdict() {
  local -a remote=(-u CLAUDE_CODE_REMOTE)
  [ -n "${REMOTE:-}" ] && remote=("CLAUDE_CODE_REMOTE=$REMOTE")
  jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' |
    env "${remote[@]}" CLAUDE_PROJECT_DIR="$work/projeto" bash "$hook" 2> /dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null
}
snapshot() { (cd "$work/cwd" && find . -type f -exec sha256sum {} + | sort); }

expect() { # expect <livre|ask> <comando> [<alvo na pasta temporária que o comando pode gravar>]
  local got; got=$(verdict "$2"); got=${got:-livre}
  if [ "$got" != "$1" ]; then echo "FALHOU: esperado $1, obtido $got: $2"; fails=$((fails + 1)); return; fi
  [ "$1" = livre ] || return 0
  # prova diferencial: nada nasce nem muda na pasta de trabalho; só o alvo declarado pode nascer na temporária
  local before after; before=$(snapshot)
  (cd "$work/cwd" && PATH="$work/bin:$PATH" timeout 10 bash -O extglob -O globstar -O nullglob -c "$2" > /dev/null 2>&1)
  after=$(snapshot)
  [ "$before" = "$after" ] || { echo "FALHOU: forma livre gravou na pasta de trabalho: $2"; fails=$((fails + 1)); }
  if [ $# -eq 3 ]; then [ -f "$3" ] || { echo "FALHOU: o alvo declarado não foi gravado (a prova não provaria nada): $2"; fails=$((fails + 1)); }; rm -f "$3"; fi
}

t1=$tmp/claude-rg-alvo-$$.log
# livres: sem >, /dev/null, 2>&1, pasta temporária literal, o commit da skill
expect livre 'git status --short'
expect livre 'git log -1 2>/dev/null'
expect livre 'git log -1 2>&1 | tail -3'
expect livre 'git log -1 >/dev/null 2>&1; git status 2>/dev/null'
expect livre 'git log -1 &>/dev/null'
expect livre 'git log -1 >&2'
expect livre 'git log -1 >/dev/stderr'
expect livre "git log -1 > $t1 2>&1" "$t1"
expect livre "git log -1 >> $t1" "$t1"
expect livre "git log -1 2> $t1" "$t1"
expect livre "git commit -F - <<'EOF'
fix(x): corpo com -> e > e <noreply@anthropic.com>
EOF"
expect livre 'git log -1 < /dev/null'
# os comandos exatos que a skill lead manda rodar sem pedido
expect livre 'gh pr list --state merged --search "merged:2026-11-01..*" --json number,title,mergedAt'
expect livre 'bash .claude/scripts/checkpoint.sh x 1 "esperando aprovação do plano"'
expect ask 'gh pr list --state merged --search "merged:>=2026-11-01"'

# pedem aprovação: alvo no projeto ou fora da temporária, e toda forma fora do formato fechado
expect ask 'git status --short > .gitignore'
expect ask 'git status --short >> .gitignore'
expect ask 'git status --short >| .claude/settings.json'
expect ask 'git status --short > docs/x.txt'
expect ask "git status --short > $work/projeto/x.txt"
expect ask "git status --short > $tmp/../root/x"
expect ask 'git status --short > /etc/x'
expect ask 'git status --short > ~/x'
expect ask 'git status --short > $HOME/x'
expect ask 'git status --short > "/tmp/a b"'
expect ask 'git status --short > /tmp/a\ b'
expect ask 'git status --short >/tmp/code-sig[n]'
expect ask 'git status --short > /tmp/x*'
expect ask 'git status --short > /tmp/{a,b}'
expect ask 'git status --short >&x'
expect ask 'git status --short 10>x'
expect ask 'git status --short 3>x'
expect ask 'git status --short 1<>x'
expect ask 'git status --short 2>&1>x'
expect ask 'git status --short >>>x'
expect ask 'git status --short > >(cat)'
expect ask 'cat <<EOF > x
a
EOF'
expect ask "$(printf 'git status --short > /tmp/x\\\n/../../root/x')"
expect ask "git status --short > /tmp/a$(printf '\302\240')b"
expect ask "$(printf 'git status --short > /tmp/x\r')"
expect ask 'cd /tmp && git status > x'
expect ask "git log --format='%h -> %s'"
expect ask "git commit -F - <<'EOF'
x
EOF
git status > .gitignore"
expect ask 'X=1>y'

# a pasta temporária é conferida no caminho real: symlink e hardlink para o projeto pedem aprovação
echo hook > "$work/projeto/hook.sh"
ln -s "$work/projeto/hook.sh" "$tmp/claude-rg-link-$$"
ln -s "$work/projeto" "$tmp/claude-rg-dir-$$"
ln "$work/projeto/hook.sh" "$tmp/claude-rg-hard-$$" 2> /dev/null || cp "$work/projeto/hook.sh" "$tmp/claude-rg-hard-$$"
expect ask "git status --short > $tmp/claude-rg-link-$$"
expect ask "git status --short > $tmp/claude-rg-dir-$$/novo.sh"
# link/.. sobe a partir do alvo do link, não do texto: /tmp/d2/../hook.sh é o hook do projeto
mkdir -p "$work/projeto/sub" && ln -s "$work/projeto/sub" "$tmp/claude-rg-d2-$$"
expect ask "git status --short > $tmp/claude-rg-d2-$$/../hook.sh"
rm -f "$tmp/claude-rg-d2-$$"
[ "$(stat -c %h "$tmp/claude-rg-hard-$$" 2> /dev/null)" = 2 ] && expect ask "git status --short > $tmp/claude-rg-hard-$$"
rm -f "$tmp/claude-rg-link-$$" "$tmp/claude-rg-dir-$$" "$tmp/claude-rg-hard-$$"

# comando gigante: pede aprovação sem estourar o prazo do hook (hook que estoura o prazo não bloqueia)
big="git status --short $(head -c 100000 /dev/zero | tr '\0' 1) > x"
start=$(date +%s)
expect ask "$big"
digits="git status --short $(head -c 19000 /dev/zero | tr '\0' 1)>/dev/null >> y"
expect ask "$digits"
[ $(( $(date +%s) - start )) -le 4 ] || { echo "FALHOU: comando gigante levou mais de 4 s no hook"; fails=$((fails + 1)); }

# payload ilegível: pede aprovação, também na nuvem
got=$(printf 'não é json' | env -u CLAUDE_CODE_REMOTE bash "$hook" 2> /dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null)
[ "$got" = ask ] || { echo "FALHOU: payload ilegível não pediu aprovação"; fails=$((fails + 1)); }
got=$(printf 'não é json' | CLAUDE_CODE_REMOTE=true bash "$hook" 2> /dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null)
[ "$got" = ask ] || { echo "FALHOU: payload ilegível não pediu aprovação na nuvem"; fails=$((fails + 1)); }

# Nuvem (CLAUDE_CODE_REMOTE=true, VM descartável): o hook não pede nada. A trava por texto do comando é contornável
# (aspas no meio do nome, tee, sed -i) e o que importa na VM é o que SAI dela: push-guard e checkpoint.sh conferem os
# caminhos protegidos do que será publicado. Qualquer valor diferente de true segue a regra local acima.
cloud() { # cloud <livre|ask> <valor de CLAUDE_CODE_REMOTE> <comando>
  local got; got=$(REMOTE=$2 verdict "$3"); got=${got:-livre}
  [ "$got" = "$1" ] || { echo "FALHOU (CLAUDE_CODE_REMOTE=$2): esperado $1, obtido $got: $3"; fails=$((fails + 1)); }
}
for c in 'echo a > .claude/x' 'echo a > .claude/hooks/x.sh' 'git status --short > .gitignore' 'git status --short >| .claude/settings.json' \
  'grep -rn "A =>" src' 'grep "<IMigrator>" tests' 'echo a > src/Foo.cs' 'echo a > ~/x' 'echo a > /etc/x' 'echo a > "$X"' 'echo a >&x' \
  'cat <<EOF > x
a
EOF' 'gh pr list --state merged --search "merged:>=2026-11-01"' "$big"; do
  cloud livre true "$c"
  cloud ask '' "$c"
done
# fora da nuvem nada muda: variável de outro valor segue a regra local
for r in false 1 TRUE yes; do
  cloud ask "$r" 'echo a > .claude/x'
  cloud ask "$r" 'grep -rn "A =>" src'
  cloud livre "$r" 'git log -1 >/dev/null 2>&1'
done

if [ "$fails" -eq 0 ]; then echo "test-redirect-guard: todos os casos passaram"; exit 0; fi
echo "test-redirect-guard: $fails falha(s)"
exit 1
