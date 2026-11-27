#!/usr/bin/env bash
# Casos dos repositórios companheiros (chave companion do risk.conf, companions.mjs) com dois repositórios git de
# verdade, Platform e ServerControl, lado a lado: a validação da lista, o classify-diff.sh --companions, o
# verify-on-stop (o companheiro vermelho bloqueia o Stop; o aprendizado fica no projeto) e o checkpoint-tests (o commit
# no companheiro usa o risk.conf dele). Sem rede.
# Uso: test-companions.sh [<pasta do plugin>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

plugin=$(cd "${1:-$(dirname "$0")/..}" && pwd -P)
[ -f "$plugin/hooks/companions.mjs" ] || { echo "companions.mjs não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-comp-XXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU [$1]: $2"; fails=$((fails + 1)); }
gitc() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# par novo: Platform (projeto) e ServerControl (companheiro), cada um com risk.conf e um commit base
par() { # par <nome> <linhas extras do risk.conf do Platform>...
  local d="$work/$1"; shift
  P=$d/Platform; C=$d/ServerControl
  for r in "$P" "$C"; do
    git init -q "$r"; mkdir -p "$r/.claude"; printf 'base = HEAD\n' > "$r/.claude/risk.conf"
    printf 'x\n' > "$r/a.cs"; gitc "$r" add -A; gitc "$r" commit -qm base
  done
  printf 'companion = ../ServerControl\n' >> "$P/.claude/risk.conf"
  local l; for l in "$@"; do printf '%s\n' "$l" >> "$P/.claude/risk.conf"; done
  gitc "$P" commit -qam conf
}

# --- companions.mjs: só vale raiz de repositório git com risk.conf, diferente do projeto
par lista 'companion = ../nada' 'companion = .' 'companion = /etc'
git init -q "$work/lista/Solto"
printf 'companion = ../Solto\n' >> "$P/.claude/risk.conf"
out=$(cd "$P" && CLAUDE_PROJECT_DIR=$P node "$plugin/hooks/companions.mjs")
[ "$out" = "$C" ] || fail lista-valida "$out"
s=$(cd "$P" && CLAUDE_PROJECT_DIR=$P node "$plugin/hooks/companions.mjs" --session)
for t in 'companion = ../nada ignorado: a pasta não existe' 'companion = . ignorado: é o próprio projeto' \
  'companion = /etc ignorado' 'companion = ../Solto ignorado: o repositório não tem .claude/risk.conf' 'Repositórios companheiros (risk.conf, companion): ../ServerControl'; do
  grep -qF -- "$t" <<< "$s" || fail "session: $t" "$s"
done

# --- classify-diff --companions: o maior nível, e COMPLEXA quando os dois mudam código
classify() { CLAUDE_PROJECT_DIR=$P bash "$plugin/scripts/classify-diff.sh" --companions; }
par risco
printf 'y\n' >> "$P/a.cs"
[ "$(classify | head -1)" = TRIVIAL ] || fail risco-so-projeto "$(classify | tr '\n' '|')"
grep -qx 'repositório: ServerControl TRIVIAL' <<< "$(classify)" || fail risco-lista-companheiro "$(classify | tr '\n' '|')"
printf 'y\n' >> "$C/a.cs"
[ "$(classify | head -1)" = COMPLEXA ] || fail risco-dois-com-codigo "$(classify | tr '\n' '|')"
grep -qF 'código mudou em 2 repositórios' <<< "$(classify)" || fail risco-motivo "$(classify | tr '\n' '|')"
gitc "$C" checkout -q a.cs; printf 'doc\n' > "$C/README.md"
[ "$(classify | head -1)" = TRIVIAL ] || fail risco-doc-no-companheiro "$(classify | tr '\n' '|')"
planned() { CLAUDE_PROJECT_DIR=$P bash "$plugin/scripts/classify-diff.sh" --companions --paths "$@"; }
[ "$(planned a.cs ../ServerControl/b.cs | head -1)" = COMPLEXA ] || fail planejado-dois "$(planned a.cs ../ServerControl/b.cs | tr '\n' '|')"
out=$(planned ../ServerControl/b.cs)
grep -qx 'repositório: ServerControl SIMPLES' <<< "$out" || fail planejado-so-companheiro "$(tr '\n' '|' <<< "$out")"
grep -q 'repositório: Platform' <<< "$out" && fail planejado-sem-projeto "$(tr '\n' '|' <<< "$out")"
[ "$(planned a.cs docs/x.md | head -1)" = SIMPLES ] || fail planejado-so-projeto "$(planned a.cs docs/x.md | tr '\n' '|')"
printf 'critical = *a.cs\n' >> "$C/.claude/risk.conf"; gitc "$C" commit -qam crit; printf 'z\n' >> "$C/a.cs"
[ "$(classify | head -1)" = CRITICA ] || fail risco-critica-do-companheiro "$(classify | tr '\n' '|')"
grep -q '^motivo: CRITICA .*(ServerControl)$' <<< "$(classify)" || fail risco-motivo-com-nome "$(classify | tr '\n' '|')"

# --- verify-on-stop: o companheiro vermelho bloqueia; verde segue; o aprendizado fica só no projeto
stop() { jq -cn '{session_id:"s1"}' | CLAUDE_PROJECT_DIR=$P bash "$plugin/hooks/verify-on-stop.sh" > "$work/out" 2> "$work/err"; echo $?; }
par fim
for r in "$P" "$C"; do printf 'verify_solution = a.cs\nverify_build = true\nverify_test = true\n' >> "$r/.claude/risk.conf"; gitc "$r" commit -qam v; done
printf 'mudou\n' >> "$C/a.cs"
[ "$(stop)" = 0 ] || fail fim-companheiro-verde "$(head -c 300 "$work/err")"
sed -i 's/^verify_build = true$/verify_build = false/' "$C/.claude/risk.conf"; gitc "$C" commit -qam vermelho; printf 'de novo\n' >> "$C/a.cs"
rc=$(stop)
[ "$rc" = 2 ] || fail fim-companheiro-vermelho "código $rc: $(head -c 300 "$work/err")"
grep -qF 'Repositório companheiro ServerControl' "$work/err" || fail fim-motivo-com-nome "$(head -c 300 "$work/err")"
# o gate de aprendizado não roda no companheiro: calibração lá, commit de código, sem registro, não bloqueia
par aprende
mkdir -p "$C/docs" && printf '# Calibração\n' > "$C/docs/review-calibration.md" && gitc "$C" add -A && gitc "$C" commit -qm calib
mkdir -p "$C/.claude/.session" && gitc "$C" rev-parse HEAD > "$C/.claude/.session/s1.base"
printf 'codigo\n' >> "$C/a.cs" && gitc "$C" commit -qam codigo
[ "$(stop)" = 0 ] || fail fim-sem-aprendizado-no-companheiro "$(head -c 300 "$work/err")"

# --- checkpoint-tests: o commit no companheiro usa as áreas do risk.conf dele
ck() { # ck <cwd> <comando>: código do hook
  jq -cn --arg c "$2" --arg d "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' |
    CLAUDE_PROJECT_DIR=$P bash "$plugin/hooks/checkpoint-tests.sh" > /dev/null 2> "$work/ckerr"; echo $?
}
par commit
printf 'checkpoint = *.cs -> false\n' >> "$C/.claude/risk.conf"; gitc "$C" commit -qam ck
printf 'y\n' >> "$C/a.cs"
[ "$(ck "$C" 'git commit -m x')" = 2 ] || fail checkpoint-pasta-do-companheiro "$(head -c 200 "$work/ckerr")"
[ "$(ck "$P" 'git -C ../ServerControl commit -m x')" = 2 ] || fail checkpoint-menos-C "$(head -c 200 "$work/ckerr")"
[ "$(ck "$P" 'git commit -m x')" = 0 ] || fail checkpoint-projeto-sem-area "$(head -c 200 "$work/ckerr")"
# repositório fora da lista: vale o risk.conf do projeto (sem área), não o do repositório do comando
sed -i '/^companion = /d' "$P/.claude/risk.conf"; printf 'checkpoint = nada/* -> false\n' >> "$P/.claude/risk.conf"; gitc "$P" commit -qam sem
[ "$(ck "$C" 'git commit -m x')" = 0 ] || fail checkpoint-fora-da-lista "$(head -c 200 "$work/ckerr")"

if [ "$fails" -eq 0 ]; then echo "test-companions: todos os casos passaram"; exit 0; fi
echo "test-companions: $fails falha(s)"
exit 1
