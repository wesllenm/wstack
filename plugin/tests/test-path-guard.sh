#!/usr/bin/env bash
# Casos do path-guard (hook PreToolUse em Bash, autonomia com trava mínima): pede aprovação só para comando que cita uma
# trava do harness (hooks, settings, risk.conf, scripts, cloud, .mcp.json, .git, .gitignore, workflows) ou um segredo,
# que mostra credencial ou que muda config que executa programa; o resto é livre. Sem rede e sem modelo. Confere também
# que cada glob de Edit do ask e do deny do settings.json modelo cai numa regra do hook: um caminho novo no ask sem regra
# aqui reprova. A prova com o Claude Code real está em prove-write-matrix.sh (custa modelo; roda à mão).
# Os hooks rodam de uma cópia instalada onde o Claude Code instala plugins (<home>/.claude/plugins/cache/...), para que a
# trava dos arquivos do plugin e a liberação dos scripts dele sejam conferidas no caminho real.
# Uso: test-path-guard.sh [<path-guard.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
src=${1:-$here/../hooks/path-guard.sh}
[ -f "$src" ] || { echo "path-guard.sh não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
src=$(cd "$(dirname "$src")" && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-pg-XXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
fails=0
plug=$work/home/.claude/plugins/cache/wstack/wstack/0.0.0
mkdir -p "$plug/scripts" && cp -r "$src" "$plug/hooks"
hook=$plug/hooks/path-guard.sh
proj=$work/projeto
git init -q "$proj" && git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
mkdir -p "$proj/.claude/hooks" "$proj/.claude/skills/x" "$proj/src" "$work/fora"

# REMOTE=true liga o modo nuvem; vazio deixa CLAUDE_CODE_REMOTE ausente, qualquer que seja a do ambiente de quem testa
# (na VM da nuvem ela vale true e livraria as travas do harness em todos os casos do modo local)
verdict() {
  local -a remote=(-u CLAUDE_CODE_REMOTE)
  [ -n "${REMOTE:-}" ] && remote=("CLAUDE_CODE_REMOTE=$REMOTE")
  jq -cn --arg c "$1" --arg d "${VCWD:-$proj}" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' |
    env "${remote[@]}" CLAUDE_PROJECT_DIR=$proj ${PROOT:+CLAUDE_PLUGIN_ROOT=$PROOT} bash "$hook" 2> /dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty' 2> /dev/null
}
expect() { # expect <livre|ask> <comando>
  local got; got=$(verdict "$2"); got=${got:-livre}
  [ "$got" = "$1" ] || { echo "FALHOU: esperado $1, obtido $got: $2 (cwd ${VCWD:-projeto})"; fails=$((fails + 1)); }
}

# rotina do dia a dia e o que deixou de pedir com a autonomia: tudo livre
for c in 'git status --short' 'ls src' 'cp a b' 'npm --prefix web run check' \
  'git add .claude/hooks/path-guard.mjs .claude/settings.json' 'git diff .claude/' \
  'dotnet test tests/App.ArchitectureTests' 'dotnet build App.slnx' 'dotnet run --project src/App.AppHost' \
  'dotnet list App.slnx package --vulnerable --include-transitive' 'grep -rn "dotnet build" ci' \
  'node -e "console.log(process.env.HOME)"' 'gh pr view 3' 'gh pr create --title x --body-file /tmp/x.md' 'git push -u origin fix/x' \
  'docker ps' 'cat .claude/project.md' 'grep -rn foo docs .claude/skills' 'shellcheck .claude/scripts/x.sh' \
  'bash .claude/skills/verify-app/scripts/launch.sh prova' 'cp /tmp/x .claude/skills/lead/SKILL.md' \
  'sed -i s/a/b/ .claude/agents/review-agent.md' 'cp /tmp/x .editorconfig' 'cp /tmp/x Directory.Build.props' \
  'cp /tmp/x tests/X.ArchitectureTests/A.cs' 'npm --prefix web install x' 'git cherry-pick abc' 'git rebase main' \
  'git stash pop' 'git switch outra' 'tar -xzf /tmp/x.tgz' 'cp -r /tmp/stage/. .' 'git worktree add .claude/worktrees/x -b task/x' \
  'git config --get user.name' 'git config --list' 'git switch main' 'git pull --ff-only origin main'; do
  expect livre "$c"
done
expect livre "$(printf '%s\n' "git commit -F - <<'EOF'" 'fix(claude): ajustar .claude/hooks e .env' '' 'corpo' 'EOF')"
# os scripts do plugin, pelo caminho em que ele está instalado, rodando na raiz do projeto
for c in "bash $plug/scripts/classify-diff.sh" "$plug/scripts/classify-diff.sh" "bash $plug/scripts/checkpoint.sh a 1 b" \
  "node $plug/scripts/review-dispatch.mjs --base main" "bash -n $plug/hooks/push-guard.sh"; do
  expect livre "$c"
done
# o projeto não tem mais scripts do harness: um .claude/scripts ou .claude/hooks no projeto é trava como as outras
for c in 'bash .claude/scripts/classify-diff.sh' '.claude/scripts/classify-diff.sh' 'bash .claude/scripts/checkpoint.sh a 1 b' \
  'node .claude/scripts/review-dispatch.mjs --base main' 'bash -n .claude/hooks/push-guard.sh' "bash $proj/.claude/scripts/classify-diff.sh"; do
  expect ask "$c"
done

# travas do harness: pedem, por qualquer programa, também em Windows e com a pasta como cwd
for t in .claude/hooks/push-guard.sh .claude/settings.json .claude/risk.conf .claude/scripts/checkpoint.sh .claude/cloud/setup.sh \
  .mcp.json .gitignore .git/config .github/workflows/ci.yml .claude/settings.local.json "$plug/hooks/push-guard.sh" \
  "$plug/scripts/checkpoint.sh" "$plug/hooks/hooks.json" '~/.claude/plugins/cache/wstack/wstack/0.1.0/hooks/path-guard.mjs' \
  '~/.claude/plugins/known_marketplaces.json' '~/.claude/settings.json'; do
  expect ask "cp /tmp/x $t"
  expect ask "sed -i s/^/x/ $t"
  expect ask "python3 -c \"open('$t','w').write('x')\""
done
expect ask 'copy x .claude\hooks\push-guard.sh'
# segunda revisão: .claude/ com barra no fim e os marcadores que pulam build e testes
for c in 'cd .claude/ && cp /dev/null hooks/push-guard.sh' 'cd .claude/ && sed -i s/ask/allow/ settings.json' \
  'grep -rl ask .claude/ | xargs sed -i s/ask/allow/g' 'find .claude/ -name push-guard.sh -delete' \
  'pushd .claude/ && rm hooks/push-guard.sh' 'touch .claude/.session/checkpoint-ok-abc' \
  'git diff HEAD | sha1sum | cut -d" " -f1 | tee .claude/.verify-ok' 'printf "sessão: x" > .claude/verify-blocked.md'; do
  expect ask "$c"
done
expect livre 'ls .claude/skills/'
expect livre 'echo x > /dev/null; cat .claude/.session/abc.base'
expect ask 'cd .claude && cp a hooks/push-guard.sh'
expect ask 'bash .claude/scripts/checkpoint.sh a 1 b && cp x .claude/hooks/push-guard.sh'
expect ask 'bash .claude/scripts/checkpoint.sh .claude/hooks/x 1 b'
expect ask 'bash .claude/scripts/../hooks/x.sh'
expect ask 'cp /tmp/x ~/.claude.json'
VCWD=$proj/.claude/hooks expect ask 'cp a push-guard.sh'
VCWD=$work/fora expect ask 'bash .claude/scripts/checkpoint.sh a 1 b'
VCWD=$proj/src expect ask 'bash .claude/scripts/checkpoint.sh a 1 b'
VCWD=$proj/.claude/skills/x expect livre 'ls'
VCWD=$work/fora expect livre 'ls'
VCWD=$plug/hooks expect ask 'cp a push-guard.sh'
VCWD=$work/home/.claude/plugins expect ask 'rm -rf cache'

# script do plugin: livre só no começo do comando, pelo caminho da pasta do plugin que roda este hook, e com a pasta do
# comando na raiz do projeto (em outra pasta ele trataria outro repositório); o resto do comando continua conferido
for c in "bash $plug/scripts/classify-diff.sh --paths src/a.cs" "node $plug/scripts/review-dispatch.mjs --base main" \
  "bash -n $plug/hooks/push-guard.sh" "$plug/scripts/classify-diff.sh" "bash $plug/scripts/checkpoint.sh a 1 b"; do
  expect livre "$c"
done
for c in "true; bash $plug/scripts/classify-diff.sh" "true && bash $plug/scripts/classify-diff.sh" \
  "cp x y; node $plug/scripts/review-dispatch.mjs" "bash $plug/scripts/checkpoint.sh a 1 b && cp x $plug/hooks/push-guard.sh" \
  "bash $plug/scripts/checkpoint.sh $plug/hooks/x 1 b" "bash $plug/scripts/../hooks/x.sh" "bash $plug/scripts/x/../../hooks/x.sh" \
  "bash $work/fora/.claude/plugins/cache/wstack/wstack/0.0.0/scripts/classify-diff.sh" "bash $plug/x/scripts/classify-diff.sh" \
  "bash ${plug}x/scripts/classify-diff.sh" "bash $plug/scripts/classify-diff.sh .claude/settings.json" "cp /tmp/x $plug/hooks/push-guard.sh"; do
  expect ask "$c"
done
VCWD=$proj/src expect ask "bash $plug/scripts/checkpoint.sh a 1 b"
VCWD=$work/fora expect ask "bash $plug/scripts/checkpoint.sh a 1 b"

# o plugin fora de .claude/plugins (CLAUDE_CONFIG_DIR em outra pasta): a pasta dele é trava pelo caminho, não pelo nome
plug2=$work/cfgdir/plugins/cache/wstack/wstack/0.0.0
mkdir -p "$plug2/scripts" && cp -r "$src" "$plug2/hooks"
for c in "cp /tmp/x $plug2/hooks/push-guard.mjs" "sed -i s/a/b/ $plug2/hooks/push-guard.mjs" \
  "bash $plug2/scripts/classify-diff.sh; cp x $plug2/hooks/path-guard.mjs" "bash $plug2/scripts/checkpoint.sh $plug2/hooks/x 1 b"; do
  hook=$plug2/hooks/path-guard.sh expect ask "$c"
done
hook=$plug2/hooks/path-guard.sh VCWD=$plug2/hooks expect ask 'cp a b'
hook=$plug2/hooks/path-guard.sh expect livre "bash $plug2/scripts/classify-diff.sh"
hook=$plug2/hooks/path-guard.sh expect livre "cp /tmp/x ${plug2}x/hooks/a.mjs"
# o plugin chamado pela pasta que o Claude Code informa (CLAUDE_PLUGIN_ROOT), aqui um link simbólico para a real
ln -s "$work/cfgdir" "$work/cfglink"
plugl=$work/cfglink/plugins/cache/wstack/wstack/0.0.0
hook=$plug2/hooks/path-guard.sh PROOT=$plugl expect livre "bash $plugl/scripts/classify-diff.sh"
hook=$plug2/hooks/path-guard.sh PROOT=$plugl expect ask "cp /tmp/x $plugl/hooks/push-guard.mjs"
# CLAUDE_PLUGIN_ROOT que não é esta pasta de plugin não libera nada
hook=$plug2/hooks/path-guard.sh PROOT=$work/fora expect ask "bash $work/fora/x.sh; cp x $plug2/hooks/a"

# segredos: o comando mostraria ou publicaria o arquivo por cima do deny de Read, também pelas formas livres do git
for c in 'shellcheck -s bash .env' 'bash -n .claude/scripts/../../.env' 'gh pr edit 3 --body-file .env.local' 'cat certs/api.pfx' \
  'cat ~/.ssh/id_ed25519' 'cat C:/Users/x/.config/gh/hosts.yml' 'cat src/App.App/appsettings.Development.local.json' \
  'git add certs/client.p12' 'git show :certs/client.p12' 'cat ~/.kube/config' 'cat ~/.npmrc' 'cat ~/.claude/.credentials.json' \
  'cat ~/.aws/credentials' 'cat ~/.nuget/NuGet/NuGet.Config' 'cp /tmp/x ~/.gitconfig' 'gh auth token' 'gh auth status -t' \
  'gh auth status --show-token' 'printf x | git credential fill'; do
  expect ask "$c"
done

# config que executa programa sem citar o caminho
for c in 'git config core.hooksPath /tmp/h' 'git config core.fsmonitor "touch /tmp/p; false"' 'git -c x=y config a.b c' \
  'git config --global user.name x' 'gh config set browser /tmp/x.sh' 'gh alias import /tmp/a.yml' 'gh ext install o/r' \
  'gh extensions install o/r' 'gh pr view 3 --web' 'gh pr list -w' 'gh pr view 3 -cw' 'gh browse' '/usr/bin/gh pr view 3 --web' \
  'npm --prefix web config set --location=project x=y' 'if true; then gh browse; fi'; do
  expect ask "$c"
done

# Nuvem (CLAUDE_CODE_REMOTE=true, VM descartável): a trava por texto é contornável (aspas no meio do nome, tee, sed -i), então
# a mera citação de caminho do harness deixa de pedir; push-guard e checkpoint.sh conferem o que sai da VM. Continuam
# pedindo, como no modo local: .git (config e hooks: core.hooksPath executaria código no push com a credencial da VM),
# git config que grava e os demais comandos de config que executam programa, segredos e credenciais.
nuvem() { # nuvem <livre|ask> <comando>
  local got; got=$(REMOTE=true verdict "$2"); got=${got:-livre}
  [ "$got" = "$1" ] || { echo "FALHOU (nuvem): esperado $1, obtido $got: $2 (cwd ${VCWD:-projeto})"; fails=$((fails + 1)); }
}
for t in .claude/hooks/push-guard.sh .claude/settings.json .claude/risk.conf .claude/scripts/checkpoint.sh .claude/cloud/setup.sh \
  .claude/agents/x.md .claude/skills/lead/SKILL.md .claude/.verify-ok .claude/.session/checkpoint-ok-abc .mcp.json .gitignore \
  .github/workflows/ci.yml .claude/; do
  nuvem livre "cp /tmp/x $t"
  nuvem livre "sed -i s/^/x/ $t"
  nuvem livre "tee $t"
  nuvem livre "cat $t"
done
for c in 'cp /dev/null .cl""aude/hooks/pre.sh' 'ls .claude' 'grep -rl ask .claude/ | xargs sed -i s/ask/allow/g' 'find .claude/ -name push-guard.sh -delete' \
  'cd .claude/ && cp a hooks/push-guard.sh' 'pushd .claude/ && rm hooks/push-guard.sh' 'bash .claude/scripts/checkpoint.sh .claude/hooks/x 1 b' \
  'bash .claude/scripts/../hooks/x.sh' 'bash .claude/scripts/checkpoint.sh a 1 b && cp x .claude/hooks/push-guard.sh' \
  "cp /tmp/x $proj/.claude/hooks/push-guard.sh" 'copy x .claude\hooks\push-guard.sh' 'git add .claude/hooks/path-guard.mjs' \
  "cp /tmp/x $plug/hooks/push-guard.sh" "bash $plug/scripts/checkpoint.sh a 1 b && cp x $plug/hooks/push-guard.sh"; do
  nuvem livre "$c"
done
VCWD=$proj/.claude/hooks nuvem livre 'cp a push-guard.sh'
VCWD=$proj/.claude/skills/x nuvem livre 'ls'
VCWD=$proj/.github/workflows nuvem livre 'cp a ci.yml'
VCWD=$work/fora nuvem livre 'bash .claude/scripts/checkpoint.sh a 1 b'
VCWD=$proj/src nuvem livre 'bash .claude/scripts/checkpoint.sh a 1 b'
for c in 'cp /tmp/x .git/config' 'cp /tmp/x .git/hooks/pre-push' 'sed -i s/^/x/ .git/config' 'tee .git/config' 'git --git-dir=.git config x.y z' \
  'cp /tmp/x ./.git/hooks/pre-push' 'cd .git/hooks && cp /tmp/x pre-push' 'git config core.hooksPath /tmp/h' 'git config core.fsmonitor "touch /tmp/p; false"' \
  'git -c x=y config a.b c' 'git config --global user.name x' 'git credential fill' 'gh auth token' 'gh auth status -t' 'gh config set browser /tmp/x.sh' \
  'gh alias import /tmp/a.yml' 'gh ext install o/r' 'gh pr view 3 --web' 'gh browse' 'npm --prefix web config set --location=project x=y' \
  'cp /tmp/x .claude/settings.local.json' 'cat .env' 'cat .env.local' 'cat certs/api.pfx' 'cat server.pem' 'git add certs/client.p12' 'cat ~/.ssh/id_ed25519' \
  'cat ~/.config/gh/hosts.yml' 'cat src/App.App/appsettings.Development.local.json' 'cat ~/.git-credentials' 'cat ~/.npmrc' 'cat ~/.aws/credentials' \
  'cp /tmp/x ~/.claude.json' 'cat ~/.claude/.credentials.json' 'cp /tmp/x ~/.gitconfig' 'git show :certs/client.p12'; do
  nuvem ask "$c"
done
VCWD=$proj/.git/hooks nuvem ask 'cp a pre-push'
VCWD=$proj/.git nuvem ask 'ls'
nuvem livre 'git config --get user.name'
nuvem livre 'git config --list'
nuvem livre 'git status --short'
nuvem livre 'bash .claude/scripts/classify-diff.sh'
nuvem livre "bash $proj/.claude/scripts/classify-diff.sh"
nuvem livre "bash $plug/scripts/classify-diff.sh"
VCWD=$work/fora nuvem livre "bash $plug/scripts/checkpoint.sh a 1 b"
nuvem livre 'git push -u origin fix/x'
nuvem livre "$(printf '%s\n' "git commit -F - <<'EOF'" 'fix(claude): ajustar .claude/hooks e .env' '' 'corpo' 'EOF')"
# qualquer valor diferente de true segue o modo local
for r in false 1 TRUE yes; do
  got=$(REMOTE=$r verdict 'cp /tmp/x .claude/hooks/push-guard.sh'); got=${got:-livre}
  [ "$got" = ask ] || { echo "FALHOU: CLAUDE_CODE_REMOTE=$r deveria seguir o modo local: obtido $got"; fails=$((fails + 1)); }
done

# as formas fechadas livres vêm de allow_module no .claude/risk.conf do projeto (CLAUDE_PROJECT_DIR), e o módulo é carregado
# da pasta dos hooks: uma cópia dos hooks (para pôr módulos quebrados ao lado) e um risk.conf próprio por caso. Um dotnet
# build de projeto dentro de .claude/hooks cita uma trava; só a forma fechada do módulo o libera antes dessa conferência
cfg=$work/cfg; mkdir -p "$cfg" && cp -r "$plug/hooks" "$cfg/hooks"
cfghook=$cfg/hooks/$(basename "$hook")
conf() { local l; : > "$proj/.claude/risk.conf"; for l in "$@"; do printf '%s\n' "$l" >> "$proj/.claude/risk.conf"; done; }
cfgexpect() { hook=$cfghook expect "$@"; }
conf 'allow_module = dotnet'
cfgexpect livre 'dotnet build .claude/hooks/x.csproj'
cfgexpect livre 'dotnet build App.slnx'
conf '# allow_module = dotnet'
cfgexpect ask 'dotnet build .claude/hooks/x.csproj'
cfgexpect livre 'dotnet build App.slnx'
rm -f "$proj/.claude/risk.conf"
cfgexpect ask 'dotnet build .claude/hooks/x.csproj'
# módulo declarado que não carrega (ausente, nome inválido): todo comando pede, nunca exceção nem forma livre
for m in inexistente 'Dotnet' 'dotnet/../x' '../dotnet' 'dotnet x'; do
  conf "allow_module = $m"
  cfgexpect ask 'dotnet build .claude/hooks/x.csproj'
  cfgexpect ask 'ls src'
done
printf 'throw new Error("quebrado");\n' > "$cfg/hooks/quebrado-allow.mjs"
conf 'allow_module = quebrado'
cfgexpect ask 'ls src'
printf 'export const allowed = 1;\n' > "$cfg/hooks/semfuncao-allow.mjs"
conf 'allow_module = semfuncao'
cfgexpect ask 'ls src'
# um módulo quebrado ao lado do válido não libera nada: continua pedindo
conf 'allow_module = dotnet' 'allow_module = inexistente'
cfgexpect ask 'dotnet build .claude/hooks/x.csproj'
rm -f "$proj/.claude/risk.conf"

# cada glob de Edit do ask e do deny do settings.json modelo cai numa regra do hook
settings=$here/../templates/.claude/settings.json
globs=$(jq -r '.permissions.ask[], .permissions.deny[] | select(startswith("Edit(")) | sub("^Edit\\(";"") | sub("\\)$";"")' "$settings")
[ -n "$globs" ] || { echo "FALHOU: nenhum glob de Edit no settings.json"; fails=$((fails + 1)); }
while IFS= read -r g; do
  [ -n "$g" ] || continue
  sample=${g#./}; sample=${sample#\~/}; sample=${sample//\*\*/x}; sample=${sample//\*/x}
  got=$(verdict "cp /tmp/x $sample"); [ "$got" = ask ] || { echo "FALHOU: glob do settings.json sem regra no path-guard: $g (amostra $sample)"; fails=$((fails + 1)); }
done <<< "$globs"

if [ "$fails" -eq 0 ]; then echo "test-path-guard: todos os casos passaram"; exit 0; fi
echo "test-path-guard: $fails falha(s)"
exit 1
