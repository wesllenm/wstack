#!/usr/bin/env bash
# Casos do push-guard (hook PreToolUse) e do checkpoint.sh, sem rede: o hook recebe o payload do Claude Code pela
# entrada padrão; o checkpoint roda contra um remoto local (git init --bare).
# Uso: test-push-guard.sh [<push-guard.sh>] [<checkpoint.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
guard=${1:-$here/../hooks/push-guard.sh}
ckpt=${2:-$here/../scripts/checkpoint.sh}
# o hook lê o risk.conf do projeto: cada repositório temporário versiona o modelo do bootstrap no commit base, como um projeto real
fixture=$here/../templates/.claude/risk.conf
[ -f "$guard" ] && [ -f "$ckpt" ] && [ -f "$fixture" ] || { echo "push-guard.sh, checkpoint.sh ou templates/.claude/risk.conf não encontrado" >&2; exit 2; }
guard=$(cd "$(dirname "$guard")" && pwd -P)/$(basename "$guard"); ckpt=$(cd "$(dirname "$ckpt")" && pwd -P)/$(basename "$ckpt")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-pg-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0

payload() { jq -cn --arg c "$1" --arg d "${PAYLOAD_CWD:-}" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}} + (if $d == "" then {} else {cwd:$d} end)'; }
expect() { # expect <ok|ask|deny> <comando>
  local out rc got
  out=$(payload "$2" | bash "$guard" 2> /dev/null); rc=$?
  if [ "$rc" = 2 ]; then got=deny
  elif [ "$rc" = 0 ] && grep -q '"permissionDecision":"ask"' <<< "$out"; then got=ask
  elif [ "$rc" = 0 ] && [ -z "$out" ]; then got=ok
  else got="rc=$rc"; fi
  if [ "$1" = notok ]; then [ "$got" = ask ] || [ "$got" = deny ] || { echo "FALHOU: esperado ask ou deny, obtido $got: $2"; fails=$((fails + 1)); }; return; fi
  [ "$got" = "$1" ] || { echo "FALHOU: esperado $1, obtido $got: $2"; fails=$((fails + 1)); }
  # com um terceiro argumento, o motivo do pedido precisa conter esse texto
  if [ $# -ge 3 ]; then grep -qF -- "$3" <<< "$out" || { echo "FALHOU: o motivo não cita '$3': $out"; fails=$((fails + 1)); }; fi
}

# repositório hermético para os casos de sintaxe: com origin/main e sem mudança em caminho protegido, o veredito não
# depende do repositório em que o teste roda (o push de uma branch que não existe aqui não publica nada)
hermetic="$work/hermetico"
git init -q --bare "$work/hermetico.git" && git init -q "$hermetic" && git -C "$hermetic" remote add origin "$work/hermetico.git"
mkdir -p "$hermetic/.claude" && cp "$fixture" "$hermetic/.claude/risk.conf" && git -C "$hermetic" add .claude/risk.conf
git -C "$hermetic" -c user.name=t -c user.email=t@t commit -q -m base && git -C "$hermetic" push -q origin HEAD:refs/heads/main 2> /dev/null
export PAYLOAD_CWD="$hermetic" CLAUDE_PROJECT_DIR="$hermetic"

# permitidos: forma exata validada
expect ok 'git push -u origin chore/permissoes'
expect ok 'git push -u origin feat/42-login'
expect ok 'git push origin fix/x task/y'
expect ok 'git push -u origin claude/exec-manutencao-aprendizado-pyaaqb'
expect ok 'git push origin abc123:refs/heads/wip/permissoes-1'
expect ok 'git push -u origin chore/a:chore/a'
expect ask 'git status && git push -u origin chore/a'
expect ok 'git -C . push -u origin chore/a'
expect ok 'git push -u origin chore/a 2>&1'
expect ok 'git push -u origin chore/a > /tmp/p.log 2>&1'
expect ok 'git push --dry-run -u origin chore/a'
expect ok 'git push -u origin chore/a &>/dev/null'
expect ok 'git push -u origin chore/a >&2'
expect ok 'git push -u origin chore/a 2>&1 | tail -2'
# branch que a sessão da nuvem impõe (ccr-<id>-<id>, minúsculas e dígitos): mesma forma fechada
expect ok 'git push -u origin ccr-1ad6512c-bpqm1j'
expect ok 'git push -u origin ccr-1ad6512c-bpqm1j 2>&1 | tail -2'
expect ok 'git push -u origin HEAD:ccr-1ad6512c-bpqm1j'
expect ask 'git push -u origin ccr-1ad6512c'
expect ask 'git push -u origin ccr-1ad6512c-bpqm1j-x'
expect ask 'git push -u origin ccr-1AD6512C-bpqm1j'
expect ask 'git push -u origin ccr-1ad6512c-bpqm1j/x'
expect ask 'git push -u origin ccr-1ad.6512c-bpqm1j'
expect ask 'git push -u origin xccr-1ad6512c-bpqm1j'
expect ask 'git push -u origin refs/tags/ccr-1ad6512c-bpqm1j'
expect deny 'git push -u origin ccr-1ad6512c-bpqm1j --force'
expect deny 'git push origin ccr-1ad6512c-bpqm1j:main'
expect deny 'git push origin :ccr-1ad6512c-bpqm1j'
# não são push: texto entre aspas e heredoc são dados
expect ok 'git log -1 --oneline'
expect ok 'grep -n "git push --force" docs/notas.md'
expect ok 'git commit -m "doc: o hook recusa git push origin main"'
expect ok "cat <<'X'
it's a note about push
X"
# perguntam: só o desenvolvedor aprova, mesmo que o allow case
expect ask 'git push -u origin chore/a --force-with-lease'
expect ask 'git push origin release/1.0'
expect ask 'git push origin main/hotfix'
expect ask 'git push'
expect ask 'git push origin'
expect ask 'git push origin HEAD'
expect ask 'git push upstream chore/a'
expect ask 'git push -u /tmp/x chore/x'
expect ask "git push -u origin chore/a #'"
expect ask "git push -u origin \${E}:feat/42-login"
expect ask "git push -u origin \$''\":feat/42-login\""
expect ask 'git push -u origin {,x}:chore/a'
expect ask 'git push -u origin chore/*'
expect ask 'git push -u origin ~/x:chore/a'
expect ask 'git push -u origin chore/a?'
expect ask 'export FOO=1; git push -u origin chore/a'
expect ask 'cd /tmp && git push -u origin chore/a'
expect ask 'source x.sh && git push -u origin chore/a'
expect ask "P=+; git push -u origin \${P}chore/a:chore/a"
expect ask "git push -u origin \$'\\x2b'chore/a:chore/a"
expect ask "git push -u origin chore/x <<'EOF'
it's
EOF"
# recusados: nem com aprovação
expect deny 'git push -u origin chore/a --force'
expect deny 'git push -u origin chore/a -f'
expect deny 'git push -uf origin chore/a'
expect deny 'git push origin +chore/a'
expect deny 'git push origin :chore/a'
expect deny 'git push origin --delete chore/a'
expect deny 'git push origin main'
expect deny 'git push origin chore/a:main'
expect deny 'git push origin refs/heads/master'
expect deny 'git push -u origin HEAD:heads/main'
expect deny 'git push origin chore/a:heads/master'
expect deny 'git push origin heads/main'
expect deny 'git push -u origin chore/a main'
expect deny 'git push --mirror origin'
expect deny 'git push --all origin'
expect deny 'git push --tags origin'
expect deny 'git push --no-verify -u origin chore/a'
expect deny 'git push origin chore/../main'
expect deny 'git status; git push origin main'
expect deny 'true && git push origin main'
expect deny '/usr/bin/git push origin main'
expect deny 'git push origin "main"'
expect deny 'git push -u origin chore/x +HEAD:main #'
expect deny 'git push -u origin chore/a 2>&1 +HEAD:main'
expect deny 'git push -u origin chore/a 2>&1 main'
expect deny 'git push -u origin chore/a &>/dev/null main'
expect deny 'git push -u origin chore/a >&2 --force'
expect deny 'git push -u origin chore/a >|x main'
expect deny 'git push -u origin chore/a 2> /tmp/e.log main'
# gramática do bash que o tokenizador não lê: nunca OK (fechar descritor, substituição de processo)
expect notok 'git push -u origin chore/x 2>&- +HEAD:main'
expect notok 'git push -u origin chore/x <&- :victim'
expect notok 'git push -u origin chore/x >&- --force chore/y'
expect notok 'git push -u origin chore/x 0<&- --delete x'
expect notok 'git push -u origin chore/x > >(cat) +HEAD:main'
expect notok 'git push -u origin chore/x < <(true) :main'
expect notok 'git push -u origin chore/x <> arq main'
# formato fechado: refspec com "-", quebra de linha, redirecionamento para arquivo do repositório
expect notok 'git push -u origin x:chore/victim -fo:chore/victim'
expect notok 'git push -u origin x:chore/gone -do:chore/gone'
expect notok 'git push -u origin chore/x
chore/run'
expect notok "git push -u origin chore/x$(printf '\r')"
expect notok 'git push -u origin chore/x > .git/config'
expect notok 'git push -u origin chore/x 2> .claude/settings.json'
expect notok 'git push -u origin chore/x > /tmp/../root/.bashrc'
expect deny 'GIT_TRACE=1 git push origin chore/a'
expect deny 'GIT_SSH_COMMAND=evil git push -u origin chore/x'
expect deny 'git -c core.sshCommand=evil push -u origin chore/x'
expect deny 'git -c push.default=current push origin main'
expect deny 'if true; then git push --force origin main; fi'
expect deny '{ git push --force origin main; }'
expect deny '! git push origin main'
expect deny 'env git push origin main'
expect deny 'time git push origin main'
expect deny 'command git push origin main'
expect deny "echo \$(git push origin main)"
expect deny "echo \`git push origin main\`"
expect deny "git \\
push --force origin main"

# checkpoint contra remoto local: inclui arquivo novo, respeita .gitignore, não mexe em HEAD/índice/árvore
unset PAYLOAD_CWD CLAUDE_PROJECT_DIR
remote="$work/remote.git"; repo="$work/repo"
git init -q --bare "$remote" && git init -q "$repo" && cd "$repo" || exit 2
git config user.name t && git config user.email t@t && git remote add origin "$remote"
# o push de HEAD para main grava refs/remotes/origin/main, a base de comparação do que o push ou o checkpoint publica
mkdir -p .claude && cp "$fixture" .claude/risk.conf
printf 'a\n' > a.txt && printf '.env\n' > .gitignore && git add -A && git commit -qm base && git push -q origin HEAD:refs/heads/main HEAD:refs/heads/chore/x 2> /dev/null
printf 'mudou\n' >> a.txt && printf 'novo\n' > novo.txt && printf 'segredo\n' > .env
head_before=$(git rev-parse HEAD); status_before=$(git status --porcelain)
out=$(bash "$ckpt" teste 1 "esperando aprovação" 2>&1) || { echo "FALHOU: checkpoint saiu com erro: $out"; fails=$((fails + 1)); }
sha=$(git ls-remote "$remote" refs/heads/wip/teste-1 | cut -f1)
[ -n "$sha" ] || { echo "FALHOU: ref wip/teste-1 não chegou ao remoto"; fails=$((fails + 1)); }
if [ -n "$sha" ]; then
  files=$(git ls-tree -r --name-only "$sha" | tr '\n' ' ')
  [ "$files" = ".claude/risk.conf .gitignore a.txt novo.txt " ] || { echo "FALHOU: árvore do checkpoint: $files"; fails=$((fails + 1)); }
  [ "$(git log -1 --format=%s "$sha")" = "checkpoint: esperando aprovação" ] || { echo "FALHOU: mensagem do checkpoint"; fails=$((fails + 1)); }
fi
[ "$(git rev-parse HEAD)" = "$head_before" ] || { echo "FALHOU: checkpoint mexeu no HEAD"; fails=$((fails + 1)); }
[ "$(git status --porcelain)" = "$status_before" ] || { echo "FALHOU: checkpoint mexeu no índice ou na árvore"; fails=$((fails + 1)); }
bash "$ckpt" teste 1 "de novo" > /dev/null 2>&1 && { echo "FALHOU: checkpoint sobrescreveu uma ref existente"; fails=$((fails + 1)); }
# arquivo com nome de credencial ou conteúdo de segredo recusa o checkpoint (e nada chega ao remoto)
printf 'x\n' > deploy.key
bash "$ckpt" teste 5 "com chave" > /dev/null 2>&1 && { echo "FALHOU: checkpoint enviou arquivo .key"; fails=$((fails + 1)); }
rm -f deploy.key
printf 'token = "ghp_%s"\n' "$(printf 'a%.0s' $(seq 1 36))" > config.txt
bash "$ckpt" teste 6 "com token" > /dev/null 2>&1 && { echo "FALHOU: checkpoint enviou conteúdo com token"; fails=$((fails + 1)); }
rm -f config.txt
[ -z "$(git ls-remote "$remote" refs/heads/wip/teste-5 refs/heads/wip/teste-6)" ] || { echo "FALHOU: ref de checkpoint recusado chegou ao remoto"; fails=$((fails + 1)); }
# mudança em caminho protegido (arquivo novo ou alterado) em relação ao merge-base com origin/main: o checkpoint não publica
# (um workflow alterado numa ref wip/ dispararia o GitHub Actions com segredos), sai com 3 e lista o arquivo
n=10
for p in .claude/hooks/x.sh .github/workflows/x.yml .claude/settings.json .claude/scripts/x.sh .claude/agents/x.md .claude/skills/x/SKILL.md \
  .claude/cloud/setup.sh .claude/risk.conf .claude/settings.local.json .gitattributes .gitmodules .mcp.json; do
  n=$((n + 1)); mkdir -p "$(dirname "$p")"; printf 'x\n' > "$p"
  msg=$(bash "$ckpt" teste "$n" "com protegido" 2>&1); rc=$?
  [ "$rc" != 0 ] || { echo "FALHOU: checkpoint publicou mudança em $p"; fails=$((fails + 1)); }
  grep -qF "checkpoint com mudança protegida" <<< "$msg" && grep -qF -- "$p" <<< "$msg" || { echo "FALHOU: a recusa não cita o arquivo $p: $msg"; fails=$((fails + 1)); }
  [ -z "$(git ls-remote "$remote" "refs/heads/wip/teste-$n")" ] || { echo "FALHOU: ref com $p chegou ao remoto"; fails=$((fails + 1)); }
  rm -f "$p"; cp "$fixture" .claude/risk.conf # o risk.conf versionado volta como estava (o caso dele o alterou)
done
rm -rf .claude .github ci .devcontainer && mkdir -p .claude && cp "$fixture" .claude/risk.conf
# o que não é protegido segue livre: src, docs, e nomes parecidos fora da raiz protegida
mkdir -p src/ci docs .claude && printf 'x\n' > src/ci/a.cs && printf 'x\n' > docs/a.md && printf 'x\n' > cix.txt && printf 'x\n' > .claude/project.md
bash "$ckpt" teste 30 "sem protegido" > /dev/null 2>&1 || { echo "FALHOU: checkpoint recusou mudança só em src, docs e .claude/project.md"; fails=$((fails + 1)); }
[ -n "$(git ls-remote "$remote" refs/heads/wip/teste-30)" ] || { echo "FALHOU: checkpoint sem protegido não chegou ao remoto"; fails=$((fails + 1)); }
rm -rf src docs .claude cix.txt && mkdir -p .claude && cp "$fixture" .claude/risk.conf
# sem origin/main não dá para saber o que o push publica: falha fechada, o checkpoint não publica
main_sha=$(git rev-parse refs/remotes/origin/main) && git update-ref -d refs/remotes/origin/main
msg=$(bash "$ckpt" teste 31 "sem origin main" 2>&1) && { echo "FALHOU: checkpoint publicou sem origin/main"; fails=$((fails + 1)); }
grep -qF "origin/main" <<< "$msg" || { echo "FALHOU: a recusa sem origin/main não diz o motivo: $msg"; fails=$((fails + 1)); }
[ -z "$(git ls-remote "$remote" refs/heads/wip/teste-31)" ] || { echo "FALHOU: ref sem origin/main chegou ao remoto"; fails=$((fails + 1)); }
git update-ref refs/remotes/origin/main "$main_sha"
# validação dos argumentos sai com 2 (uso errado), antes de qualquer git (o git recusaria parte deles com 3)
for bad in 'Teste' '../main' 'a;b' ''; do
  bash "$ckpt" "$bad" 2 motivo > /dev/null 2>&1; [ $? = 2 ] || { echo "FALHOU: atividade aceita: $bad"; fails=$((fails + 1)); }
done
bash "$ckpt" teste x motivo > /dev/null 2>&1; [ $? = 2 ] || { echo "FALHOU: n não numérico aceito"; fails=$((fails + 1)); }
bash "$ckpt" teste 3 "$(printf 'a\nb')" > /dev/null 2>&1; [ $? = 2 ] || { echo "FALHOU: motivo com quebra de linha aceito"; fails=$((fails + 1)); }

# o destino real vem da configuração: pushurl (ou insteadOf, sshCommand) no .git/config faz o push pedir aprovação
export CLAUDE_PROJECT_DIR="$repo"
expect ok "git -C $repo push -u origin chore/x"
# repositório aninhado com outro origin, ou com transporte ext::, não é o origin do projeto
fake="$work/fake"; git init -q "$fake" && git -C "$fake" remote add origin "$work/outro.git"
expect ask "git -C $fake push -u origin chore/x"
git -C "$fake" remote set-url origin 'ext::sh -c touch% /tmp/pwned'
expect ask "git -C $fake push -u origin chore/x"
# -C relativo vale a partir do cwd do payload (onde o git vai rodar), não da pasta em que o hook roda
PAYLOAD_CWD="$fake" expect ask 'git -C . push -u origin chore/x'
PAYLOAD_CWD="$work" expect ask 'git -C fake push -u origin chore/x'
PAYLOAD_CWD="$work" expect ok 'git -C repo push -u origin chore/x'
cd "$fake" || exit 2
PAYLOAD_CWD="$repo" expect ok 'git -C . push -u origin chore/x'
cd "$repo" || exit 2
CLAUDE_PROJECT_DIR="$fake" expect ask "git -C $fake push -u origin chore/x"
git -C "$repo" config remote.origin.pushurl "$work/outro.git"
expect ask "git -C $repo push -u origin chore/x"
git -C "$repo" config --unset remote.origin.pushurl
git -C "$repo" config url."$work/outro.git".pushInsteadOf "$remote"
expect ask "git -C $repo push -u origin chore/x"
git -C "$repo" config --remove-section url."$work/outro.git"
git -C "$repo" config remote.origin.push refs/heads/chore/x:refs/heads/main
expect ask "git -C $repo push -u origin chore/x"
git -C "$repo" config --unset remote.origin.push
# o origin com mais de uma url empurra para todas: só a primeira igual à do projeto não basta (no projeto ou num aninhado)
git -C "$repo" config --add remote.origin.url "$work/outro.git"
expect ask "git -C $repo push -u origin chore/x"
CLAUDE_PROJECT_DIR='' expect ask "git -C $repo push -u origin chore/x"
git -C "$repo" config --unset remote.origin.url "$work/outro.git"
expect ok "git -C $repo push -u origin chore/x"
nested="$repo/sub"; git init -q "$nested" && git -C "$nested" remote add origin "$remote"
git -C "$nested" config --add remote.origin.url "$work/outro.git"
expect ask "git -C $nested push -u origin chore/x"
PAYLOAD_CWD="$nested" expect ask 'git push -u origin chore/x'
# repositório aninhado com a mesma url do projeto continua sendo outro repositório (config própria, credential.helper...)
git -C "$nested" config --unset remote.origin.url "$work/outro.git"
expect ask "git -C $nested push -u origin chore/x"
PAYLOAD_CWD="$nested" expect ask 'git push -u origin chore/x'
rm -rf -- "${nested:?}"
# worktree do projeto compartilha o repositório: continua liberada, dentro ou fora do projeto
git -C "$repo" worktree add -q "$repo/wt" -b chore/wt1 2> /dev/null
git -C "$repo" worktree add -q "$work/wt-fora" -b chore/wt2 2> /dev/null
expect ok "git -C $repo/wt push -u origin chore/wt1"
PAYLOAD_CWD="$work/wt-fora" expect ok 'git push -u origin chore/wt2'
# worktree com config própria (extensions.worktreeConfig): a url dela se soma à do projeto, e o push iria para as duas
git -C "$repo" config extensions.worktreeConfig true && git -C "$repo/wt" config --worktree remote.origin.url "$work/outro.git"
expect ask "git -C $repo/wt push -u origin chore/wt1"
git -C "$repo/wt" config --worktree --unset remote.origin.url && git -C "$repo" config --unset extensions.worktreeConfig
# worktree falsa gravada só com arquivos (commondir apontando para o .git do projeto): mesmo repositório comum, mas a pasta
# git é dela, e com worktreeConfig o git lê o config.worktree dela (credential.helper que executa comando)
fakewt="$repo/fakewt"; mkdir -p "$fakewt/.git"
printf 'ref: refs/heads/chore/x\n' > "$fakewt/.git/HEAD" && printf '../../.git\n' > "$fakewt/.git/commondir"
printf '[credential]\n\thelper = !touch %s/pwned\n' "$work" > "$fakewt/.git/config.worktree"
PAYLOAD_CWD="$fakewt" expect ask 'git push -u origin chore/x'
git -C "$repo" config extensions.worktreeConfig true
PAYLOAD_CWD="$fakewt" expect ask 'git push -u origin chore/x'
expect ask "git -C $fakewt push -u origin chore/x"
git -C "$repo" config --unset extensions.worktreeConfig && rm -rf -- "${fakewt:?}"
# git anterior ao 2.31 ecoa a opção --path-format desconhecida e devolve caminho relativo: o hook não pode comparar isso
nested="$repo/sub"; git init -q "$nested" && git -C "$nested" remote add origin "$remote"
mkdir -p "$work/oldgit" && real_git=$(command -v git)
printf '#!/usr/bin/env bash\nif [ "$1 $2 $3" = "-C %s rev-parse" ] || [[ " $* " = *" rev-parse --path-format=absolute "* ]]; then\n  a=(); for x in "$@"; do [ "$x" = --path-format=absolute ] && { echo "$x"; continue; }; a+=("$x"); done; exec %s "${a[@]}"\nfi\nexec %s "$@"\n' "$nested" "$real_git" "$real_git" > "$work/oldgit/git"
chmod +x "$work/oldgit/git"
PATH="$work/oldgit:$PATH" PAYLOAD_CWD="$nested" expect ask 'git push -u origin chore/x'
PATH="$work/oldgit:$PATH" expect ask "git -C $nested push -u origin chore/x"
# git lento num repositório aninhado: o hook morto pelo timeout do settings.json (10 s) deixaria o push passar; ele precisa
# terminar antes, com ASK (prazo total, não só por chamada)
printf '#!/usr/bin/env bash\n[[ " $* " = *" %s "* ]] && sleep 2.5\nexec %s "$@"\n' "$nested" "$real_git" > "$work/oldgit/git"
t0=$(date +%s); PATH="$work/oldgit:$PATH" expect ask "git -C $nested push -u origin chore/x"; t1=$(date +%s)
[ $((t1 - t0)) -lt 9 ] || { echo "FALHOU: o hook levou $((t1 - t0)) s com git lento (o limite do settings.json é 10 s)"; fails=$((fails + 1)); }
rm -rf -- "${nested:?}"
git -C "$repo" worktree remove "$repo/wt" && git -C "$repo" worktree remove "$work/wt-fora"

# sessão aberta numa worktree: a referência do projeto só vale se a pasta git for uma worktree registrada cujo elo de
# volta (<comum>/worktrees/<n>/gitdir, gravado pelo git) aponta para o .git da sessão; um .git arquivo reescrito não basta
git -C "$repo" worktree add -q "$work/wt-ok" -b chore/wtok 2> /dev/null
CLAUDE_PROJECT_DIR="$work/wt-ok" PAYLOAD_CWD="$work/wt-ok" expect ok 'git push -u origin chore/wtok'
forged="$work/wt-ok/evilgd"; mkdir -p "$forged/refs/heads/chore" "$forged/objects/info"
printf 'ref: refs/heads/chore/wtok\n' > "$forged/HEAD"
printf '%s\n' "$repo/.git/objects" > "$forged/objects/info/alternates"
git -C "$repo" rev-parse chore/wtok > "$forged/refs/heads/chore/wtok"
printf '[core]\n\trepositoryformatversion = 0\n[remote "origin"]\n\turl = %s\n' "$work/outro.git" > "$forged/config"
saved=$(cat "$work/wt-ok/.git"); printf 'gitdir: %s\n' "$forged" > "$work/wt-ok/.git"
CLAUDE_PROJECT_DIR="$work/wt-ok" PAYLOAD_CWD="$work/wt-ok" expect ask 'git push -u origin chore/wtok'
# com commondir para o repositório do projeto (e a url do projeto): o mesmo repositório comum, mas não é worktree registrada
printf '[remote "origin"]\n\turl = %s\n' "$remote" > "$forged/config" && printf '%s\n' "$repo/.git" > "$forged/commondir"
CLAUDE_PROJECT_DIR="$work/wt-ok" PAYLOAD_CWD="$work/wt-ok" expect ask 'git push -u origin chore/wtok'
# ...mesmo com um elo de volta forjado dentro dela apontando para a worktree
printf '%s/wt-ok/.git\n' "$work" > "$forged/gitdir"
CLAUDE_PROJECT_DIR="$work/wt-ok" PAYLOAD_CWD="$work/wt-ok" expect ask 'git push -u origin chore/wtok'
# pasta forjada dentro de <comum>/worktrees (simula o que só o git grava): o elo de volta não aponta para a worktree
fake_wt="$repo/.git/worktrees/forjada"; mkdir -p "$fake_wt"
cp "$forged/HEAD" "$fake_wt/HEAD" && printf '../..\n' > "$fake_wt/commondir" && printf '%s/outra/.git\n' "$work" > "$fake_wt/gitdir"
printf 'gitdir: %s\n' "$fake_wt" > "$work/wt-ok/.git"
CLAUDE_PROJECT_DIR="$work/wt-ok" PAYLOAD_CWD="$work/wt-ok" expect ask 'git push -u origin chore/wtok'
rm -rf -- "${fake_wt:?}" "${forged:?}"; printf '%s\n' "$saved" > "$work/wt-ok/.git"
CLAUDE_PROJECT_DIR="$work/wt-ok" PAYLOAD_CWD="$work/wt-ok" expect ok 'git push -u origin chore/wtok'
git -C "$repo" worktree remove "$work/wt-ok"

# o push que publica mudança em caminho protegido (merge-base com origin/main até a ponta) pede aprovação, com a lista;
# sem mudança protegida segue como antes; sem origin/main ou sem merge-base, falha fechada
mkbranch() { # [BASE=<ref>] mkbranch <repo> <branch> <arquivo>...: branch com um commit sobre a base (HEAD), sem mexer na árvore nem no índice
  local r=$1 b=$2 f blob tree c base=${BASE:-HEAD}; shift 2
  local idx; idx=$(mktemp "$work/idx-XXXX"); rm -f "$idx"
  GIT_INDEX_FILE="$idx" git -C "$r" read-tree "$base"
  for f in "$@"; do
    blob=$(printf 'x\n' | git -C "$r" hash-object -w --stdin)
    GIT_INDEX_FILE="$idx" git -C "$r" update-index --add --cacheinfo "100644,$blob,$f"
  done
  tree=$(GIT_INDEX_FILE="$idx" git -C "$r" write-tree)
  c=$(git -C "$r" -c user.name=t -c user.email=t@t commit-tree "$tree" -p "$base" -m "$b")
  git -C "$r" update-ref "refs/heads/$b" "$c"; rm -f "$idx"
}
i=0
for p in .claude/hooks/x.sh .github/workflows/x.yml .claude/settings.json .claude/scripts/x.sh .claude/agents/x.md .claude/skills/x/SKILL.md \
  .claude/cloud/setup.sh .claude/risk.conf .claude/settings.local.json .gitattributes .gitmodules .mcp.json sub/.gitattributes \
  .gitignore sub/.gitignore; do
  i=$((i + 1)); mkbranch "$repo" "chore/prot$i" src/ok.cs "$p"
  expect ask "git -C $repo push -u origin chore/prot$i" "caminho protegido: $p"
done
# a lista traz só os protegidos; a origem pode ser refs/heads/<branch>, origem:destino ou o sha de uma ref wip/
mkbranch "$repo" chore/mix src/a.cs docs/b.md ci/z.sh .github/workflows/w.yml
expect ask "git -C $repo push -u origin chore/mix" '.github/workflows/w.yml'
expect ask "git -C $repo push -u origin refs/heads/chore/mix"
expect ask "git -C $repo push -u origin chore/mix:chore/outro"
expect ask "git -C $repo push origin chore/mix:refs/heads/wip/mix-1"
expect ask "git -C $repo push origin $(git -C "$repo" rev-parse chore/mix):refs/heads/wip/mix-2"
expect ask "git -C $repo push -u origin chore/prot1 chore/ok0" 'caminho protegido'
# barra + quebra de linha: o bash junta antes de ler, então é o mesmo push fora do formato fechado; pede (nunca OK sem
# conferir o que publica), com push inteiro ou partido; sem push, a continuação segue livre
expect ask "git -C $repo "$'\\\n'"push -u origin chore/prot2" 'barra no fim de linha'
expect ask "git -C $repo pu"$'\\\n'"sh -u origin chore/prot2" 'barra no fim de linha'
expect ask "git -C $repo "$'\\\r\n'"push -u origin chore/prot2" 'barra no fim de linha'
expect ok "git -C $repo "$'\\\n'"status"
# só src, docs e nomes parecidos fora da raiz protegida: livre
mkbranch "$repo" chore/seguro src/a.cs docs/b.md src/ci/x.cs cix/y.txt .claude/project.md src/.claude/hooks/x docs/.github/x.yml .github-x/y
expect ok "git -C $repo push -u origin chore/seguro"
expect ok "git -C $repo push origin chore/seguro:refs/heads/wip/seguro-1"
expect ok "git -C $repo push -u origin chore/seguro chore/seguro:chore/seguro2"
# mudança protegida que já está na origin/main não conta (merge-base): o push de uma branch com a main atual segue livre
git -C "$repo" update-ref refs/remotes/origin/main "$(git -C "$repo" rev-parse chore/mix)"
BASE=chore/mix mkbranch "$repo" chore/depois src/c.cs
expect ok "git -C $repo push -u origin chore/depois"
git -C "$repo" update-ref refs/remotes/origin/main "$main_sha"
# branch que não existe localmente: o git recusa o push, nada é publicado
expect ok "git -C $repo push -u origin chore/inexistente"
# sem origin/main: não dá para saber o que o push publica, falha fechada (mesmo com mudança só em src)
git -C "$repo" update-ref -d refs/remotes/origin/main
expect ask "git -C $repo push -u origin chore/seguro" 'origin/main'
expect ask "git -C $repo push -u origin chore/prot1"
git -C "$repo" update-ref refs/remotes/origin/main "$main_sha"
expect ok "git -C $repo push -u origin chore/seguro"
# sem ancestral comum com a origin/main (histórico sem relação): falha fechada
orphan=$(git -C "$repo" commit-tree "$(git -C "$repo" rev-parse chore/seguro^{tree})" -m orfa) && git -C "$repo" update-ref refs/heads/chore/orfa "$orphan"
expect ask "git -C $repo push -u origin chore/orfa" 'merge-base'

# configuração que troca o destino de um refspec sem ":" ou junta refs ao push: push.default upstream/tracking manda
# "x" para o branch.x.merge (a main, se a branch rastreia a main); push.followTags publica tag anotada de commit
# intermediário; push.recurseSubmodules empurra submódulos. simple e current não desviam
git -C "$repo" config branch.chore/seguro.merge refs/heads/main
for v in upstream tracking; do
  git -C "$repo" config push.default "$v"
  expect ask "git -C $repo push -u origin chore/seguro" 'push.default'
done
for v in simple current; do
  git -C "$repo" config push.default "$v"
  expect ok "git -C $repo push -u origin chore/seguro"
done
git -C "$repo" config --unset push.default; git -C "$repo" config --unset branch.chore/seguro.merge
git -C "$repo" config push.followTags true
expect ask "git -C $repo push -u origin chore/seguro" 'push.followtags'
git -C "$repo" config push.followTags false
expect ok "git -C $repo push -u origin chore/seguro"
git -C "$repo" config --unset push.followTags
git -C "$repo" config push.recurseSubmodules on-demand
expect ask "git -C $repo push -u origin chore/seguro" 'push.recursesubmodules'
git -C "$repo" config push.recurseSubmodules check
expect ok "git -C $repo push -u origin chore/seguro"
git -C "$repo" config --unset push.recurseSubmodules
expect ok "git -C $repo push -u origin chore/seguro"

# a origem do refspec: o rev-parse lê primeiro o pseudo-ref .git/<nome> (FETCH_HEAD, ORIG_HEAD) e trata 40 hex como objeto,
# mas o git push casa a origem entre as refs locais (refs/<nome>, refs/tags/<nome>, refs/heads/<nome>, refs/remotes/<nome>,
# refs/remotes/<nome>/HEAD) e publica essa. O veredito precisa cobrir as duas leituras, e nome ambíguo falha fechado
mkbranch "$repo" chore/evil src/ok.cs .github/workflows/x.yml
evil=$(git -C "$repo" rev-parse chore/evil); clean=$(git -C "$repo" rev-parse chore/seguro)
git -C "$repo" update-ref -d refs/heads/chore/evil
for x in FETCH_HEAD ORIG_HEAD "$clean"; do
  git -C "$repo" update-ref "refs/heads/$x" "$evil"
  printf '%s\n' "$clean" > "$repo/.git/$x" # pseudo-ref (ou, para o sha, um arquivo inócuo) num commit limpo
  expect ask "git -C $repo push -u origin chore/ok $x:chore/y" 'caminho protegido: .github/workflows/x.yml'
  expect ask "git -C $repo push -u origin $x:chore/y" 'caminho protegido: .github/workflows/x.yml'
  git -C "$repo" update-ref -d "refs/heads/$x"
  rm -f "$repo/.git/$x"
done
# a mesma origem nos outros espaços de nome que o push casa: refs/<nome>, refs/tags/<nome>, refs/remotes/<nome>(/HEAD)
git -C "$repo" update-ref refs/heads/feat/q "$clean"
for r in refs/feat/q refs/tags/feat/q refs/remotes/feat/q refs/remotes/feat/q/HEAD; do
  git -C "$repo" update-ref "$r" "$evil"
  expect ask "git -C $repo push -u origin chore/ok feat/q:chore/y" 'caminho protegido: .github/workflows/x.yml'
  git -C "$repo" update-ref -d "$r"
done
git -C "$repo" update-ref -d refs/heads/feat/q
# nome em mais de um espaço de nome é ambíguo mesmo com tudo limpo (o git push recusa com "matches more than one", observado
# no git 2.43; o hook pergunta antes), e pseudo-ref ou hex curto que também existe como ref idem
git -C "$repo" update-ref refs/heads/chore/dup "$clean" && git -C "$repo" update-ref refs/tags/chore/dup "$clean"
expect ask "git -C $repo push -u origin chore/dup:chore/y" 'ambígu'
git -C "$repo" update-ref -d refs/heads/chore/dup && git -C "$repo" update-ref -d refs/tags/chore/dup
git -C "$repo" update-ref refs/heads/HEAD "$clean"
expect ask "git -C $repo push -u origin HEAD:chore/y" 'ambígu'
git -C "$repo" update-ref -d refs/heads/HEAD
git -C "$repo" update-ref "refs/heads/${clean:0:7}" "$clean"
expect ask "git -C $repo push -u origin ${clean:0:7}:chore/y" 'ambígu'
git -C "$repo" update-ref -d "refs/heads/${clean:0:7}"
# o caso comum segue livre: branch normal, HEAD sem ref homônima, sha cru sem ref homônima, refs/heads/<branch>
expect ok "git -C $repo push -u origin chore/seguro:chore/y"
expect ok "git -C $repo push -u origin refs/heads/chore/seguro:chore/y"
expect ok "git -C $repo push -u origin HEAD:chore/y"
expect ok "git -C $repo push origin $clean:refs/heads/wip/limpo-1"
# destino curto herda o tipo da origem: com origem tag o git cria refs/tags/<destino> no remoto. Pede, com ou sem ":",
# por nome curto ou qualificado; destino qualificado em refs/heads/ cria branch a partir da tag e segue livre
git -C "$repo" update-ref refs/tags/v1 "$clean" && git -C "$repo" update-ref refs/tags/v2 "$clean" && git -C "$repo" update-ref refs/tags/feat/soltag "$clean"
expect ask "git -C $repo push origin v1:feat/x" 'criaria uma tag'
expect ask "git -C $repo push -u origin refs/tags/v2:fix/y" 'criaria uma tag'
expect ask "git -C $repo push -u origin feat/soltag" 'criaria uma tag'
expect ask "git -C $repo push -u origin v1:ccr-1ad6512c-bpqm1j" 'criaria uma tag'
expect ask "git -C $repo push -u origin chore/seguro v1:chore/y" 'criaria uma tag'
expect ok "git -C $repo push -u origin v1:refs/heads/feat/y"
expect ok "git -C $repo push -u origin chore/seguro"
# a tag pode apontar para árvore ou blob (não há commit a conferir) e a branch pode ser symref para uma tag: o tipo é o que
# o git resolve para a origem, como ele faz ao completar o destino curto
git -C "$repo" update-ref refs/tags/feat/soltree "$(git -C "$repo" rev-parse "$clean^{tree}")"
git -C "$repo" update-ref refs/tags/feat/solblob "$(printf 'x\n' | git -C "$repo" hash-object -w --stdin)"
git -C "$repo" symbolic-ref refs/heads/feat/link refs/tags/v1
expect ask "git -C $repo push -u origin feat/soltree" 'criaria uma tag'
expect ask "git -C $repo push -u origin feat/solblob:feat/z" 'criaria uma tag'
expect ask "git -C $repo push -u origin feat/link:feat/l1" 'criaria uma tag'
git -C "$repo" update-ref -d refs/tags/feat/soltree && git -C "$repo" update-ref -d refs/tags/feat/solblob
git -C "$repo" update-ref --no-deref -d refs/heads/feat/link
# nome que o rev-parse não resolve (pseudo-ref .git/<nome> e tag no mesmo commit: ele imprime vazio) com a origem
# existente: o tipo é desconhecido e pede
git -C "$repo" update-ref refs/tags/feat/amb "$clean" && git -C "$repo" update-ref feat/amb "$clean"
expect ask "git -C $repo push -u origin feat/amb" 'tipo da origem'
expect ask "git -C $repo push -u origin chore/seguro feat/amb:feat/z" 'tipo da origem'
git -C "$repo" update-ref -d refs/tags/feat/amb && git -C "$repo" update-ref -d feat/amb
head=$(git -C "$repo" symbolic-ref HEAD) && git -C "$repo" symbolic-ref HEAD refs/tags/v1
expect ask "git -C $repo push -u origin HEAD:feat/h" 'criaria uma tag'
git -C "$repo" symbolic-ref HEAD "$head"
git -C "$repo" update-ref -d refs/tags/v1 && git -C "$repo" update-ref -d refs/tags/v2 && git -C "$repo" update-ref -d refs/tags/feat/soltag

# prefixos de atividade, branch padrão e caminhos protegidos extras vêm do .claude/risk.conf do projeto
# (CLAUDE_PROJECT_DIR, aqui o $repo): um risk.conf próprio por caso, na árvore dele (o push confere commits, não a árvore)
cfg="$repo/.claude"; mkdir -p "$cfg"
cfgguard="$guard"
conf() { local l; : > "$cfg/risk.conf"; for l in "$@"; do printf '%s%b' "$l" "${EOL:-\n}" >> "$cfg/risk.conf"; done; }
cfgexpect() { guard="$cfgguard" expect "$@"; }
# só o prefixo declarado vale (um comentário não declara; CRLF é tolerado); o ccr- da nuvem e o wip/ são embutidos
EOL='\r\n' conf '# activity_branch = chore/' 'activity_branch = feat/'
cfgexpect ask "git -C $repo push -u origin chore/x"
cfgexpect ok "git -C $repo push -u origin feat/x"
cfgexpect ok "git -C $repo push -u origin HEAD:refs/heads/feat/x"
cfgexpect ok "git -C $repo push -u origin ccr-1ad6512c-bpqm1j"
cfgexpect ok "git -C $repo push origin abc123:refs/heads/wip/x-1"
# sem nenhum activity_branch (ou com o risk.conf do HEAD apagado da árvore), só o ccr- e o wip/ valem; main segue recusada
conf '# vazio'
cfgexpect ask "git -C $repo push -u origin feat/x"
cfgexpect ok "git -C $repo push -u origin ccr-1ad6512c-bpqm1j"
cfgexpect ok "git -C $repo push origin abc123:refs/heads/wip/x-1"
rm -f "$cfg/risk.conf"
cfgexpect ask "git -C $repo push -u origin feat/x"
cfgexpect deny "git -C $repo push origin main"
# valor fora do alfabeto fechado é ignorado, nunca vira regex
conf 'activity_branch = .*/' 'activity_branch = a|zzz/' 'activity_branch = -f/' 'activity_branch = feat'
cfgexpect ask "git -C $repo push -u origin zzz/x"
cfgexpect ask "git -C $repo push -u origin a/x"
cfgexpect ask "git -C $repo push -u origin feat/x"
# prefixo que é espaço de nome do git (refs/, heads/, tags/, remotes/, em qualquer caixa) é ignorado: o git leria o
# destino como ref de outro tipo (refs/tags/v1 cria tag no remoto, remotes/x atualiza ref de rastreio); heads/heads/x
# testa o heads/ porque o guard já tira um heads/ do destino antes de comparar
conf 'activity_branch = refs/' 'activity_branch = Tags/' 'activity_branch = heads/' 'activity_branch = remotes/' 'activity_branch = feat/'
cfgexpect ask "git -C $repo push -u origin refs/tags/v1"
cfgexpect ask "git -C $repo push origin HEAD:refs/tags/v1"
cfgexpect ask "git -C $repo push -u origin tags/v1"
cfgexpect ask "git -C $repo push -u origin Tags/v1"
cfgexpect ask "git -C $repo push -u origin heads/heads/x"
cfgexpect ask "git -C $repo push -u origin remotes/origin/x"
cfgexpect ok "git -C $repo push -u origin feat/x"
# default_branch: recusado como main e master, e é a base do que o push publica (origin/<default_branch>)
conf 'activity_branch = feat/' 'default_branch = trunk'
cfgexpect deny "git -C $repo push origin trunk"
cfgexpect deny "git -C $repo push origin feat/x:trunk"
cfgexpect deny "git -C $repo push origin refs/heads/trunk"
cfgexpect deny "git -C $repo push origin main"
mkbranch "$repo" feat/seguro src/a.cs
cfgexpect ask "git -C $repo push -u origin feat/seguro" 'origin/trunk'
git -C "$repo" update-ref refs/remotes/origin/trunk "$main_sha"
cfgexpect ok "git -C $repo push -u origin feat/seguro"
git -C "$repo" update-ref -d refs/remotes/origin/trunk
conf 'activity_branch = feat/' 'default_branch = tr unk' 'default_branch = .*'
cfgexpect ask "git -C $repo push origin trunk"
cfgexpect ok "git -C $repo push -u origin feat/seguro"
# protected acrescenta ao núcleo: ci/ e .devcontainer/ só valem se o risk.conf declarar; o núcleo vale sempre
mkbranch "$repo" feat/segredo docs/segredo/x
mkbranch "$repo" feat/ci ci/x.sh
mkbranch "$repo" feat/devc .devcontainer/devcontainer.json
mkbranch "$repo" feat/nucleo .github/workflows/x.yml
conf 'activity_branch = feat/' 'protected = docs/segredo/*'
cfgexpect ask "git -C $repo push -u origin feat/segredo" 'caminho protegido: docs/segredo/x'
cfgexpect ok "git -C $repo push -u origin feat/ci"
cfgexpect ok "git -C $repo push -u origin feat/devc"
cfgexpect ask "git -C $repo push -u origin feat/nucleo" '.github/workflows/x.yml'
conf 'activity_branch = feat/' 'protected = ci/*' 'protected = .devcontainer/*'
cfgexpect ask "git -C $repo push -u origin feat/ci" 'caminho protegido: ci/x.sh'
cfgexpect ask "git -C $repo push -u origin feat/devc" 'caminho protegido: .devcontainer/devcontainer.json'
cfgexpect ok "git -C $repo push -u origin feat/segredo"
# o glob ignora a caixa e todo metacaractere de regex é literal (* e ? são os curingas do case)
conf 'activity_branch = feat/' 'protected = DOCS/Segredo/*'
cfgexpect ask "git -C $repo push -u origin feat/segredo" 'docs/segredo/x'
mkbranch "$repo" feat/pontos docs/aXb docs/x/y
conf 'activity_branch = feat/' 'protected = docs/a.b' 'protected = docs/(x)*'
cfgexpect ok "git -C $repo push -u origin feat/pontos"
mkbranch "$repo" feat/ponto docs/a.b
cfgexpect ask "git -C $repo push -u origin feat/ponto" 'docs/a.b'
mkbranch "$repo" feat/paren 'docs/(x)/y'
cfgexpect ask "git -C $repo push -u origin feat/paren" 'docs/(x)/y'
mkbranch "$repo" feat/interr docs/segredo
conf 'activity_branch = feat/' 'protected = docs/segred?'
cfgexpect ask "git -C $repo push -u origin feat/interr" 'docs/segredo'
# o curinga casa LF e CR no nome do arquivo (o "." do regex não casaria): o antigo prefixo ci/ pedia aqui
conf 'activity_branch = feat/' 'protected = ci/*' 'protected = .devcontainer/?/*'
mkbranch "$repo" feat/lf $'ci/a\nb.sh'
cfgexpect ask "git -C $repo push -u origin feat/lf" 'caminho protegido: ci/a'
mkbranch "$repo" feat/cr $'ci/a\rb.sh'
cfgexpect ask "git -C $repo push -u origin feat/cr" 'caminho protegido: ci/a'
mkbranch "$repo" feat/interr-lf $'.devcontainer/\n/devcontainer.json'
cfgexpect ask "git -C $repo push -u origin feat/interr-lf" 'caminho protegido: .devcontainer/'
# risk.conf que existe mas não pode ser lido (aqui, uma pasta): falha fechada, nunca só o núcleo
mkbranch "$repo" ccr-1ad6512c-semconf src/b.cs
rm -f "$cfg/risk.conf" && mkdir "$cfg/risk.conf"
cfgexpect ask "git -C $repo push -u origin ccr-1ad6512c-semconf" 'risk.conf'
rmdir "$cfg/risk.conf"
# apagado da árvore com o arquivo no HEAD também: os caminhos protegidos do projeto sumiriam em silêncio
cfgexpect ask "git -C $repo push -u origin ccr-1ad6512c-semconf" 'risk.conf'
cfgexpect ask "git -C $repo "$'\\\n'"push -u origin ccr-1ad6512c-semconf"

# projeto que nunca adotou o wstack (sem .claude/risk.conf na árvore nem no HEAD): o hook não força pedido para branch
# que não é a padrão, mas a padrão (main, master e a do origin/HEAD), o force e o núcleo de caminhos protegidos continuam
cru="$work/cru"; git init -q --bare "$work/cru.git" && git init -q "$cru" && git -C "$cru" remote add origin "$work/cru.git"
printf 'a\n' > "$cru/a.txt" && git -C "$cru" add a.txt && git -C "$cru" -c user.name=t -c user.email=t@t commit -q -m base
git -C "$cru" push -q origin HEAD:refs/heads/develop 2> /dev/null && git -C "$cru" fetch -q origin
git -C "$cru" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
mkbranch "$cru" qualquer/coisa src/a.cs
mkbranch "$cru" feat/wf .github/workflows/x.yml
mkbranch "$cru" feat/ci ci/x.sh
crexpect() { CLAUDE_PROJECT_DIR="$cru" PAYLOAD_CWD="$cru" expect "$@"; }
crexpect ok "git -C $cru push -u origin qualquer/coisa"
crexpect ok "git -C $cru push -u origin feat/ci"
crexpect ask "git -C $cru push -u origin feat/wf" '.github/workflows/x.yml'
crexpect deny "git -C $cru push origin develop"
crexpect deny "git -C $cru push origin qualquer/coisa:main"
crexpect deny "git -C $cru push origin master"
crexpect deny "git -C $cru push --force origin qualquer/coisa"
crexpect ask "git status && git -C $cru push -u origin qualquer/coisa"
# tag, nota e ref de rastreio não são branch: continuam pedindo, como no projeto que declara os prefixos
crexpect ask "git -C $cru push origin qualquer/coisa:refs/tags/v1"
crexpect ask "git -C $cru push origin HEAD:refs/tags/v1"
crexpect ask "git -C $cru push origin qualquer/coisa:refs/notes/commits"
crexpect ask "git -C $cru push origin qualquer/coisa:refs/remotes/origin/x"
crexpect ask "git -C $cru push -u origin tags/v1"
crexpect ask "git -C $cru push -u origin Refs/tags/v1"
crexpect ok "git -C $cru push -u origin qualquer/coisa:refs/heads/outra"

# projeto que adotou o wstack com o HEAD num commit anterior ao bootstrap (checkout que não cita a trava): o arquivo está
# na branch padrão, então nada afrouxa: sem o arquivo na árvore o hook não conhece prefixos, branch padrão nem caminhos
# protegidos do projeto, e pede (falha fechada, como na 0.0.10); nenhum desses pushes sai sem decisão
ado="$work/adotado"; git init -q --bare "$work/adotado.git" && git init -q -b develop "$ado" && git -C "$ado" remote add origin "$work/adotado.git"
printf 'a\n' > "$ado/a.txt" && git -C "$ado" add a.txt && git -C "$ado" -c user.name=t -c user.email=t@t commit -q -m pre
pre=$(git -C "$ado" rev-parse HEAD)
mkdir -p "$ado/.claude" && printf 'default_branch = develop\nactivity_branch = feat/\nprotected = ci/*\n' > "$ado/.claude/risk.conf"
git -C "$ado" add -A && git -C "$ado" -c user.name=t -c user.email=t@t commit -q -m bootstrap
git -C "$ado" push -q origin develop 2> /dev/null && git -C "$ado" fetch -q origin
git -C "$ado" checkout -q -b release/a "$pre"
mkdir -p "$ado/ci" && printf 'x\n' > "$ado/ci/x.sh" && git -C "$ado" add -A && git -C "$ado" -c user.name=t -c user.email=t@t commit -q -m ci
git -C "$ado" branch -q feat/b
adexpect() { CLAUDE_PROJECT_DIR="$ado" PAYLOAD_CWD="$ado" expect "$@"; }
adexpect ask "git -C $ado push -u origin release/a"
adexpect ask "git -C $ado push -u origin feat/b"
adexpect ask "git -C $ado push -u origin feat/b:release/b"
adexpect notok "git -C $ado push origin feat/b:develop"
adexpect notok "git -C $ado push origin feat/b:refs/tags/v9"
# objeto de troca (git replace, que não cita a trava): o hook vê os commits reais, que são os que o push manda
git -C "$ado" replace "$(git -C "$ado" rev-parse develop)" "$(git -C "$ado" commit-tree "$pre^{tree}" -p "$pre" -m x)"
adexpect ask "git -C $ado push -u origin release/a"
git -C "$ado" replace -d "$(git -C "$ado" rev-parse develop)" > /dev/null
git -C "$ado" checkout -q -b feat/x develop
mkdir -p "$ado/ci" && printf 'y\n' > "$ado/ci/y.sh" && git -C "$ado" add -A && git -C "$ado" -c user.name=t -c user.email=t@t commit -q -m ci
git -C "$ado" replace "$(git -C "$ado" rev-parse feat/x)" "$(git -C "$ado" commit-tree "develop^{tree}" -p develop -m inocente)"
adexpect ask "git -C $ado push -u origin feat/x" 'ci/y.sh'

# repositório bare forjado numa pasta qualquer (sem .git no nome, fora do alcance do write-guard): com
# safe.bareRepository=explicit, que o setup.sh grava na config global, o git recusa usá-lo pela pasta atual
bare="$work/bare"; mkdir -p "$bare/objects" "$bare/refs" && printf 'ref: refs/heads/main\n' > "$bare/HEAD"
printf '[core]\n\tbare = true\n\tfsmonitor = touch %s/pwned\n' "$work" > "$bare/config"
printf '[safe]\n\tbareRepository = explicit\n' > "$work/gitconfig-explicit"
(cd "$bare" && GIT_CONFIG_GLOBAL="$work/gitconfig-explicit" git rev-parse --git-dir > /dev/null 2>&1) \
  && { echo "FALHOU: com safe.bareRepository=explicit o git ainda usou o repositório bare pela pasta atual"; fails=$((fails + 1)); }
(cd "$bare" && GIT_CONFIG_GLOBAL=/dev/null git rev-parse --git-dir > /dev/null 2>&1) \
  || { echo "FALHOU: sem a configuração o git deveria usar o repositório bare (o caso acima não provaria nada)"; fails=$((fails + 1)); }

if [ "$fails" -eq 0 ]; then echo "test-push-guard: todos os casos passaram"; exit 0; fi
echo "test-push-guard: $fails falha(s)"
exit 1
