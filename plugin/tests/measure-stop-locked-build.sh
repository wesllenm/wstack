#!/usr/bin/env bash
# Mede se o hook de fim (verify-on-stop) passa com a aplicação do projeto rodando, quando ela trava os arquivos de saída
# do build (no .NET, a aplicação de pé trava o bin/: com o Aspire, o AppHost e os serviços). Roda os comandos
# verify_build e verify_test do .claude/risk.conf como o hook roda (bash -c, na raiz), mede o tempo e procura o erro de
# arquivo em uso (MSB3027, MSB3021, "being used by another process", "The process cannot access the file"). Com o
# erro, e com comandos dotnet build ou dotnet test, roda de novo com --artifacts-path numa pasta temporária, para
# mostrar se a saída separada resolve. Não roda o hook em si (ele grava carimbo e marcadores) nem muda o risk.conf.
# Uso: com a aplicação rodando em outro terminal: measure-stop-locked-build.sh [<pasta do projeto>]
#      APP_PROCESS=<regex> escolhe os processos da aplicação que o script procura (padrão: apphost|dcp|aspire)
# Roda código do projeto (o build e os testes), como o hook de fim.
# Código: 0 mediu, 2 uso errado ou risk.conf sem verify_build e verify_test.
set -uo pipefail

proj=$(cd "${1:-.}" 2> /dev/null && pwd -P) || { echo "pasta do projeto não encontrada: ${1:-.}" >&2; exit 2; }
conf="$proj/.claude/risk.conf"
[ -f "$conf" ] || { echo "sem $conf" >&2; exit 2; }
val() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$conf" | tr -d '\r' | tail -1; }
build=$(val verify_build); test_cmd=$(val verify_test)
[ -n "$build" ] && [ -n "$test_cmd" ] || { echo "o risk.conf não tem verify_build e verify_test" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/wstack-stop-XXXX")
[ -n "${KEEP:-}" ] || trap 'rm -rf "$work"' EXIT
LOCK='MSB3027|MSB3021|being used by another process|sendo usado por outro processo|The process cannot access the file'
app=${APP_PROCESS:-apphost|dcp|aspire}

echo "Projeto: $proj"
if command -v tasklist > /dev/null; then running=$(tasklist 2> /dev/null | grep -Ei "$app" | awk '{print $1}' | sort -u | tr '\n' ' ')
else running=$(ps -eo comm= 2> /dev/null | grep -Ei "$app" | sort -u | tr '\n' ' '); fi
echo "Processos da aplicação ($app): ${running:-nenhum encontrado (suba a aplicação antes, senão a medição não prova nada)}"
echo

run() { # run <rótulo> <comando>: tempo, código e se houve arquivo em uso
  local t0 t1 rc lock=não
  t0=$(date +%s)
  (cd "$proj" && bash -c "$2") > "$work/$1.log" 2>&1; rc=$?
  t1=$(date +%s)
  grep -Eq "$LOCK" "$work/$1.log" && lock=sim
  printf '%-18s código %-3s %4s s   arquivo em uso: %s\n' "$1" "$rc" $((t1 - t0)) "$lock"
  [ "$lock" = não ] || grep -Em 2 "$LOCK" "$work/$1.log" | cut -c1-200 | sed 's/^/    /'
  [ "$rc" = 0 ] || [ "$lock" = sim ] || tail -3 "$work/$1.log" | cut -c1-200 | sed 's/^/    /'
  printf -v "rc_$1" '%s' "$rc"; printf -v "lock_$1" '%s' "$lock"
}

echo "1) Como o hook roda hoje (verify_build e verify_test do risk.conf):"
echo "   build: $build"; echo "   teste: $test_cmd"
run build "$build"
run test "$test_cmd"
echo
if [ "$lock_build" = não ] && [ "$lock_test" = não ]; then
  if [ "$rc_build" = 0 ] && [ "$rc_test" = 0 ]; then echo "Resultado: build e testes passaram sem arquivo em uso; o hook de fim não trava."
  else echo "Resultado: falhou sem arquivo em uso; a causa é outra (ver as linhas acima)."; fi
elif ! grep -Eq 'dotnet (build|test)' <<< "$build $test_cmd"; then
  echo "Resultado: o hook de fim trava por arquivo em uso. Os comandos não são dotnet build/test, então o script não"
  echo "tenta a saída separada: separe a saída do build com a opção da sua ferramenta e meça de novo."
else
  alt="$work/artefatos"
  # --artifacts-path logo depois do subcomando: a saída sai do bin/ e do obj/ do projeto
  addart() { sed -E "s#(dotnet (build|test))( |$)#\1 --artifacts-path \"$alt\"\3#" <<< "$1"; }
  b2=$(addart "$build"); t2=$(addart "$test_cmd")
  echo "2) Com a saída numa pasta temporária (--artifacts-path):"
  echo "   build: $b2"; echo "   teste: $t2"
  run build_sep "$b2"
  run test_sep "$t2"
  echo
  if [ "$lock_build_sep" = não ] && [ "$lock_test_sep" = não ] && [ "$rc_build_sep" = 0 ] && [ "$rc_test_sep" = 0 ]; then
    echo "Resultado: com a aplicação rodando, o hook de fim trava por arquivo em uso, e o --artifacts-path resolve."
    echo "No risk.conf, com uma pasta fixa fora do repositório no lugar de <pasta>:"
    echo "  verify_build = $(sed "s#\"$alt\"#<pasta>#" <<< "$b2")"
    echo "  verify_test = $(sed "s#\"$alt\"#<pasta>#" <<< "$t2")"
  else
    echo "Resultado: com a aplicação rodando, o hook de fim trava, e o --artifacts-path não bastou (ver as linhas acima)."
  fi
fi
[ -z "${KEEP:-}" ] && echo "Para guardar os logs, rode com KEEP=1." || echo "Logs em $work"
