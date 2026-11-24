#!/usr/bin/env bash
# Testa o classify-diff.sh em repositórios git temporários (nada toca o repositório real).
# Uso: bash .claude/scripts/test-classify.sh [<caminho do classify-diff.sh>]   (saída 0 = todos os casos passaram)
#      Sem argumento testa o .claude/scripts/classify-diff.sh vizinho deste arquivo.
# O que protege: o classificador decide quanta revisão cada mudança recebe, então erro de coleta do diff NUNCA
# pode virar um nível baixo (falha fechada), e a contagem de linhas e de testes removidos tem de refletir a mudança real.
# Três blocos: (A) casos do classificador (diff, base, renomeação, arquivos novos, `complex`, `domain`);
#              (B) a bateria do bootstrap 2.8.2 §6.5 (falso positivo e falso negativo dos sinais, git quebrado);
#              (C) o que a 2.8.2 acrescenta: modo --commit, pipeline de CI lido de arquivo real, motivos com nível e `hot`.
set -uo pipefail

if [ -n "${1:-}" ]; then SCRIPT=$(realpath "$1"); else SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/classify-diff.sh"; fi
[ -f "$SCRIPT" ] || { echo "classificador não encontrado: $SCRIPT" >&2; exit 2; }
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claude-classify-test-XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
falhas=0
total=0

conf() { # conf <pasta>: configuração mínima, independente da do projeto
  mkdir -p "$1/.claude"
  cat > "$1/.claude/risk.conf" << 'EOF'
critical = src/Secure/*
complex = src/Complex/*
domain = src/A/*
domain = src/B/*
base = HEAD
EOF
}

git_in() { git -C "$repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.autocrlf=false "$@"; }

new_repo() { # new_repo <nome>: repositório com uma linha de base commitada
  repo="$ROOT/$1"
  mkdir -p "$repo/src/A" "$repo/src/Secure" "$repo/tests"
  conf "$repo"
  git -C "$repo" init -q
  printf 'class Latest {}\n' > "$repo/src/Latest.cs"
  printf 'class FooTests {}\n' > "$repo/tests/FooTests.cs"
  printf 'x\n' > "$repo/README.md"
  git_in add -A
  git_in commit -q -m base
}

classify() { CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" "$@" 2> /dev/null; }

expect() { # expect <nome> <nível esperado> <saída completa> [trecho esperado no resto]
  total=$((total + 1))
  local nome="$1" esperado="$2" saida="$3" trecho="${4:-}" nivel
  nivel=$(printf '%s\n' "$saida" | head -1)
  if [ "$nivel" != "$esperado" ]; then
    echo "FALHOU: $nome — esperado $esperado, veio '$nivel'"; printf '%s\n' "$saida" | sed 's/^/    /'; falhas=$((falhas + 1)); return
  fi
  if [ -n "$trecho" ] && ! printf '%s\n' "$saida" | tail -n +2 | grep -qF -- "$trecho"; then
    echo "FALHOU: $nome — nível certo ($nivel), mas faltou o motivo '$trecho'"; printf '%s\n' "$saida" | sed 's/^/    /'; falhas=$((falhas + 1)); return
  fi
  echo "ok: $nome"
}

refuse() { # refuse <nome> <saída> <trecho proibido>: o motivo NÃO pode aparecer
  total=$((total + 1))
  if printf '%s\n' "$2" | grep -qF -- "$3"; then
    echo "FALHOU: $1 — apareceu '$3'"; printf '%s\n' "$2" | sed 's/^/    /'; falhas=$((falhas + 1))
  else
    echo "ok: $1"
  fi
}

echo "== A. casos do classificador"
# 1. árvore limpa
new_repo limpa
expect "árvore limpa é TRIVIAL" TRIVIAL "$(classify)"

# 2. FALHA FECHADA: fora de um repositório git (a coleta do diff falha)
repo="$ROOT/sem-git"; conf "$repo"
expect "fora de um repositório git é CRITICA" CRITICA "$(classify)" "git"

# 3. FALHA FECHADA: base inexistente (não pode cair em silêncio no HEAD)
new_repo base-invalida
expect "base inexistente é CRITICA" CRITICA "$(classify nao-existe)" "nao-existe"

# 4. arquivo cujo nome contém 'test' dentro de outra palavra NÃO é teste (Latest.cs)
new_repo latest
rm "$repo/src/Latest.cs"
saida=$(classify)
refuse "remover Latest.cs não conta como teste removido" "$saida" "teste removido"
expect "remover Latest.cs é TRIVIAL" TRIVIAL "$saida"

# 5. teste de verdade removido
new_repo teste-removido
rm "$repo/tests/FooTests.cs"
expect "remover tests/FooTests.cs é CRITICA" CRITICA "$(classify)" "teste removido"

# 6. arquivo NOVO (não rastreado) tem as linhas contadas
new_repo novo-grande
seq 1 300 | sed 's/^/linha /' > "$repo/src/A/Big.cs"
expect "arquivo novo de 300 linhas é COMPLEXA" COMPLEXA "$(classify)" "300 linhas"
new_repo novo-medio
seq 1 60 | sed 's/^/linha /' > "$repo/src/A/Mid.cs"
expect "arquivo novo de 60 linhas é SIMPLES" SIMPLES "$(classify)" "60 linhas"

# 7. nome com espaço
new_repo espaco
printf 'a\n' > "$repo/src/A/com espaco.cs"
expect "arquivo com espaço no nome é TRIVIAL e conta 1 arquivo" TRIVIAL "$(classify)"

# 8. caminho crítico tocado
new_repo critico
printf 'a\n' > "$repo/src/Secure/Auth.cs"
expect "tocar src/Secure é CRITICA" CRITICA "$(classify)" "src/Secure/Auth.cs"

# 9. trabalho já commitado, com base explícita
new_repo commitado
printf 'a\n' > "$repo/src/Secure/Auth.cs"; git_in add -A; git_in commit -q -m seguro
expect "base explícita enxerga o commit crítico" CRITICA "$(classify HEAD~1)" "src/Secure/Auth.cs"
expect "sem base explícita o commit já feito não aparece" TRIVIAL "$(classify)"

# 10. modo --paths
new_repo paths
expect "--paths com caminho crítico é CRITICA" CRITICA "$(classify --paths src/Secure/Auth.cs)"
expect "--paths com um arquivo comum é SIMPLES" SIMPLES "$(classify --paths README.md)" "TRIVIAL só se confirma"

# 11. sem configuração
new_repo sem-conf
rm "$repo/.claude/risk.conf"
expect "sem risk.conf é CRITICA" CRITICA "$(classify)" "risk.conf"

# 12. renomeação: o caminho ANTIGO (crítico ou de teste) não pode sumir do diff
new_repo rename-critico
printf 'a\n' > "$repo/src/Secure/Auth.cs"; git_in add -A; git_in commit -q -m seguro
git_in mv src/Secure/Auth.cs docs.cs
expect "mover um arquivo crítico para fora de src/Secure é CRITICA" CRITICA "$(classify)" "src/Secure/Auth.cs"
new_repo rename-teste
git_in mv tests/FooTests.cs misc.cs
expect "mover um teste para fora de tests/ é CRITICA (teste removido)" CRITICA "$(classify)" "teste removido"

# 13. outras convenções de teste
new_repo teste-ts
mkdir -p "$repo/src/web" "$repo/a/test"
printf 'x\n' > "$repo/src/web/x.test.ts"; printf 'x\n' > "$repo/a/test/b.cs"; git_in add -A; git_in commit -q -m ts
rm "$repo/src/web/x.test.ts"
expect "remover x.test.ts é CRITICA" CRITICA "$(classify)" "teste removido"
new_repo teste-pasta
mkdir -p "$repo/a/test"; printf 'x\n' > "$repo/a/test/b.cs"; git_in add -A; git_in commit -q -m pasta
rm "$repo/a/test/b.cs"
expect "remover a/test/b.cs é CRITICA" CRITICA "$(classify)" "teste removido"

# 14. glob complex, domínio duplo e --paths vazio
new_repo complexo
mkdir -p "$repo/src/Complex"; printf 'a\n' > "$repo/src/Complex/W.cs"
expect "tocar src/Complex é COMPLEXA" COMPLEXA "$(classify)" "src/Complex/W.cs"
new_repo dominios
mkdir -p "$repo/src/B"; printf 'a\n' > "$repo/src/A/x.cs"; printf 'a\n' > "$repo/src/B/y.cs"
expect "tocar dois domínios é COMPLEXA" COMPLEXA "$(classify)" "mais de um domínio"
new_repo paths-vazio
expect "--paths sem argumentos é SIMPLES (nada a confirmar)" SIMPLES "$(classify --paths)"

# 15. o nome com espaço e quebra de linha é UM arquivo (e casa o glob crítico)
new_repo nome-estranho
printf 'a\n' > "$repo/src/Secure/com espaco.cs"
expect "nome com espaço em src/Secure é CRITICA" CRITICA "$(classify)" "src/Secure/com espaco.cs"
new_repo quatro-com-espaco
for i in 1 2 3 4; do printf 'a\n' > "$repo/src/A/arq $i.cs"; done
expect "4 arquivos com espaço contam como 4 (não 8)" SIMPLES "$(classify)" "4 arquivos"

# 16. arquivo novo sem newline final conta a última linha; binário novo não conta linhas
new_repo sem-newline
for i in $(seq 1 60); do printf 'linha %s\n' "$i"; done > "$repo/src/A/N.cs"
printf 'ultima' >> "$repo/src/A/N.cs"
expect "arquivo novo de 61 linhas (a última sem newline) é SIMPLES e conta 61" SIMPLES "$(classify)" "61 linhas"
new_repo binario
head -c 20000 /dev/urandom > "$repo/src/A/blob.bin"
expect "binário novo não conta linhas (TRIVIAL)" TRIVIAL "$(classify)"

# 17. `complex`: vale em --paths, em --commit, nunca rebaixa e perde para `critical`
new_repo complex-paths
expect "--paths em src/Complex é COMPLEXA" COMPLEXA "$(classify --paths src/Complex/W.cs)" "src/Complex/W.cs"
new_repo complex-e-critico
mkdir -p "$repo/src/Complex"; printf 'a\n' > "$repo/src/Complex/W.cs"; printf 'a\n' > "$repo/src/Secure/Auth.cs"
expect "complex e critical juntos: vence CRITICA" CRITICA "$(classify)" "src/Secure/Auth.cs"
new_repo complex-commit
mkdir -p "$repo/src/Complex"; printf 'a\n' > "$repo/src/Complex/W.cs"; git_in add -A; git_in commit -q -m complexo
expect "--commit com arquivo em src/Complex é COMPLEXA" COMPLEXA "$(classify --commit HEAD)" "src/Complex/W.cs"
new_repo complex-pequeno
mkdir -p "$repo/src/Complex"; printf 'a\n' > "$repo/src/Complex/W.cs"
expect "complex mesmo com 1 arquivo e 1 linha não é rebaixado" COMPLEXA "$(classify)"
new_repo complex-fora
printf 'a\n' > "$repo/src/A/ok.cs"
refuse "arquivo fora de src/Complex não ganha motivo de complex" "$(classify)" "complexo:"

# 18. staged, modificado e removido que não é teste
new_repo staged
seq 1 60 | sed 's/^/linha /' > "$repo/src/A/S.cs"; git_in add src/A/S.cs
expect "arquivo novo staged de 60 linhas é SIMPLES" SIMPLES "$(classify)" "60 linhas"
new_repo modificado
seq 1 300 | sed 's/^/linha /' > "$repo/src/A/Big.cs"; git_in add -A; git_in commit -q -m big
seq 1 500 | sed 's/^/outra /' > "$repo/src/A/Big.cs"
expect "arquivo rastreado reescrito (300 -> 500 linhas) é COMPLEXA" COMPLEXA "$(classify)" "linhas"

# 19. convenções de teste e nomes parecidos
new_repo teste-spec
mkdir -p "$repo/src/web" "$repo/src/py"
printf 'x\n' > "$repo/src/web/x.spec.ts"; printf 'x\n' > "$repo/src/py/test_foo.py"; printf 'x\n' > "$repo/src/Contest.cs"; printf 'x\n' > "$repo/src/Inspector.cs"
git_in add -A; git_in commit -q -m convencoes
rm "$repo/src/Contest.cs" "$repo/src/Inspector.cs"
refuse "remover Contest.cs e Inspector.cs não conta como teste removido" "$(classify)" "teste removido"
rm "$repo/src/web/x.spec.ts"
expect "remover x.spec.ts é CRITICA" CRITICA "$(classify)" "teste removido"
git_in checkout -q -- src/web/x.spec.ts; rm "$repo/src/py/test_foo.py"
expect "remover test_foo.py é CRITICA" CRITICA "$(classify)" "teste removido"

# 20. `hot`: categoria de benchmark tocada aparece como "quente:" e não muda o nível
new_repo quente
printf 'hot = src/Hot/* -> Pricing\n' >> "$repo/.claude/risk.conf"
mkdir -p "$repo/src/Hot"; printf 'a\n' > "$repo/src/Hot/P.cs"
expect "caminho quente emite 'quente: Pricing' e segue TRIVIAL" TRIVIAL "$(classify)" "quente: Pricing"

echo "== B. bateria do bootstrap 2.8.2 (sinais, falso positivo e falso negativo)"
new_doc_repo() { # new_doc_repo <nome>: configuração com todos os sinais e dois workflows commitados
  repo="$ROOT/$1"
  mkdir -p "$repo/.claude" "$repo/.github/workflows"
  git -C "$repo" init -q -b main
  cat > "$repo/.claude/risk.conf" << 'CONF'
domain = src/*
critical_signal = dependency-lockfile
critical_signal = authentication
critical_signal = authorization
critical_signal = database-migration
critical_signal = infrastructure
critical_signal = secrets
critical_signal = payment
critical_signal = public-api-contract
CONF
  printf 'on: pull_request\njobs:\n  lint:\n    runs-on: ubuntu-latest\n    steps:\n      - run: npm ci && npm run lint && npm test\n' > "$repo/.github/workflows/lint.yml"
  printf 'on: push\njobs:\n  ship:\n    environment: production\n    steps:\n      - uses: azure/webapps-deploy@v3\n' > "$repo/.github/workflows/release.yml"
  git_in add -A; git_in commit -q -m init
}
new_doc_repo doc
check() { # check <esperado: CRITICA|nao> <caminho>
  total=$((total + 1))
  local got; got=$(CLAUDE_PROJECT_DIR=$repo bash "$SCRIPT" --paths "$2" 2> /dev/null | head -1)
  if { [ "$1" = CRITICA ] && [ "$got" != CRITICA ]; } || { [ "$1" = nao ] && [ "$got" = CRITICA ]; }; then
    printf 'FALHOU  esperado=%-8s obtido=%-8s %s\n' "$1" "$got" "$2"; falhas=$((falhas + 1))
  else
    echo "ok: $2 ($1)"
  fi
}
# não podem ser CRITICA
for p in src/Orders/Resilience/RetryPolicy.cs src/Orders/Caching/CacheExpirationPolicy.cs \
  src/Orders/Dtos/OrderSummaryDto.cs src/Orders/Features/ListOrders/ListOrdersResponseDto.cs \
  src/Orders/Validation/OrderJsonSchema.cs src/web/components/ProductPricingCard.svelte \
  src/Orders/Contracts/IOrderRepository.cs src/Orders/Domain/Order.cs src/Orders/Domain/Pricing/PriceCalculator.cs \
  src/Messaging/Subscriptions/OrderCreatedSubscription.cs src/web/lib/schema.ts src/Orders/Infrastructure.Tests/OrderRepoTests.cs \
  src/Orders/Api/AuthorBooksEndpoint.cs src/web/routes/blog/+page.svelte src/Orders/Features/Checkouts.md \
  src/Catalog.API/Infrastructure/CatalogContextSeed.cs src/Ordering.Infrastructure/Repositories/OrderRepository.cs \
  src/WebApp/Components/Pages/Checkout/Checkout.razor.css src/ClientApp/Views/LoginView.xaml src/Billing/README.md .github/workflows/lint.yml; do check nao "$p"; done
# precisam ser CRITICA
for p in src/web/package-lock.json Cargo.lock src/Auth/TokenService.cs src/Identity/Users.cs \
  src/Api/Security/JwtBearerSetup.cs src/web/routes/login/+page.svelte src/Api/Authorization/OrderOwnerHandler.cs \
  src/Api/CanEditOrderAuthorizationHandler.cs src/web/src/app/admin.guard.ts src/Api/Users/PermissionService.cs \
  src/Infrastructure/Migrations/20261101_AddOrders.cs src/Infrastructure/Migrations/AppDbContextModelSnapshot.cs \
  prisma/schema.prisma migrations/0003_add_index.sql infra/main.bicep .github/workflows/deploy.yml .github/workflows/release.yml deploy/app.tf \
  config/secrets.json src/Billing/InvoiceTotals.cs src/Orders/Checkout/CheckoutFlow.cs src/Api/StripePaymentGateway.cs \
  api/openapi.yaml proto/orders.proto src/web/schema.graphql src/Api/PublicAPI.Shipped.txt; do check CRITICA "$p"; done

# falha fechada: git quebrado no meio da coleta não pode virar TRIVIAL
fake="$ROOT/fakebin"; mkdir -p "$fake"; real_git=$(command -v git)
fakegit() { # fakegit <subcomando que falha>
  printf '#!/usr/bin/env bash\n[ "$1" = %s ] && exit 128\nexec "%s" "$@"\n' "$1" "$real_git" > "$fake/git"; chmod +x "$fake/git"
}
for sub in diff ls-files; do
  fakegit "$sub"
  expect "git $sub com erro é CRITICA (falha fechada)" CRITICA "$(PATH="$fake:$PATH" CLAUDE_PROJECT_DIR=$repo bash "$SCRIPT" 2> /dev/null)" "falha ao coletar o diff"
done
fakegit diff-tree
expect "git diff-tree com erro no --commit é CRITICA (falha fechada)" CRITICA "$(PATH="$fake:$PATH" CLAUDE_PROJECT_DIR=$repo bash "$SCRIPT" --commit HEAD 2> /dev/null)" "falha ao coletar o diff"
rm -f "$fake/git"

echo "== C. modo --commit, pipeline de CI lido do arquivo e motivos com nível"
new_doc_repo ci
printf '      - run: npm run build\n' >> "$repo/.github/workflows/lint.yml"
expect "workflow só de teste alterado é COMPLEXA (sem deploy)" COMPLEXA "$(classify)" "COMPLEXA — pipeline de CI sem deploy"
new_doc_repo ci-deploy
printf '      - run: echo ok\n' >> "$repo/.github/workflows/release.yml"
expect "workflow com publicação alterado é CRITICA" CRITICA "$(classify)" "CRITICA — pipeline de CI com deploy ou publicação"
new_doc_repo ci-removido
rm "$repo/.github/workflows/lint.yml"
expect "workflow removido é CRITICA (pode ter removido um gate)" CRITICA "$(classify)" "removido ou ilegível"
new_doc_repo ci-commit
printf '      - run: npm run build\n' >> "$repo/.github/workflows/lint.yml"; git_in add -A; git_in commit -q -m ci
expect "--commit lê o workflow do commit (sem deploy => COMPLEXA)" COMPLEXA "$(classify --commit HEAD)" "pipeline de CI sem deploy"
new_doc_repo ci-commit-deploy
printf '      - run: echo ok\n' >> "$repo/.github/workflows/release.yml"; git_in add -A; git_in commit -q -m ci
expect "--commit lê o workflow do commit (deploy => CRITICA)" CRITICA "$(classify --commit HEAD)" "pipeline de CI com deploy"

new_repo commit-critico
printf 'a\n' > "$repo/src/Secure/Auth.cs"; git_in add -A; git_in commit -q -m seguro
expect "--commit de um commit crítico é CRITICA" CRITICA "$(classify --commit HEAD)" "CRITICA — crítico: src/Secure/Auth.cs"
expect "--commit com sha inexistente é CRITICA" CRITICA "$(classify --commit 0000000000000000000000000000000000000000)" "não encontrado"
expect "--commit do commit raiz é SIMPLES (4 arquivos)" SIMPLES "$(classify --commit HEAD~1)" "4 arquivos"
git_in rm -q tests/FooTests.cs; git_in commit -q -m "remove teste"
expect "--commit que remove teste é CRITICA" CRITICA "$(classify --commit HEAD)" "teste removido"
git_in rm -q src/Latest.cs; git_in commit -q -m "remove Latest"
saida=$(classify --commit HEAD)
refuse "--commit que remove Latest.cs não conta como teste removido" "$saida" "teste removido"
expect "--commit que remove Latest.cs é TRIVIAL" TRIVIAL "$saida"
new_repo commit-grande
seq 1 300 | sed 's/^/linha /' > "$repo/src/A/Big.cs"; git_in add -A; git_in commit -q -m grande
expect "--commit de 300 linhas é COMPLEXA" COMPLEXA "$(classify --commit HEAD)" "300 linhas"
mv "$repo/.claude/risk.conf" "$repo/risk.conf.off"
expect "--commit sem risk.conf é CRITICA" CRITICA "$(classify --commit HEAD)" "risk.conf"

new_repo motivo-nivel
printf 'a\n' > "$repo/src/Secure/Auth.cs"
saida=$(classify)
expect "linha de motivo traz o nível que impõe" CRITICA "$saida" "motivo: CRITICA — crítico: src/Secure/Auth.cs casa com src/Secure/*"

echo
echo "$((total - falhas)) de $total casos passaram"
[ "$falhas" -eq 0 ]
