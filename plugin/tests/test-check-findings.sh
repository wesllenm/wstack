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
# com esperado: preenchido, o " → " de dentro do comando não corta a prova
{ item lente-3g bloqueante correctness "node -e 'console.log(\"a → b\")'"; printf '  esperado: a → b\n'; echo 'status: achados'; } > "$work/seta-com-esperado.txt"
run --json "$work/seta-com-esperado.txt"
node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8")); const r=j.results[0]; process.exit(r.proof==="presente" && r.proof_command.endsWith("\")'"'"'") ? 0 : 1)' <<< "$out" 2> /dev/null \
  || fail "seta no comando com esperado: o comando foi cortado ($out)"
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

# chave repetida (severidade: nit e severidade: bloqueante): o script leria a primeira e o verificador as duas; descarta
{ item lente-dup nit correctness; printf '  severidade: bloqueante\n'; echo 'status: achados'; } > "$work/dup.txt"
run --json "$work/dup.txt"
node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8")); const r=j.results[0]; process.exit(r.status==="descartado" && /chave repetida no candidato \(severidade\)/.test(r.detail) ? 0 : 1)' <<< "$out" 2> /dev/null \
  || fail "chave repetida: não foi descartado ($out)"
# linha do trecho com recuo menor que 4 fica fora dele: o candidato ganha aviso de trecho cortado
printf -- '- id: lente-cut\n  categoria: correctness\n  severidade: nit\n  confiança: 80\n  local: src/a.cs:1\n  trecho: |\n    linha um\n  var total = itens.Sum(i => i.Preco);\n  evidência: src/a.cs:1 — x\n  cenário: x → y\n  preexistente: sim\nstatus: achados\n' > "$work/cortado.txt"
run "$work/cortado.txt"
grep -q 'atenção: trecho pode ter sido cortado' <<< "$out" || fail "trecho cortado: sem aviso ($out)"
# duas lentes com o mesmo nome de arquivo em pastas diferentes não se misturam: a saída usa o caminho inteiro
mkdir -p "$work/g1" "$work/g2"
printf 'acho que está tudo certo\n' > "$work/g1/review-agent.txt"
printf 'status: sem achados\n' > "$work/g2/review-agent.txt"
run "$work/g1/review-agent.txt" "$work/g2/review-agent.txt"; expect_code 'lentes com o mesmo nome' 4
grep -qF "lacuna: $work/g1/review-agent.txt — " <<< "$out" || fail "lentes com o mesmo nome: lacuna sem o caminho inteiro ($out)"
grep -qF "lacuna: $work/g2/review-agent.txt" <<< "$out" && fail "lentes com o mesmo nome: a lente boa herdou a lacuna ($out)"
# entrada malformada: arquivo ilegível é 3; opção desconhecida é 2; --rev que não é commit é 2
run "$work/nao-existe.txt"; expect_code 'arquivo ausente' 3
run --xpto "$work/limpa.txt"; expect_code 'opção desconhecida' 2
run --rev nao-e-commit "$work/limpa.txt"; expect_code '--rev inválido' 2
run --rev --output=x "$work/limpa.txt"; expect_code '--rev com hífen' 2
# trecho que não existe descarta (achado alucinado)
sed 's/var total = itens.Sum(i => i.Preco);/var inventado = 1;/' "$work/prova.txt" > "$work/alucinado.txt"
run "$work/alucinado.txt"; expect_code 'alucinado' 0
grep -q '^- id:' <<< "$out" && fail "alucinado: candidato não foi descartado ($out)"
# a lente que só trouxe lixo não some num "sem achados": a saída diz, para a calibração
grep -q '^descartes: alucinado.txt — 1 de 1 candidato(s) descartado(s) (1 trecho não encontrado)' <<< "$out" || fail "alucinado: sem a linha descartes: ($out)"
grep -qx 'sem achados' <<< "$out" && fail "alucinado: lente só com descartes virou 'sem achados' ($out)"
# lente com um candidato bom e um alucinado não ganha a linha descartes:
cat "$work/prova.txt" | sed '$d' > "$work/misto.txt"; sed '$d' "$work/alucinado.txt" | sed 's/lente-1/lente-9/' >> "$work/misto.txt"; echo 'status: achados' >> "$work/misto.txt"
run "$work/misto.txt"
grep -q '^descartes:' <<< "$out" && fail "lente mista: ganhou descartes: ($out)"

# achado sobre código que o diff removeu ("removeu a checagem"): o trecho está nas linhas removidas, não no arquivo
rm2=$work/rm
git init -q "$rm2"; mkdir -p "$rm2/src"
printf 'void M(Pedido p) {\n  if (p == null) throw new ArgumentNullException(nameof(p));\n  Salvar(p);\n}\n' > "$rm2/src/b.cs"
git -C "$rm2" -c user.email=t@t -c user.name=t add -A; git -C "$rm2" -c user.email=t@t -c user.name=t commit -qm base; git -C "$rm2" branch -q -M main
printf 'void M(Pedido p) {\n  Salvar(p);\n}\n' > "$rm2/src/b.cs"
printf -- '- id: lente-r\n  categoria: correctness\n  severidade: bloqueante\n  confiança: 90\n  local: src/b.cs:2\n  trecho: |\n    if (p == null) throw new ArgumentNullException(nameof(p));\n  evidência: src/b.cs:2 — a guarda saiu\n  cenário: p nulo → NullReferenceException em Salvar\n  prova: dotnet test --filter Nulo\n  esperado: NullReferenceException\n  preexistente: não\nstatus: achados\n' > "$work/removido.txt"
out=$(cd "$rm2" && node "$script" "$work/removido.txt" 2> "$work/err"); code=$?
[ "$code" = 0 ] || fail "removido: código $code ($(cat "$work/err"))"
grep -q '^- id: lente-r$' <<< "$out" || fail "removido: achado sobre linha removida foi descartado ($out)"
grep -q '^  ancoragem: removido (trecho removido pelo diff' <<< "$out" || fail "removido: ancoragem ($out)"
grep -q 'fora das linhas alteradas' <<< "$out" && fail "removido: marcado fora do diff ($out)"
# local na linha seguinte a um trecho que só remove também está no diff (sem o aviso de preexistente)
printf -- '- id: lente-s\n  categoria: correctness\n  severidade: nit\n  confiança: 80\n  local: src/b.cs:2\n  trecho: |\n    Salvar(p);\n  evidência: src/b.cs:2 — x\n  cenário: x → y\n  preexistente: não\nstatus: achados\n' > "$work/corte.txt"
out=$(cd "$rm2" && node "$script" "$work/corte.txt" 2> /dev/null)
grep -q 'fora das linhas alteradas' <<< "$out" && fail "corte: linha junto de trecho que só remove ficou fora do diff ($out)"
# linha adicionada que começa com "++ " e linha removida "-- " (SQL) são conteúdo, não cabeçalho
printf -- '-- comentário antigo\nSELECT 1;\n' > "$rm2/src/q.sql"; git -C "$rm2" -c user.email=t@t -c user.name=t add -A; git -C "$rm2" -c user.email=t@t -c user.name=t commit -qm sql
printf '++ nova\nSELECT 1;\n' > "$rm2/src/q.sql"
printf -- '- id: lente-q\n  categoria: correctness\n  severidade: nit\n  confiança: 80\n  local: src/q.sql:1\n  trecho: |\n    -- comentário antigo\n  evidência: src/q.sql:1 — x\n  cenário: x → y\n  preexistente: não\nstatus: achados\n' > "$work/sql.txt"
out=$(cd "$rm2" && node "$script" --base HEAD "$work/sql.txt" 2> /dev/null)
grep -q '^  ancoragem: removido' <<< "$out" || fail "SQL: linha removida '-- ' não foi lida como conteúdo ($out)"

if [ "$fails" -eq 0 ]; then echo 'test-check-findings: todos os casos passaram'; exit 0; fi
echo "test-check-findings: $fails falha(s)"
exit 1
