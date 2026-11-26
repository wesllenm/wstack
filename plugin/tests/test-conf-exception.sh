#!/usr/bin/env bash
# Casos do conf-exception.mjs (exceções do risk.conf com motivo e data de vencimento) e do aviso dele no SessionStart.
# Sem rede.
# Uso: test-conf-exception.sh [<conf-exception.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

mod=${1:-$(dirname "$0")/../hooks/conf-exception.mjs}
[ -f "$mod" ] || { echo "conf-exception.mjs não encontrado" >&2; exit 2; }
mod=$(cd "$(dirname "$mod")" && pwd)/$(basename "$mod")
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-ce-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

# parse: devolve "válida|valor|problema" para a linha crua
parse() { node --input-type=module -e "import { parseException } from '$mod'; const e = parseException(process.argv[1]); console.log([e.valid, e.value, e.problem].join('|'));" "$1"; }
expect() { local got; got=$(parse "$2"); [[ "$got" == $1 ]] || fail "parse '$2': obtido '$got', esperado '$1'"; }

# caminho feliz: data futura e motivo
expect 'true|dotnet|' 'dotnet | vence: 2999-12-31 | motivo: formas fechadas'
expect 'true|docs/generated/**|' 'docs/generated/** | motivo: gerado | vence: 2999-01-01'
# vencida, sem data, sem motivo: ignorada, com o problema dito
expect 'false|dotnet|venceu em 2000-01-01' 'dotnet | vence: 2000-01-01 | motivo: velho'
expect 'false|dotnet|sem data de vencimento*' 'dotnet'
expect 'false|dotnet|sem motivo*' 'dotnet | vence: 2999-12-31'
expect 'false|dotnet|sem motivo*' 'dotnet | vence: 2999-12-31 | motivo:   '
# malformada: data que não existe, formato errado, campo desconhecido no lugar da data
expect 'false|dotnet|data inválida: 2999-02-30' 'dotnet | vence: 2999-02-30 | motivo: x'
expect 'false|dotnet|data inválida: 31/12/2999' 'dotnet | vence: 31/12/2999 | motivo: x'
expect 'false|dotnet|sem data de vencimento*' 'dotnet | validade: 2999-12-31 | motivo: x'

# --warn: avisa só as exceções ignoradas, com a linha; chave que não é exceção não entra; sai 0
mkdir -p "$work/p/.claude"
cat > "$work/p/.claude/risk.conf" <<'EOF'
# allow_module = comentado
allow_module = dotnet | vence: 2999-12-31 | motivo: ok
review_exclude = docs/generated/**
smell_exclude = **/Interop/** | vence: 2001-05-01 | motivo: legado
base = HEAD
EOF
out=$(CLAUDE_PROJECT_DIR=$work/p node "$mod" --warn); code=$?
[ "$code" = 0 ] || fail "--warn: código $code"
grep -q 'linha 3, review_exclude = docs/generated/\*\*): sem data de vencimento' <<< "$out" || fail "--warn: sem o aviso do review_exclude ($out)"
grep -q 'linha 4, smell_exclude = \*\*/Interop/\*\*): venceu em 2001-05-01' <<< "$out" || fail "--warn: sem o aviso do smell_exclude ($out)"
grep -q 'allow_module' <<< "$out" && fail "--warn: avisou da exceção válida ($out)"
[ "$(wc -l <<< "$out")" = 2 ] || fail "--warn: esperado 2 avisos ($out)"
# sem risk.conf: sai 0 calado
out=$(CLAUDE_PROJECT_DIR=$work/nada node "$mod" --warn); code=$?
[ "$code" = 0 ] && [ -z "$out" ] || fail "--warn sem risk.conf: código $code, saída ($out)"

if [ "$fails" -eq 0 ]; then echo 'test-conf-exception: todos os casos passaram'; exit 0; fi
echo "test-conf-exception: $fails falha(s)"
exit 1
