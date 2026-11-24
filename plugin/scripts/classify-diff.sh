#!/usr/bin/env bash
# Classifica o risco de uma mudança a partir dos arquivos tocados, do tamanho do diff e de .claude/risk.conf.
# Sem configuração, ou sem conseguir ler o diff, o nível é CRITICA: a ausência de dado nunca afrouxa (falha fechada).
# Uso: classify-diff.sh [<base>]            working tree + commits desde <base> (padrão: `base` do risk.conf)
#      classify-diff.sh --paths <caminhos>  caminhos planejados, antes de implementar
#      classify-diff.sh --commit <sha>      um commit do histórico (usado por calibrate-risk.sh)
# Saída: 1ª linha = nível (TRIVIAL | SIMPLES | COMPLEXA | CRITICA); depois "quente: <categoria>" para cada categoria
#        de benchmark tocada (bench-compare.sh) e "motivo: <NÍVEL> — <causa>" para cada motivo.
# Chaves lidas do risk.conf: critical, complex, domain, hot, critical_signal, base, max_files_*, max_lines_*.
#   critical = <glob>   qualquer toque => CRITICA        complex = <glob>   qualquer toque => COMPLEXA
#   domain   = <glob>   mais de um domínio tocado => COMPLEXA
#   critical_signal = dependency-lockfile | authentication | authorization | database-migration | infrastructure
#                     | secrets | payment | public-api-contract   (convenção de pasta e tipo de arquivo; calibrar com
#                     calibrate-risk.sh)
# Sobre a versão 2.8.2 (§6.5): chave `complex`, base padrão HEAD, base inexistente => CRITICA (a 2.8.2 caía em HEAD),
# arquivo novo soma linhas, teste por convenção de caminho e nome.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 1
CONF=".claude/risk.conf"

# Falha fechada: se não der para coletar o diff com confiança, o nível é CRITICA, nunca TRIVIAL.
fail_closed() { echo "CRITICA"; echo "motivo: CRITICA — falha ao coletar o diff ($1); sem dado confiável, tudo é crítico"; exit 0; }
[ -f "$CONF" ] || { echo "CRITICA"; echo "motivo: CRITICA — $CONF ausente; sem configuração, tudo é crítico"; exit 0; }

critical=(); complex=(); domains=(); hot=(); critical_signals=()
base="HEAD"; max_files_trivial=3; max_lines_trivial=50; max_files_simple=5; max_lines_simple=200
while IFS='=' read -r k v; do
  k=$(echo "$k" | tr -d '[:space:]')
  v=$(echo "$v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$k" in
    ''|'#'*) ;;
    critical) critical+=("$v") ;;
    complex) complex+=("$v") ;;
    domain) domains+=("$v") ;;
    hot) hot+=("$v") ;;
    critical_signal) critical_signals+=("$v") ;;
    base) base="$v" ;;
    max_files_trivial) max_files_trivial="$v" ;;
    max_lines_trivial) max_lines_trivial="$v" ;;
    max_files_simple) max_files_simple="$v" ;;
    max_lines_simple) max_lines_simple="$v" ;;
  esac
done < "$CONF"

# O aviso "LF will be replaced by CRLF" do autocrlf é ruído de stderr; erro de verdade continua visível e reprova pelo
# status. Configurado por ambiente (e não por `git -c`) para que cada comando seja invocado como `git diff ...` puro.
_n=${GIT_CONFIG_COUNT:-0}
export "GIT_CONFIG_KEY_${_n}=core.safecrlf" "GIT_CONFIG_VALUE_${_n}=false" "GIT_CONFIG_COUNT=$((_n + 1))"

# Teste por convenção de caminho e nome; "test|spec" solto casaria com Latest, Contest, Inspector.
TEST_RE='(^|/)(tests?|Tests?|__tests__|specs?)/|[._-](test|spec)s?\.[A-Za-z0-9]+$|[a-z0-9]Tests?\.cs$|(^|/)test_[^/]*\.py$|_test\.(go|rs|py)$'

numstat_sum() { awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {a+=$1; r+=$2} END {print a+0, r+0}'; }
dedupe() { # dedupe <arquivo com nomes separados por NUL>: preenche files sem depender de sort -z
  local raw=() f; declare -A seen=(); files=()
  mapfile -d '' -t raw < "$1"
  for f in "${raw[@]}"; do [ -n "$f" ] && [ -z "${seen[$f]:-}" ] && { seen[$f]=1; files+=("$f"); }; done
}
tests_among() { # tests_among <arquivo NUL>: imprime os caminhos que são teste (separados por espaço)
  local raw=() f out=""
  mapfile -d '' -t raw < "$1"
  for f in "${raw[@]}"; do [ -n "$f" ] && [[ "$f" =~ $TEST_RE ]] && out+="$f "; done
  printf '%s' "$out"
}

reasons=(); planned=0; added=0; removed=0; deleted_tests=""; mode="diff"; sha=""
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || fail_closed "não é um repositório git"
lst=$(mktemp "${TMPDIR:-/tmp}/classify-XXXXXX") || fail_closed "mktemp"
lst2=$(mktemp "${TMPDIR:-/tmp}/classify-XXXXXX") || fail_closed "mktemp"
trap 'rm -f "$lst" "$lst2"' EXIT
files=()
if [ "${1:-}" = "--paths" ]; then
  shift
  files=("$@")
  planned=1
elif [ "${1:-}" = "--commit" ]; then
  sha=${2:?uso: classify-diff.sh --commit <sha>}; mode=commit
  git cat-file -e "$sha^{commit}" 2> /dev/null || fail_closed "commit $sha não encontrado"
  dt=(git diff-tree --root --no-commit-id --no-renames -r)
  "${dt[@]}" --name-only -z "$sha" > "$lst" || fail_closed "git diff-tree"
  dedupe "$lst"
  ns=$("${dt[@]}" --numstat "$sha") || fail_closed "git diff-tree --numstat"
  read -r added removed < <(numstat_sum <<< "$ns")
  "${dt[@]}" --name-only --diff-filter=D -z "$sha" > "$lst2" || fail_closed "git diff-tree --diff-filter=D"
  deleted_tests=$(tests_among "$lst2")
else
  ref="${1:-$base}"
  git rev-parse --verify -q "${ref}^{commit}" > /dev/null 2>&1 || fail_closed "base '$ref' inexistente"
  # -z preserva espaços e caracteres especiais; cada comando é checado, sem pipe que esconda erro.
  git diff --no-renames --name-only -z "$ref" > "$lst" || fail_closed "git diff"
  git ls-files --others --exclude-standard -z > "$lst2" || fail_closed "git ls-files"
  mapfile -d '' -t untracked < "$lst2"
  cat "$lst2" >> "$lst"
  dedupe "$lst"
  ns=$(git diff --no-renames --numstat "$ref") || fail_closed "git diff --numstat"
  read -r added removed < <(numstat_sum <<< "$ns")
  git diff --no-renames --name-only --diff-filter=D -z "$ref" > "$lst2" || fail_closed "git diff --diff-filter=D"
  deleted_tests=$(tests_among "$lst2")
  # Arquivo novo (não rastreado) também é linha de código: `git diff --numstat` não o enxerga. `grep -c ''` conta a última
  # linha mesmo sem newline final, e `-I` pula binário (o numstat também conta 0 linhas para binário).
  for f in "${untracked[@]}"; do
    [ -f "$f" ] && added=$((added + $(grep -cI '' -- "$f" || true)))
  done
fi

nfiles=${#files[@]}
lines=$((added + removed))
level="TRIVIAL"
raise() { # raise <nível> <motivo>
  case "$1:$level" in
    CRITICA:*) level="CRITICA" ;;
    COMPLEXA:TRIVIAL|COMPLEXA:SIMPLES) level="COMPLEXA" ;;
    SIMPLES:TRIVIAL) level="SIMPLES" ;;
  esac
  reasons+=("$1 — $2")
}
matches() { # o glob do risk.conf é o padrão, de propósito (sem aspas)
  # shellcheck disable=SC2254
  case "$1" in $2) return 0 ;; esac; return 1
}

# Sinais semânticos: convenções de pasta e de tipo de arquivo, nunca sufixo genérico de classe
# (Policy, Dto, Contract, Schema casam com RetryPolicy, todo DTO, interface de repositório, validação).
# O que for crítico por nome de classe no projeto vai em "critical = <glob>", decidido no bootstrap.
SIG_LOCKFILE='(^|/)(packages\.lock\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|Cargo\.lock|poetry\.lock|uv\.lock|Gemfile\.lock)$'
SIG_AUTHN='(^|/)(auth|authentication|identity|oauth|oidc|sso|login|signin|sign-in)/|(^|/)[^/]*(authentication|authenticator|jwtbearer|passwordhasher)[^/]*$'
SIG_AUTHZ='(^|/)(authorization|permissions?)/|(^|/)[^/]*authoriz[^/]*$|(^|/)[^/]*permissions?(handler|service|requirement|provider|guard|check|policy)[^/]*$|\.guard\.(ts|js)$'
SIG_MIGRATION='(^|/)(migrations?|db/migrate|alembic|flyway)/|(^|/)(schema\.prisma|[^/]*modelsnapshot\.cs)$'
# "Infrastructure/" fica de fora: na Clean Architecture é a camada de persistência, não deploy.
SIG_INFRA='(^|/)(infra|terraform|k8s|kubernetes|helm|deploy)/|\.(tf|bicep)$'
# Pipeline de CI: CRITICA só se publica ou implanta; lint e teste no PR ficam COMPLEXA. Arquivo removido ou
# ilegível conta como CRITICA, porque remover um workflow pode remover um gate.
SIG_CI='(^|/)\.github/workflows/[^/]+\.ya?ml$|(^|/)(azure-pipelines|\.gitlab-ci)\.ya?ml$'
CI_DEPLOY='deploy|publish|release|environment:|kubectl|helm (upgrade|install)|terraform (apply|destroy)|docker (push|buildx .*--push)|push: *true|gh release|npm publish|nuget push|cargo publish|az (webapp|functionapp|containerapp|deployment|acr)|aws (ecs|lambda|s3 (cp|sync)|cloudformation)|gcloud (run|app|functions) deploy|webapps-deploy|deploy-pages'
SIG_SECRETS='(^|/)(secrets?|vault|credentials?)(/|\.|$)'
SIG_PAYMENT='(^|/)(payments?|billing|checkout|invoic(e|es|ing))/|(^|/)[^/]*(payment|billing|invoice|checkout|refund|chargeback)(service|gateway|processor|handler|client|provider|controller|endpoint)[^/]*$'
# Estilo, imagem e texto não carregam risco semântico (lockfile e contrato são checados à parte).
NONCODE='\.(css|scss|sass|less|svg|png|jpe?g|gif|webp|ico|md|mdx)$'
SIG_CONTRACT='(^|/)(openapi|swagger|asyncapi)[^/]*\.(json|ya?ml)$|\.(proto|graphqls?|avsc)$|(^|/)PublicAPI\.(Shipped|Unshipped)\.txt$'

for f in "${files[@]}"; do
  for g in "${critical[@]}"; do
    matches "$f" "$g" && raise CRITICA "crítico: $f casa com $g"
  done
  for g in "${complex[@]}"; do
    matches "$f" "$g" && raise COMPLEXA "complexo: $f casa com $g"
  done
  shopt -s nocasematch
  noncode=0; [[ "$f" =~ $NONCODE ]] && noncode=1
  for signal in "${critical_signals[@]}"; do
    case "$signal" in dependency-lockfile|public-api-contract) ;; *) [ "$noncode" -eq 1 ] && continue ;; esac
    case "$signal" in
      dependency-lockfile) [[ "$f" =~ $SIG_LOCKFILE ]] && raise CRITICA "lockfile alterado: $f" ;;
      authentication) [[ "$f" =~ $SIG_AUTHN ]] && raise CRITICA "sinal de autenticação: $f" ;;
      authorization) [[ "$f" =~ $SIG_AUTHZ ]] && raise CRITICA "sinal de autorização: $f" ;;
      database-migration) [[ "$f" =~ $SIG_MIGRATION ]] && raise CRITICA "sinal de migration: $f" ;;
      infrastructure)
        if [[ "$f" =~ $SIG_CI ]]; then
          if [ "$mode" = commit ]; then ci=$(git show "$sha:$f" 2> /dev/null); else ci=$(cat -- "$f" 2> /dev/null); fi
          if [ -z "$ci" ]; then raise CRITICA "pipeline de CI removido ou ilegível: $f"
          elif grep -Eiq "$CI_DEPLOY" <<< "$ci"; then raise CRITICA "pipeline de CI com deploy ou publicação: $f"
          else raise COMPLEXA "pipeline de CI sem deploy: $f"; fi
        elif [[ "$f" =~ $SIG_INFRA ]]; then raise CRITICA "sinal de infraestrutura/deploy: $f"; fi ;;
      secrets) [[ "$f" =~ $SIG_SECRETS ]] && raise CRITICA "sinal de configuração de segredo: $f" ;;
      payment) [[ "$f" =~ $SIG_PAYMENT ]] && raise CRITICA "sinal financeiro: $f" ;;
      public-api-contract) [[ "$f" =~ $SIG_CONTRACT ]] && raise CRITICA "contrato público: $f" ;;
    esac
  done
  shopt -u nocasematch
done

[ -n "$deleted_tests" ] && raise CRITICA "teste removido: $(printf '%s' "$deleted_tests" | tr ' ' '\n' | head -3 | tr '\n' ' ')"

touched_domains=()
for f in "${files[@]}"; do
  for d in "${domains[@]}"; do
    if matches "$f" "$d"; then
      case " ${touched_domains[*]:-} " in *" $d "*) ;; *) touched_domains+=("$d") ;; esac
    fi
  done
done
[ "${#touched_domains[@]}" -gt 1 ] && raise COMPLEXA "mais de um domínio: ${touched_domains[*]}"

if [ "$nfiles" -gt "$max_files_simple" ]; then raise COMPLEXA "$nfiles arquivos (> $max_files_simple)"
elif [ "$nfiles" -gt "$max_files_trivial" ]; then raise SIMPLES "$nfiles arquivos (> $max_files_trivial)"; fi
if [ "$planned" -eq 0 ]; then
  if [ "$lines" -gt "$max_lines_simple" ]; then raise COMPLEXA "$lines linhas (> $max_lines_simple)"
  elif [ "$lines" -gt "$max_lines_trivial" ]; then raise SIMPLES "$lines linhas (> $max_lines_trivial)"; fi
else
  [ "$level" = "TRIVIAL" ] && raise SIMPLES "classificação por caminhos planejados; TRIVIAL só se confirma no diff real"
fi

hot_cats=()
for f in "${files[@]}"; do
  for h in "${hot[@]}"; do
    g=$(echo "${h%%->*}" | sed 's/[[:space:]]*$//')
    c=$(echo "${h#*->}" | sed 's/^[[:space:]]*//')
    if matches "$f" "$g"; then
      case " ${hot_cats[*]:-} " in *" $c "*) ;; *) hot_cats+=("$c") ;; esac
    fi
  done
done

echo "$level"
[ "${#hot_cats[@]}" -gt 0 ] && printf 'quente: %s\n' "${hot_cats[@]}"
[ "${#reasons[@]}" -gt 0 ] && printf 'motivo: %s\n' "${reasons[@]}"
exit 0
