#!/usr/bin/env bash
# Casos do dotnet-allow (hook PreToolUse em Bash que libera dotnet build/test/restore/format/ef só num formato fechado),
# sem rede. Para cada caso liberado, prova diferencial: o texto roda no bash (com extglob, globstar e nullglob) com um
# dotnet falso no PATH que grava os argumentos; o teste reprova se o dotnet recebeu outra coisa que não as palavras do
# texto. Varredura: toda opção que o dotnet instalado lista na ajuda de build, test, restore e format, com um valor que
# seria um arquivo, não pode sair liberada fora da lista de opções do hook.
# Uso: test-dotnet-allow.sh [<dotnet-allow.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

top=$(git rev-parse --show-toplevel 2> /dev/null)
hook=${1:-$top/.claude/hooks/dotnet-allow.sh}
[ -f "$hook" ] || { echo "dotnet-allow.sh não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
hook=$(cd "$(dirname "$hook")" && pwd -P)/$(basename "$hook")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-dna-XXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
fails=0
tmp=$(cd "${TMPDIR:-/tmp}" && pwd -P)
mkdir -p "$work/bin" "$work/cwd" "$work/projeto"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$ARGV_OUT"\n' > "$work/bin/dotnet" && chmod +x "$work/bin/dotnet"
touch "$work/cwd/a.csproj" "$work/cwd/-flp:logfile=x"

verdict() {
  jq -cn --arg c "$1" --arg d "${VCWD:-$work/cwd}" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' |
    CLAUDE_PROJECT_DIR=$work/projeto bash "$hook" 2> /dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null
}
expect() { # expect <allow|none> <comando>
  local got; got=$(verdict "$2"); got=${got:-none}
  if [ "$got" != "$1" ]; then echo "FALHOU: esperado $1, obtido $got: $2"; fails=$((fails + 1)); return; fi
  [ "$1" = allow ] || return 0
  (cd "$work/cwd" && PATH="$work/bin:$PATH" ARGV_OUT="$work/argv" bash -O extglob -O globstar -O nullglob -c "$2" > /dev/null 2>&1)
  local want got_argv
  want=$(printf '%s\n' "$2" | sed -E 's/ +(2>.*|> \/.*|\|.*)$//' | node -e '
    let s = ""; process.stdin.on("data", (c) => (s += c)).on("end", () => {
      const out = []; const re = /"([^"]*)"|(\S+)/g; let m;
      while ((m = re.exec(s.trim()))) out.push(m[1] ?? m[2]);
      process.stdout.write(out.slice(1).join("\n"));
    });')
  got_argv=$(cat "$work/argv" 2> /dev/null); rm -f "$work/argv"
  [ "$got_argv" = "$want" ] || { echo "FALHOU: o dotnet recebeu argumentos diferentes do texto: $2"; fails=$((fails + 1)); }
}

# os comandos do CLAUDE.md e da rotina
expect allow 'dotnet build App.slnx'
expect allow 'dotnet test App.slnx'
expect allow 'dotnet test App.slnx --filter "Category!=Integration&Category!=E2E"'
expect allow 'dotnet test tests/App.ArchitectureTests'
expect allow 'dotnet format App.slnx --verify-no-changes'
expect allow 'dotnet format App.slnx --verify-no-changes --verbosity q'
expect allow 'dotnet build App.slnx -c Release --no-restore --nologo -v q'
expect allow 'dotnet test tests/App.UnitTests --no-build --filter "FullyQualifiedName~Order" 2>&1 | tail -20'
expect allow "dotnet test App.slnx > $tmp/claude-dna-saida.log 2>&1"
expect allow 'dotnet restore App.slnx --locked-mode'
expect allow 'dotnet build'
expect allow 'dotnet ef migrations list --project src/App.App --startup-project src/App.App'
expect allow 'dotnet ef migrations add AddOrderIndex --project src/App.App'
expect allow 'dotnet ef migrations script Initial AddOrderIndex --idempotent --project src/App.App'
expect allow 'dotnet format App.slnx --verify-no-changes --include src/App.App'
expect allow 'dotnet restore App.slnx --force-evaluate'
expect allow 'dotnet test App.slnx --blame-crash'
expect allow 'dotnet test App.slnx --filter "FullyQualifiedName~Outer+Inner"'
expect allow 'dotnet list App.slnx package --vulnerable --include-transitive'
expect allow 'dotnet list package --outdated'
expect none 'dotnet list /tmp/x/t.csproj package'
expect none 'dotnet list App.slnx reference'
expect none 'dotnet list App.slnx package --source x'

# Directory.Build.rsp acrescenta opções por dentro do MSBuild: na pasta do comando, acima dela ou na do projeto, nada
# sai liberado
mkdir -p "$work/rsp/sub/proj" "$work/rsp2/a"
touch "$work/rsp/sub/proj/p.csproj"
echo '-flp:logfile=x' > "$work/rsp/Directory.Build.rsp"
VCWD=$work/rsp/sub expect none 'dotnet build proj/p.csproj'
VCWD=$work/rsp expect none 'dotnet build'
VCWD=$work/rsp/sub expect none 'dotnet list proj/p.csproj package'
echo '-flp:logfile=x' > "$work/rsp2/a/Directory.Build.rsp"
VCWD=$work/rsp2 expect none 'dotnet build a/p.csproj'
VCWD=$work/rsp2 expect none 'dotnet test App.slnx --project a'
VCWD=$work/rsp2 expect allow 'dotnet build'

# opções que gravam arquivo onde o agente quiser, e tudo fora do formato: pedido de permissão normal
expect none 'dotnet build -flp:logfile=.claude/hooks/push-guard.sh'
expect none 'dotnet build App.slnx "-flp:logfile=x;verbosity=diagnostic"'
expect none 'dotnet build -fl -flp:logfile=x'
expect none 'dotnet build -bl:x.binlog'
expect none 'dotnet build -o .claude/hooks'
expect none 'dotnet build -p:OutputPath=.claude/hooks/'
expect none 'dotnet build -p:Inj=x%0Atouch'
expect none 'dotnet build @resp.rsp'
expect none 'dotnet test --logger trx;LogFileName=x'
expect none 'dotnet test --results-directory .claude'
expect none 'dotnet test --diag x.log'
expect none 'dotnet test -- RunConfiguration.ResultsDirectory=x'
expect none 'dotnet format App.slnx --verify-no-changes --report .claude/hooks'
expect none 'dotnet format App.slnx'
expect none 'dotnet ef migrations script -o .claude/hooks/x.sh'
expect none 'dotnet ef migrations add X -o ../x'
expect none 'dotnet ef database update'
expect none 'dotnet build ../outro/x.csproj'
expect none 'dotnet build /tmp/x.csproj'
expect none 'dotnet build -c $X'
expect none 'dotnet build -c Release*'
expect none 'dotnet test --filter "$(id)"'
expect none 'dotnet test --filter "a`id`"'
expect none 'dotnet test --filter Category=Unit'
expect none 'dotnet test App.slnx > docs/x.log 2>&1'
expect none 'dotnet test App.slnx > /tmp/../root/x 2>&1'
expect none 'dotnet test App.slnx > /etc/x 2>&1'
expect none "dotnet test App.slnx > $work/projeto/x.log 2>&1"
expect none 'dotnet test; rm -rf x'
expect none 'cd x && dotnet build'
expect none 'DOTNET_CLI_HOME=x dotnet build'
expect none 'dotnet run --project src/App.AppHost'
expect none "$(printf 'dotnet build\n-o x')"
expect none 'dotnet format App.slnx --verify-no-changes --binarylog .claude/hooks/push-guard.sh'

# varredura: nenhuma opção que o dotnet instalado conhece sai liberada fora da lista do hook
known='^(--verify-no-changes|--include|--force-evaluate|--blame-crash|--no-restore|--no-build|--nologo|--locked-mode|--idempotent|--no-incremental|-c|--configuration|-v|--verbosity|--filter|--project|--startup-project)$'
if command -v dotnet > /dev/null; then
  swept=0
  for sub in build test restore 'format'; do
    for o in $( (cd "$work/cwd" && dotnet $sub -h 2> /dev/null) | grep -oE '(^|[ ,])-{1,2}[A-Za-z][A-Za-z0-9:-]*' | tr -d ' ,' | sort -u); do
      swept=$((swept + 1))
      [[ $o =~ $known ]] && continue
      base="dotnet $sub"; [ "$sub" = format ] && base='dotnet format --verify-no-changes'
      for c in "$base $o" "$base $o x" "$base $o:x" "$base $o=x"; do
        [ "$(verdict "$c")" = allow ] && { echo "FALHOU: opção fora da lista liberada: $c"; fails=$((fails + 1)); }
      done
    done
  done
  [ "$swept" -gt 40 ] || { echo "FALHOU: varredura viu só $swept opções na ajuda do dotnet"; fails=$((fails + 1)); }
fi

if [ "$fails" -eq 0 ]; then echo "test-dotnet-allow: todos os casos passaram"; exit 0; fi
echo "test-dotnet-allow: $fails falha(s)"
exit 1
