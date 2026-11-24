#!/usr/bin/env bash
# Casos do write-guard (hook PreToolUse em Edit, Write, MultiEdit e NotebookEdit), sem rede: o hook recebe o payload do
# Claude Code pela entrada padrão; os repositórios são montados numa pasta temporária.
# Uso: test-write-guard.sh [<write-guard.sh>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

top=$(git rev-parse --show-toplevel 2> /dev/null)
guard=${1:-$top/.claude/hooks/write-guard.sh}
[ -f "$guard" ] || { echo "write-guard.sh não encontrado" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq ausente" >&2; exit 2; }
guard=$(cd "$(dirname "$guard")" && pwd -P)/$(basename "$guard")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-write-guard-XXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
fails=0

expect() { # expect <ok|deny> <ferramenta> <caminho> [cwd]
  local payload rc got key=file_path
  [ "$2" = NotebookEdit ] && key=notebook_path
  payload=$(jq -cn --arg t "$2" --arg k "$key" --arg p "$3" --arg d "${4:-$repo}" \
    '{hook_event_name:"PreToolUse",tool_name:$t,cwd:$d,tool_input:({($k):$p, content:"x"})}')
  printf '%s' "$payload" | HOME=$work/home XDG_CONFIG_HOME='' CLAUDE_PROJECT_DIR=${PROJECT:-$repo} bash "$guard" > /dev/null 2>&1; rc=$?
  case $rc in 0) got=ok ;; 2) got=deny ;; *) got="rc=$rc" ;; esac
  [ "$got" = "$1" ] || { echo "FALHOU: esperado $1, obtido $got: $2 $3 (cwd ${4:-$repo})"; fails=$((fails + 1)); }
}

repo=$work/repo
git init -q "$repo" && git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
mkdir -p "$repo/src" "$repo/sub"

# livres: arquivos comuns, inclusive os que começam por .git no nome
expect ok Write "$repo/src/a.cs"
expect ok Edit src/a.cs
expect ok Write "$repo/.gitignore"
expect ok Write "$repo/.gitattributes"
expect ok Write "$repo/.github/workflows/x.yml"
expect ok Write "$repo/src/.gitkeep"
expect ok NotebookEdit "$repo/n.ipynb"
expect ok Write "$work/fora/x.txt"

# recusados: qualquer caminho que passe por uma pasta ou arquivo .git, em qualquer ferramenta e grafia
expect deny Write "$repo/.git/config"
expect deny Edit .git/hooks/pre-push
expect deny Write "$repo/sub/.git/config"
expect deny Write "$repo/sub/.git"
expect deny MultiEdit "$repo/sub/.GIT/config"
expect deny NotebookEdit "$repo/.git/x.ipynb"
expect deny Write "$work/outro/.git/config"
expect deny Write "$repo/src/../.git/config"
expect deny Write 'sub\.git\config'
# nomes que o Windows (NTFS) trata como .git: nome curto 8.3, ponto ou espaço no fim, fluxo alternativo
expect deny Write "$repo/GIT~1/config"
expect deny Write "$repo/git~2/hooks/pre-push"
expect deny Write "$repo/.git./config"
expect deny Write "$repo/.git /config"
expect deny Write "$repo/.git::\$INDEX_ALLOCATION/config"
expect ok Write "$repo/.git.bak/x"
expect ok Write "$repo/gitx~1/x"

# config global e do sistema: sem .git no caminho, mas decidem o que todo git executa
expect deny Write "$work/home/.gitconfig"
expect deny Write "$work/home/.config/git/config"
expect deny Write "$work/home/.config/git/attributes"
expect deny Write /etc/gitconfig
expect deny Write "$repo/sub/.gitconfig"
expect ok Write "$work/home/.config/outro/config"
# arquivos que a config global manda ler ou executar: o include e os programas (gpg.ssh.program, credential.helper...)
mkdir -p "$work/home"
printf '[include]\n\tpath = %s/incluida.cfg\n[gpg "ssh"]\n\tprogram = %s/assina\n[credential]\n\thelper = !%s/cred get\n[core]\n\tpager = less\n' "$work" "$work" "$work" > "$work/home/.gitconfig"
expect deny Write "$work/incluida.cfg"
expect deny Write "$work/assina"
expect deny Write "$work/cred"
expect ok Write "$work/outro-programa"
# include.path relativo vale a partir da pasta do arquivo que o contém (ainda que o incluído não exista)
printf '[include]\n\tpath = local.inc\n' > "$work/home/.gitconfig"
expect deny Write "$work/home/local.inc"
rm -f "$work/home/.gitconfig"
# na config local, a origem vem relativa (file:.git/config): vale a pasta do projeto, não o cwd do hook
git -C "$repo" config --local include.path ../team.cfg
cd / && expect deny Write "$repo/team.cfg" / && cd "$OLDPWD"
git -C "$repo" config --local --unset include.path

# recusado atrás de symlink: um link para o .git do projeto
ln -s "$repo/.git" "$repo/atalho"
expect deny Write "$repo/atalho/config"
expect deny Write "$repo/atalho/novo/arquivo"
git init -q "$repo/sub2" && ln -s "$repo/sub2/.git" "$repo/atalho2"
expect deny Write "$repo/atalho2/config"
# symlink pendente (o alvo ainda não existe): o Write seguiria o link e criaria o hook dentro do .git
ln -s "$repo/.git/hooks/pre-push" "$repo/pendente"
expect deny Write "$repo/pendente"
ln -s "$repo/nao/existe/.git/config" "$repo/pendente2"
expect deny Write "$repo/pendente2"
# link/.. sobe a partir do alvo do link, não do texto: lnk/../config é sub2/.git/config
ln -s "$repo/sub2/.git/hooks" "$repo/lnk"
expect deny Write "$repo/lnk/../config"
expect deny Write lnk/../config

# sessão numa worktree: o .git dela é arquivo e o repositório comum fica fora da pasta do projeto
git -C "$repo" worktree add -q "$work/wt" -b chore/wt 2> /dev/null
PROJECT=$work/wt expect deny Write "$work/wt/.git" "$work/wt"
PROJECT=$work/wt expect deny Write "$repo/.git/worktrees/wt/config.worktree" "$work/wt"
PROJECT=$work/wt expect deny Write "$repo/.git/hooks/pre-push" "$work/wt"
PROJECT=$work/wt expect ok Write "$work/wt/src/a.cs" "$work/wt"

# repositório com --separate-git-dir: a pasta git não se chama .git e também é recusada
git init -q --separate-git-dir "$work/gd" "$work/sep" 2> /dev/null
PROJECT=$work/sep expect deny Write "$work/gd/config" "$work/sep"
PROJECT=$work/sep expect ok Write "$work/sep/a.txt" "$work/sep"

# payload ilegível ou sem caminho: recusa (falha fechada)
printf 'não é json' | CLAUDE_PROJECT_DIR=$repo bash "$guard" > /dev/null 2>&1
[ $? = 2 ] || { echo "FALHOU: payload ilegível não foi recusado"; fails=$((fails + 1)); }

if [ "$fails" -eq 0 ]; then echo "test-write-guard: todos os casos passaram"; exit 0; fi
echo "test-write-guard: $fails falha(s)"
exit 1
