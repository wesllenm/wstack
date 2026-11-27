#!/usr/bin/env bash
# Mede o custo dos hooks do plugin por comando Bash: roda os comandos do PreToolUse em Bash do hooks.json do jeito que
# o Claude Code roda (sh -c, CLAUDE_PLUGIN_ROOT, CLAUDE_PROJECT_DIR, payload na entrada padrão), N vezes para cada
# comando de exemplo, num projeto dado. Mede só o hook: o comando em si não roda. Sem o plugin, o acréscimo é zero.
# O Claude Code roda os hooks de um evento em paralelo, então o acréscimo por comando fica entre o hook mais lento
# (núcleos livres) e a soma de todos (máquina ocupada). No Windows com Git Bash, criar processo é o custo dominante.
# Referência: menos de ~1 s a mais por comando.
# Uso: measure-hook-cost.sh [<pasta do projeto>] [<repetições>]    (padrão: a pasta atual, 20)
# Requer bash 4+, git e node no PATH (o Git Bash do Windows traz bash 5). Não grava nada no projeto.
# Código: 0 mediu, 2 uso errado ou ferramenta ausente.
set -uo pipefail

proj=$(cd "${1:-.}" 2> /dev/null && pwd -P) || { echo "pasta do projeto não encontrada: ${1:-.}" >&2; exit 2; }
n=${2:-20}
[[ $n =~ ^[1-9][0-9]*$ ]] || { echo "repetições: número inteiro positivo" >&2; exit 2; }
plugin=$(cd "$(dirname "$0")/.." && pwd -P)
command -v node > /dev/null || { echo "node ausente do PATH" >&2; exit 2; }
command -v git > /dev/null || { echo "git ausente do PATH" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/wstack-custo-XXXX")
trap 'rm -rf "$work"' EXIT

# relógio em microssegundos: EPOCHREALTIME (bash 5; a vírgula de alguns locais sai), senão o date do GNU
now() {
  if [ -n "${EPOCHREALTIME:-}" ]; then local t=${EPOCHREALTIME//[.,]/}; echo "$t"
  else echo $(( $(date +%s%N) / 1000 )); fi
}

# os comandos do PreToolUse em Bash, um por linha, com o nome do hook (o .sh que ele chama)
node -e '
  const h = require(process.argv[1]).hooks.PreToolUse.filter((m) => m.matcher === "Bash").flatMap((m) => m.hooks);
  for (const x of h) {
    const name = (/hooks\/([A-Za-z0-9_-]+)\.sh/.exec(x.command) ?? [, "?"])[1];
    process.stdout.write(name + "\t" + Buffer.from(x.command).toString("base64") + "\n");
  }' "$plugin/hooks/hooks.json" > "$work/hooks.tsv" || { echo "hooks.json ilegível" >&2; exit 2; }

cmds=('git status' 'ls' 'git diff --stat' 'git log --oneline -5')
echo "Projeto: $proj"
echo "Plugin: $plugin ($(node -e 'console.log(require(process.argv[1]).version)' "$plugin/.claude-plugin/plugin.json"))"
echo "Hooks do PreToolUse em Bash: $(cut -f1 "$work/hooks.tsv" | tr '\n' ' ')"
echo "Repetições por comando: $n"
echo

# decodificados uma vez: no Windows cada node a mais custa caro, e isso não é custo do hook
names=(); hcs=()
while IFS=$'\t' read -r name b64; do
  names+=("$name"); hcs+=("$(node -e 'process.stdout.write(Buffer.from(process.argv[1],"base64").toString())' "$b64")")
done < "$work/hooks.tsv"

: > "$work/tempos.tsv"
for c in "${cmds[@]}"; do
  payload=$(node -e 'process.stdout.write(JSON.stringify({hook_event_name:"PreToolUse",tool_name:"Bash",session_id:"medicao",cwd:process.argv[1],tool_input:{command:process.argv[2]}}))' "$proj" "$c")
  for _ in $(seq 1 "$n"); do
    for i in "${!hcs[@]}"; do
      t0=$(now)
      (cd "$proj" && printf '%s' "$payload" | CLAUDE_PLUGIN_ROOT=$plugin CLAUDE_PROJECT_DIR=$proj sh -c "${hcs[$i]}" > /dev/null 2>&1)
      t1=$(now)
      printf '%s\t%s\t%s\n' "$c" "${names[$i]}" $(( t1 - t0 )) >> "$work/tempos.tsv"
    done
  done
done

node -e '
  const rows = require("fs").readFileSync(process.argv[1], "utf8").trim().split("\n").map((l) => l.split("\t"));
  const med = (a) => { const s = [...a].sort((x, y) => x - y); return s[Math.floor(s.length / 2)]; };
  const ms = (us) => (us / 1000).toFixed(0).padStart(6) + " ms";
  const byCmd = new Map();
  for (const [c, h, us] of rows) {
    if (!byCmd.has(c)) byCmd.set(c, new Map());
    const m = byCmd.get(c); if (!m.has(h)) m.set(h, []); m.get(h).push(Number(us));
  }
  let worstSum = 0;
  for (const [c, m] of byCmd) {
    console.log(`Comando: ${c}`);
    let sum = 0, max = 0;
    for (const [h, a] of m) { const v = med(a); sum += v; max = Math.max(max, v); console.log(`  ${h.padEnd(18)} mediana ${ms(v)}`); }
    console.log(`  acréscimo por comando: ${ms(max).trim()} (hooks em paralelo) a ${ms(sum).trim()} (em série)\n`);
    worstSum = Math.max(worstSum, sum);
  }
  console.log(worstSum < 1e6 ? "Resultado: abaixo de ~1 s por comando, mesmo em série." : "Resultado: acima de ~1 s por comando em série; ver o hook mais lento acima.");
' "$work/tempos.tsv"
# teste de nuvem: dois repositórios na mesma sessão (pode apagar)
