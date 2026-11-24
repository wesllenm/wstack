#!/usr/bin/env bash
# Checkpoint de tarefa: roda os testes da área tocada quando o Claude tenta commitar (PreToolUse em Bash,
# só para comandos git commit) ou marcar uma tarefa como concluída (TaskCompleted). Falha devolve código 2:
# o commit não acontece, ou a tarefa não fecha, e a saída vai para o Claude corrigir.
# Configuração no .claude/risk.conf, uma linha por área; cada comando roda uma vez, mesmo que várias áreas casem:
#   checkpoint = <glob> -> <comando>      ex.: checkpoint = src/*/Auth/* -> dotnet test tests/Auth.Tests --no-restore
#   checkpoint_timeout = 600               segundos por comando
# No glob, * atravessa pastas. Mesmo conteúdo já aprovado não roda de novo (cache por hash do diff).
# Código: 0 nada a checar ou testes ok; 2 testes falharam.
set -uo pipefail

input=$(cat)
root=${CLAUDE_PROJECT_DIR:-$(pwd)}
conf="$root/.claude/risk.conf"
[ -f "$conf" ] || exit 0
grep -q '^[[:space:]]*checkpoint[[:space:]]*=' "$conf" || exit 0

read -r event command < <(printf '%s' "$input" | node -e '
  let d = ""; process.stdin.on("data", (c) => (d += c)).on("end", () => {
    let j; try { j = JSON.parse(d); } catch { return; }
    const cmd = (j?.tool_input?.command ?? "").replace(/\s+/g, " ");
    process.stdout.write(`${j?.hook_event_name ?? ""} ${cmd}`);
  });')
# Falha fechada: sem node ou com payload ilegível não dá para saber o que se está executando. Se o texto bruto
# menciona git commit, o commit não passa sem checkpoint; qualquer outro comando segue (o hook roda em todo Bash).
if [ -z "$event" ]; then
  if printf '%s' "$input" | grep -Eq 'git.*commit'; then
    echo "Checkpoint não pôde interpretar o comando (node ausente do PATH ou payload ilegível) e o texto menciona git commit: commit recusado. Corrija o ambiente do hook." >&2
    exit 2
  fi
  exit 0
fi
case "$event" in
  TaskCompleted) ;;
  PreToolUse)
    # só git commit (com -C <dir> ou -c chave=valor antes), em qualquer ponto de uma cadeia com ; && ||
    [[ " $command" =~ (^|[[:space:];\&\|\(])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$) ]] || exit 0 ;;
  *) exit 0 ;;
esac

cd "$root" || exit 0
git rev-parse --git-dir > /dev/null 2>&1 || exit 0
if git rev-parse --verify -q HEAD > /dev/null; then
  changed=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
else
  changed=$( { git diff --name-only --cached; git ls-files --others --exclude-standard; } | sort -u)
fi
[ -n "$changed" ] || exit 0

limit=$(sed -n 's/^[[:space:]]*checkpoint_timeout[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$conf" | tail -1)
limit=${limit:-600}
cmds=()
while IFS= read -r line; do
  rule=$(printf '%s' "$line" | sed -n 's/^[[:space:]]*checkpoint[[:space:]]*=[[:space:]]*//p')
  [ -n "$rule" ] || continue
  glob=$(printf '%s' "${rule%% -> *}" | sed 's/[[:space:]]*$//')
  cmd=${rule#* -> }
  [ "$cmd" != "$rule" ] && [ -n "$glob" ] || continue
  hit=0
  while IFS= read -r f; do
    if [[ "$glob" == */* ]]; then t=$f; else t=${f##*/}; fi
    # shellcheck disable=SC2053
    [[ "$t" == $glob ]] && { hit=1; break; }
  done <<< "$changed"
  [ "$hit" = 1 ] || continue
  dup=0
  for c in "${cmds[@]+"${cmds[@]}"}"; do [ "$c" = "$cmd" ] && dup=1; done
  [ "$dup" = 1 ] || cmds+=("$cmd")
done < "$conf"
[ "${#cmds[@]}" -gt 0 ] || exit 0

# cache: mesmo diff, mesmos não rastreados e mesmos comandos já aprovados não rodam de novo
state="$root/.claude/.session"
mkdir -p "$state" 2> /dev/null
key=$( { git diff HEAD 2> /dev/null || git diff --cached; git ls-files --others --exclude-standard -z | xargs -0 -r cat 2> /dev/null; printf '%s\n' "${cmds[@]}"; } | git hash-object --stdin)
[ -f "$state/checkpoint-ok-$key" ] && exit 0

budget=$(sed -n 's/^[[:space:]]*checkpoint_budget[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$conf" | tail -1)
budget=${budget:-840}
fail=""
started=$SECONDS
for cmd in "${cmds[@]}"; do
  left=$((budget - (SECONDS - started)))
  if [ "$left" -le 0 ]; then
    fail+="Checkpoint sem tempo: o orçamento de ${budget}s acabou antes de: $cmd"$'\n'
    continue
  fi
  run=$((left < limit ? left : limit))
  out=$(timeout "$run" bash -c "$cmd" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    [ "$rc" = 124 ] && out="estourou ${run}s"$'\n'"$out"
    fail+="Checkpoint falhou: $cmd"$'\n'"$(printf '%s\n' "$out" | tail -n 60)"$'\n'
  fi
done
if [ -z "$fail" ]; then
  rm -f "$state"/checkpoint-ok-* 2> /dev/null
  : > "$state/checkpoint-ok-$key"
  exit 0
fi
what="o commit"; [ "$event" = TaskCompleted ] && what="a tarefa"
printf '%sOs testes da área tocada falharam; %s fica para depois da correção. Não enfraqueça nem pule teste para passar.\n' "$fail" "$what" >&2
exit 2
