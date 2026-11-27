#!/usr/bin/env bash
# Casos do check-findings.mjs (ancoragem dos candidatos de revisão, prova por execução e status de cada lente), num
# repositório git temporário. Sem rede e sem modelo.
# Uso: test-check-findings.sh [<check-findings.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

script=${1:-$(dirname "$0")/../scripts/check-findings.mjs}
[ -f "$script" ] || { echo "check-findings.mjs não encontrado" >&2; exit 2; }
script=$(cd "$(dirname "$script")" && pwd)/$(basename "$script")
command -v node > /dev/null || { echo "node ausente" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-cf-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }

repo=$work/repo
git init -q "$repo"
gitc() { git -C "$repo" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$repo/src"
printf 'linha um\nvar total = itens.Sum(i => i.Preco);\nlinha tres\n' > "$repo/src/a.cs"
gitc add -A && gitc commit -qm base && gitc branch -q -M main
printf 'nova linha\n' >> "$repo/src/a.cs"

item() { # item <id> <severidade> <categoria> [prova]
  printf -- '- id: %s\n  categoria: %s\n  severidade: %s\n  confiança: 80\n  local: src/a.cs:2\n  trecho: |\n    var total = itens.Sum(i => i.Preco);\n  evidência: src/a.cs:2 — soma sem quantidade\n  cenário: quantidade 2 → total errado\n' "$1" "$3" "$2"
  [ $# -ge 4 ] && printf '  prova: %s\n' "$4"
  printf '  correção mínima: multiplicar\n  preexistente: sim\n'
}
run() { # run <arquivos...>: saída em $out, stderr em $err, código em $code
  out=$(cd "$repo" && node "$script" "$@" 2> "$work/err"); code=$?; err=$(cat "$work/err")
}
expect_code() { [ "$code" = "$2" ] || fail "$1: código $code, esperado $2 ($err)"; }

# caminho feliz: bloqueante com prova completa mantém a severidade e não ganha "a confirmar"
{ item lente-1 bloqueante correctness 'dotnet test --filter Total → Assert.Equal falhou: esperado 20, obtido 10'; echo 'status: achados'; } > "$work/prova.txt"
run "$work/prova.txt"; expect_code 'com prova' 0
grep -q '^  severidade: bloqueante$' <<< "$out" || fail 'com prova: severidade mudou'
grep -q 'situação:' <<< "$out" && fail 'com prova: ganhou situação a confirmar'
grep -q '^  ancoragem: ancorado' <<< "$out" || fail "com prova: não ancorou ($out)"

# bloqueante sem prova: fica, com a severidade dele, marcado "a confirmar"; não é descartado
{ item lente-2 bloqueante correctness; echo 'status: achados'; } > "$work/sem-prova.txt"
run "$work/sem-prova.txt"; expect_code 'sem prova' 0
grep -q '^- id: lente-2$' <<< "$out" || fail 'sem prova: candidato descartado'
grep -q '^  situação: a confirmar (sem prova:' <<< "$out" || fail "sem prova: sem situação a confirmar ($out)"
grep -q '1 a confirmar sem prova' <<< "$err" || fail "sem prova: resumo não conta ($err)"
# prova sem a saída esperada também fica a confirmar
{ item lente-3 importante security 'dotnet test --filter Total'; echo 'status: achados'; } > "$work/prova-incompleta.txt"
run "$work/prova-incompleta.txt"
grep -q 'situação: a confirmar (prova: sem a saída esperada' <<< "$out" || fail "prova incompleta: não rebaixou ($out)"
# saída esperada no campo próprio esperado:
{ item lente-3b importante security 'dotnet test --filter Total'; printf '  esperado: Assert.Equal falhou\n'; echo 'status: achados'; } > "$work/esperado.txt"
run "$work/esperado.txt"
grep -q 'situação:' <<< "$out" && fail "esperado: campo próprio não contou ($out)"
# "->" dentro do comando não é separador: sem esperado:, a prova continua incompleta
{ item lente-3c bloqueante correctness "grep 'p->x' src/a.c"; echo 'status: achados'; } > "$work/seta-no-comando.txt"
run "$work/seta-no-comando.txt"
grep -q 'situação: a confirmar (prova: sem a saída esperada' <<< "$out" || fail "seta no comando: passou como prova completa ($out)"
# severidade ausente ou fora da lista não dispensa a prova: conta como bloqueante
printf -- '- id: lente-3d\n  categoria: correctness\n  confiança: 80\n  local: src/a.cs:2\n  trecho: |\n    var total = itens.Sum(i => i.Preco);\n  evidência: src/a.cs:2 — x\n  cenário: x → y\nstatus: achados\n' > "$work/sem-severidade.txt"
run "$work/sem-severidade.txt"
grep -q 'situação: a confirmar (severidade ausente, tratada como bloqueante; sem prova:' <<< "$out" || fail "sem severidade: dispensou a prova ($out)"
for s in 'Bloqueante (alta)' 'alta' 'Nit!'; do
  { item lente-3e "$s" correctness; echo 'status: achados'; } > "$work/severidade-errada.txt"
  run "$work/severidade-errada.txt"
  grep -q 'severidade fora da lista' <<< "$out" && grep -q 'situação: a confirmar' <<< "$out" || fail "severidade '$s': dispensou a prova ($out)"
done
# severidade errada com prova completa: não fica a confirmar, mas avisa que o verificador dá a severidade
{ item lente-3f 'Alta' correctness 'dotnet test → falhou'; echo 'status: achados'; } > "$work/severidade-errada-com-prova.txt"
run "$work/severidade-errada-com-prova.txt"
grep -q 'situação: severidade fora da lista: o verificador dá a severidade final' <<< "$out" || fail "severidade errada com prova: sem aviso ($out)"
# simplicity e nit dispensam a prova
{ item lente-4 importante simplicity; item lente-5 nit correctness; echo 'status: achados'; } > "$work/dispensada.txt"
run "$work/dispensada.txt"
grep -q 'situação:' <<< "$out" && fail "prova dispensada: ganhou situação ($out)"
# o candidato não forja a situação nem a ancoragem
{ item lente-6 bloqueante correctness; printf '  situação: confirmado\n  ancoragem: ancorado\n'; echo 'status: achados'; } > "$work/forjado.txt"
run "$work/forjado.txt"
grep -q 'situação: confirmado' <<< "$out" && fail 'forjado: situação do candidato passou'
grep -q '^  situação: a confirmar' <<< "$out" || fail 'forjado: perdeu a situação do script'

# status das lentes: sem achados de verdade é 0 e "sem achados"
printf 'status: sem achados\n' > "$work/limpa.txt"
printf 'sem achados\n' > "$work/interrogate-limpo.txt"
printf 'status: sem achados\naprendizado: o filtro global cobre o tenant\n' > "$work/com-aprendizado.txt"
run "$work/com-aprendizado.txt"; expect_code 'aprendizado depois do status' 0
run "$work/limpa.txt" "$work/interrogate-limpo.txt"; expect_code 'lentes sem achados' 0
[ "$out" = 'sem achados' ] || fail "lentes sem achados: saída ($out)"
# lente sem status (resposta truncada) é lacuna: código 4 e nunca "sem achados"
item lente-7 nit correctness > "$work/truncada.txt"
printf 'acho que está tudo certo\n' > "$work/prosa.txt"
run "$work/limpa.txt" "$work/truncada.txt" "$work/prosa.txt"; expect_code 'lente sem status' 4
grep -q '^lacuna: truncada.txt — sem a linha de status' <<< "$out" || fail "lente sem status: sem lacuna da truncada ($out)"
grep -q '^lacuna: prosa.txt — ' <<< "$out" || fail "lente sem status: sem lacuna da prosa ($out)"
grep -qx 'sem achados' <<< "$out" && fail 'lente sem status: lacuna virou "sem achados"'
grep -q '^- id: lente-7$' <<< "$out" || fail 'lente sem status: perdeu o candidato da lente truncada'
# vazia, falhou, e status que contradiz o conteúdo
: > "$work/vazia.txt"
printf 'status: falhou: estourou o tempo\n' > "$work/falhou.txt"
printf 'falhou: gama — saiu com código 1\n' > "$work/interrogate-falhou.txt"
printf 'status: achados\n' > "$work/achados-vazio.txt"
{ item lente-8 nit correctness; echo 'status: sem achados'; } > "$work/contradiz.txt"
run "$work/vazia.txt" "$work/falhou.txt" "$work/interrogate-falhou.txt" "$work/achados-vazio.txt" "$work/contradiz.txt"; expect_code 'lentes com falha' 4
for c in 'vazia.txt — sem a linha de status' 'falhou.txt — falhou: estourou o tempo' 'interrogate-falhou.txt — falhou: gama' \
  'achados-vazio.txt — status achados sem candidato' 'contradiz.txt — status sem achados com candidatos'; do
  grep -qF "lacuna: $c" <<< "$out" || fail "lentes com falha: sem 'lacuna: $c' ($out)"
done
run --json "$work/falhou.txt"; expect_code 'json com lacuna' 4
node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit(j.lacunas.length===1?0:1)' <<< "$out" 2> /dev/null || fail "json com lacuna: campo lacunas ($out)"

# entrada malformada: arquivo ilegível é 3; opção desconhecida é 2; --rev que não é commit é 2
run "$work/nao-existe.txt"; expect_code 'arquivo ausente' 3
run --xpto "$work/limpa.txt"; expect_code 'opção desconhecida' 2
run --rev nao-e-commit "$work/limpa.txt"; expect_code '--rev inválido' 2
run --rev --output=x "$work/limpa.txt"; expect_code '--rev com hífen' 2
# trecho que não existe descarta (achado alucinado)
sed 's/var total = itens.Sum(i => i.Preco);/var inventado = 1;/' "$work/prova.txt" > "$work/alucinado.txt"
run "$work/alucinado.txt"; expect_code 'alucinado' 0
[ "$out" = 'sem achados' ] || fail "alucinado: candidato não foi descartado ($out)"

if [ "$fails" -eq 0 ]; then echo 'test-check-findings: todos os casos passaram'; exit 0; fi
echo "test-check-findings: $fails falha(s)"
exit 1
