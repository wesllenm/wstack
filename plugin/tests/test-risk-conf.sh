#!/usr/bin/env bash
# Casos do risk-conf.mjs: o .claude/risk.conf lido é o do PROJETO, nunca um da pasta do plugin. Nos hooks o projeto é
# $CLAUDE_PROJECT_DIR; nos scripts que o agente roda pelo Bash (onde essa variável não existe), é a raiz git da pasta
# atual. Sem nenhum dos dois, nada é lido e o motivo fica em confError (falha fechada para quem depende do arquivo).
# Uso: test-risk-conf.sh [<risk-conf.mjs>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

mod=${1:-$(dirname "$0")/../hooks/risk-conf.mjs}
[ -f "$mod" ] || { echo "risk-conf.mjs não encontrado: $mod" >&2; exit 2; }
mod=$(cd "$(dirname "$mod")" && pwd -P)/$(basename "$mod")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-rc-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0

# lê pelo módulo, na pasta e com o ambiente dados: imprime "<valores separados por vírgula>|<confError>"
probe() { # probe <pasta> <chave>
  (cd "$1" && node --input-type=module -e "
    const m = await import(process.argv[1]);
    process.stdout.write(m.confValues(process.argv[2]).join(',') + '|' + m.confError());
  " "$mod" "$2")
}
expect() { # expect <descrição> <obtido> <esperado>
  [ "$2" = "$3" ] || { echo "FALHOU [$1]: esperado '$3', obtido '$2'"; fails=$((fails + 1)); }
}

proj="$work/projeto"; mkdir -p "$proj/.claude" "$proj/sub" && git init -q "$proj"
printf 'activity_branch = feat/\n# activity_branch = x/\nactivity_branch = fix/\r\n' > "$proj/.claude/risk.conf"
outro="$work/outro"; mkdir -p "$outro/.claude" && git init -q "$outro"
printf 'activity_branch = outro/\n' > "$outro/.claude/risk.conf"
solto="$work/solto"; mkdir -p "$solto"

# hook: CLAUDE_PROJECT_DIR manda, qualquer que seja a pasta atual
expect hook-projeto "$(CLAUDE_PROJECT_DIR="$proj" probe "$solto" activity_branch)" 'feat/,fix/|'
expect hook-projeto-outra-pasta "$(CLAUDE_PROJECT_DIR="$proj" probe "$outro" activity_branch)" 'feat/,fix/|'
# script pelo Bash: sem a variável, a raiz git da pasta atual (também de uma subpasta)
expect script-raiz "$(env -u CLAUDE_PROJECT_DIR bash -c "$(declare -f probe); mod='$mod'; probe '$proj' activity_branch")" 'feat/,fix/|'
expect script-subpasta "$(env -u CLAUDE_PROJECT_DIR bash -c "$(declare -f probe); mod='$mod'; probe '$proj/sub' activity_branch")" 'feat/,fix/|'
# sem projeto: nada lido, com motivo
got=$(env -u CLAUDE_PROJECT_DIR bash -c "$(declare -f probe); mod='$mod'; probe '$solto' activity_branch")
[ "${got%%|*}" = '' ] && [ -n "${got#*|}" ] || { echo "FALHOU [sem-projeto]: esperado vazio com motivo, obtido '$got'"; fails=$((fails + 1)); }
# projeto sem risk.conf, ou com risk.conf ilegível (uma pasta): nada lido, com motivo
got=$(CLAUDE_PROJECT_DIR="$solto" probe "$proj" activity_branch)
[ "${got%%|*}" = '' ] && [ -n "${got#*|}" ] || { echo "FALHOU [projeto-sem-conf]: esperado vazio com motivo, obtido '$got'"; fails=$((fails + 1)); }
mkdir -p "$solto/.claude/risk.conf"
got=$(CLAUDE_PROJECT_DIR="$solto" probe "$proj" activity_branch)
[ "${got%%|*}" = '' ] && [ -n "${got#*|}" ] || { echo "FALHOU [conf-pasta]: esperado vazio com motivo, obtido '$got'"; fails=$((fails + 1)); }
# um risk.conf ao lado do módulo (a pasta do plugin) nunca é lido
plug="$work/plugin"; mkdir -p "$plug/hooks" && cp "$mod" "$(dirname "$mod")/git-repo.mjs" "$plug/hooks/" && printf 'activity_branch = plugin/\n' > "$plug/risk.conf"
expect conf-do-plugin "$(mod="$plug/hooks/risk-conf.mjs" CLAUDE_PROJECT_DIR="$proj" probe "$solto" activity_branch)" 'feat/,fix/|'

# confAbsent: só o projeto que não adotou o wstack (arquivo fora da árvore E do HEAD) é "sem risk.conf"
absent() { (cd "$1" && CLAUDE_PROJECT_DIR="$1" node --input-type=module -e "
  const m = await import(process.argv[1]); process.stdout.write(String(m.confAbsent()) + '|' + m.remoteDefault());" "$mod"); }
cru="$work/cru"; mkdir -p "$cru" && git init -q "$cru"
expect ausente-sem-commit "$(absent "$cru")" 'true|'
git -C "$cru" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
expect ausente-com-commit "$(absent "$cru")" 'true|'
git -C "$cru" update-ref refs/remotes/origin/develop HEAD && git -C "$cru" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
expect ausente-branch-do-remoto "$(absent "$cru")" 'true|develop'
expect presente "$(absent "$proj")" 'false|'
apagado="$work/apagado"; mkdir -p "$apagado/.claude" && git init -q "$apagado" && printf 'default_branch = main\n' > "$apagado/.claude/risk.conf"
git -C "$apagado" add .claude/risk.conf && git -C "$apagado" -c user.name=t -c user.email=t@t commit -q -m base && rm "$apagado/.claude/risk.conf"
expect apagado-da-arvore-nao-conta "$(absent "$apagado")" 'false|'
expect conf-pasta-nao-conta "$(absent "$solto")" 'false|'
# HEAD num commit anterior ao bootstrap (checkout de branch ou commit antigo): o arquivo está em outra ref, então o projeto
# adotou o wstack (o estado que o agente move sem citar a trava não liga o modo inerte)
antigo="$work/antigo"; mkdir -p "$antigo" && git init -q -b main "$antigo"
git -C "$antigo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m pre && pre=$(git -C "$antigo" rev-parse HEAD)
mkdir -p "$antigo/.claude" && printf 'default_branch = main\n' > "$antigo/.claude/risk.conf"
git -C "$antigo" add -A && git -C "$antigo" -c user.name=t -c user.email=t@t commit -q -m bootstrap
git -C "$antigo" checkout -q -b release/a "$pre"
expect head-antigo-branch-com-conf "$(absent "$antigo")" 'false|'
git -C "$antigo" checkout -q --detach "$pre"
expect head-antigo-destacado "$(absent "$antigo")" 'false|'
# só no remoto (branch local apagada): também adotado
git -C "$antigo" update-ref refs/remotes/origin/main main && git -C "$antigo" checkout -q release/a && git -C "$antigo" branch -q -D main
expect so-no-remoto "$(absent "$antigo")" 'false|'
# objeto de troca (git replace) que esconde o arquivo na ponta: o que vale é o commit real
git -C "$antigo" replace "$(git -C "$antigo" rev-parse origin/main)" "$(git -C "$antigo" commit-tree "$pre^{tree}" -p "$pre" -m x)"
expect replace-nao-esconde "$(absent "$antigo")" 'false|'
git -C "$antigo" replace -d "$(git -C "$antigo" rev-parse origin/main)" > /dev/null
# branch e ref de rastreio apagadas (git branch -d e -d -r, que não citam a trava): o reflog do HEAD ainda guarda o bootstrap
git -C "$antigo" update-ref -d refs/remotes/origin/main
expect so-no-reflog "$(absent "$antigo")" 'false|'
# branch órfã (HEAD sem commit) com as refs apagadas: o reflog continua valendo
orfa="$work/orfa"; mkdir -p "$orfa/.claude" && git init -q -b main "$orfa" && printf 'default_branch = main\n' > "$orfa/.claude/risk.conf"
git -C "$orfa" add -A && git -C "$orfa" -c user.name=t -c user.email=t@t commit -q -m bootstrap
git -C "$orfa" switch -q --orphan novo && git -C "$orfa" branch -q -D main
(cd "$orfa" && CLAUDE_PROJECT_DIR="$orfa" node "$mod" --absent); expect cli-orfa "$?" 0
# muitas refs (repositório alheio grande): continua sem o wstack, sem estourar o buffer
muitas="$work/muitas"; mkdir -p "$muitas" && git init -q "$muitas" && git -C "$muitas" -c user.name=t -c user.email=t@t commit -q --allow-empty -m b
h=$(git -C "$muitas" rev-parse HEAD)
for i in $(seq 1 20000); do echo "create refs/remotes/origin/b$i $h"; done | git -C "$muitas" update-ref --stdin
expect muitas-refs "$(absent "$muitas")" 'true|'
# ref corrompida: dúvida, não ausente
corr="$work/corrompido"; mkdir -p "$corr" && git init -q -b main "$corr" && git -C "$corr" -c user.name=t -c user.email=t@t commit -q --allow-empty -m b
printf 'lixo\n' > "$corr/.git/refs/heads/main"
expect ref-corrompida-duvida "$(absent "$corr")" 'false|'
# a linha de comando que os hooks de shell usam: código 10 = projeto sem o wstack (o 1 é o do node que falha), 0 = adotado
# ou dúvida
(cd "$cru" && CLAUDE_PROJECT_DIR="$cru" node "$mod" --absent); expect cli-ausente "$?" 10
(cd "$antigo" && CLAUDE_PROJECT_DIR="$antigo" node "$mod" --absent); expect cli-head-antigo "$?" 0

if [ "$fails" -eq 0 ]; then echo "test-risk-conf: todos os casos passaram"; exit 0; fi
echo "test-risk-conf: $fails falha(s)"
exit 1
