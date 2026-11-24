#!/usr/bin/env bash
# Hook PostToolUse em Edit|Write|MultiEdit|NotebookEdit: roda a checagem rápida do arquivo recém-editado
# (lint, formatação) e devolve a falha ao Claude enquanto o contexto ainda está no arquivo, em vez de só no Stop.
# Configuração no .claude/risk.conf, uma linha por regra, todas as que casarem rodam:
#   edit_check = <glob> -> <comando com {file}>      ex.: edit_check = *.ts -> npx eslint {file}
#   edit_check_timeout = 60                           segundos por comando
# No glob, * atravessa pastas (src/*.cs casa src/a/b/C.cs); sem / no glob, casa só pelo nome do arquivo.
# PostToolUse não desfaz a edição: o código 2 mostra a falha ao Claude, que corrige na próxima ação.
# Código: 0 sem regra, arquivo fora do projeto ou checagem ok; 2 checagem falhou (stderr vai para o Claude).
set -uo pipefail

input=$(cat)
root=${CLAUDE_PROJECT_DIR:-$(pwd)}
conf="$root/.claude/risk.conf"
[ -f "$conf" ] || exit 0
grep -q '^[[:space:]]*edit_check[[:space:]]*=' "$conf" || exit 0

# caminho do arquivo, relativo à raiz e com /; vazio se fora do projeto
rel=$(printf '%s' "$input" | ROOT="$root" node -e '
  const path = require("node:path"); let d = "";
  process.stdin.on("data", (c) => (d += c)).on("end", () => {
    let j; try { j = JSON.parse(d); } catch { return; }
    const f = j?.tool_input?.file_path || j?.tool_input?.notebook_path || "";
    if (!f) return;
    const r = path.relative(path.resolve(process.env.ROOT), path.resolve(f));
    if (!r || r.startsWith("..") || path.isAbsolute(r)) return;
    process.stdout.write(r.split(path.sep).join("/"));
  });') || exit 0
[ -n "$rel" ] && [ -f "$root/$rel" ] || exit 0

limit=$(sed -n 's/^[[:space:]]*edit_check_timeout[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$conf" | tail -1)
limit=${limit:-60}
base=${rel##*/}
fail=""
cd "$root" || exit 0
while IFS= read -r line; do
  rule=$(printf '%s' "$line" | sed -n 's/^[[:space:]]*edit_check[[:space:]]*=[[:space:]]*//p')
  [ -n "$rule" ] || continue
  glob=$(printf '%s' "${rule%% -> *}" | sed 's/[[:space:]]*$//')
  cmd=${rule#* -> }
  [ "$cmd" != "$rule" ] && [ -n "$glob" ] || continue
  if [[ "$glob" == */* ]]; then target=$rel; else target=$base; fi
  # shellcheck disable=SC2053
  [[ "$target" == $glob ]] || continue
  # O nome do arquivo nunca entra no texto do comando: vai como argumento posicional ($1). Interpolá-lo (mesmo com
  # printf %q) é execução de comando por nome de arquivo: no bash 5.2 o patsub_replacement consome o "\&" do %q.
  # Nome fora do alfabeto seguro não é verificado e bloqueia, em vez de arriscar.
  if [[ ! "$rel" =~ ^[A-Za-z0-9._/@+-]+$ ]]; then
    printf 'Nome de arquivo fora do alfabeto seguro (A-Z a-z 0-9 . _ / @ + -): %s não foi verificado; renomeie o arquivo.\n' "$rel" >&2
    exit 2
  fi
  cmd=${cmd//\{file\}/\"\$1\"}
  if ! out=$(timeout "$limit" bash -c "$cmd" _ "$rel" 2>&1); then
    fail+="Checagem do arquivo editado falhou: $cmd"$'\n'"$(printf '%s\n' "$out" | tail -n 40)"$'\n'
  fi
done < "$conf"

[ -z "$fail" ] && exit 0
printf '%sCorrija %s antes de seguir; não desligue a regra para passar.\n' "$fail" "$rel" >&2
exit 2
