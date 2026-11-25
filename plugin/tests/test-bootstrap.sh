#!/usr/bin/env bash
# Casos do scripts/bootstrap.sh sobre repositórios temporários: cria todos os modelos com os marcadores trocados, nunca
# sobrescreve nem grava através de link, o --plan não grava, argumentos fora do alfabeto são recusados, e o projeto gerado
# é o que os hooks e o classificador esperam (settings.json com o plugin fixado, risk.conf que classifica as defesas como
# CRITICA, .gitignore com o estado local).
# Uso: test-bootstrap.sh
# Código: 0 todos passaram, 1 algum falhou.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
plugin=$(cd "$here/.." && pwd -P)
boot=$plugin/scripts/bootstrap.sh
classify=$plugin/scripts/classify-diff.sh
version=$(jq -r .version "$plugin/.claude-plugin/plugin.json")
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-boot-XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FALHOU: $1"; fails=$((fails + 1)); }
newrepo() { local d="$work/$1"; mkdir -p "$d" && git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base && echo "$d"; }
boot() { local d=$1; shift; (cd "$d" && bash "$boot" "$@" 2>&1); }
snapshot() { (cd "$1" && find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum 2> /dev/null); }

# o que o modelo cria (a verify-<app> só com --app)
expected=(CLAUDE.md .claude/settings.json .claude/risk.conf .claude/project.md .claude/architecture.md .claude/cloud/hosts.conf
  docs/review-calibration.md docs/review-rubric.md docs/gotchas.md docs/decisions.md)

# projeto novo: tudo criado, sem marcador, com os valores certos
p=$(newrepo novo)
out=$(boot "$p" --projeto "Loja Exemplo"); rc=$?
[ "$rc" = 0 ] || fail "projeto novo saiu $rc: $out"
for f in "${expected[@]}"; do [ -f "$p/$f" ] || fail "não criou $f"; done
[ -e "$p/.claude/skills" ] && fail "criou .claude/skills sem --app"
left=$(grep -rl '{{[A-Z_]*}}' "$p" --exclude-dir=.git); [ -z "$left" ] || fail "marcador sem valor em: $left"
jq -e --arg r "v$version" '.agent == "wstack:lead" and .worktree.baseRef == "head" and .enabledPlugins["wstack@wstack"] == true
  and .extraKnownMarketplaces.wstack.source == {source: "github", repo: "wesllenm/wstack", ref: $r}' "$p/.claude/settings.json" > /dev/null \
  || fail "settings.json sem agente, baseRef ou plugin fixado em v$version"
jq -e '.permissions.deny | index("Edit(~/.claude/plugins/**)") and index("Edit(./.gitignore)")' "$p/.claude/settings.json" > /dev/null \
  || fail "settings.json sem o deny da pasta do plugin ou do .gitignore"
# piso das travas: o deny e o ask do modelo contêm as regras que a 2.2 fixou (fixture removida na 2.4) e o deny de leitura
# dos segredos que o path-guard pressupõe; tirar uma delas do modelo reprova aqui, não só no test-path-guard (que confere
# o que está no modelo, não o que falta)
piso_deny='["Edit(./.gitignore)","Edit(./**/.gitignore)","Edit(./.git/**)","Edit(~/.ssh/**)","Edit(~/.config/gh/**)","Edit(~/.docker/**)","Edit(~/.claude/settings.json)","Edit(~/.claude.json)","Edit(~/.claude/plugins/**)","Read(./.env)","Read(./.env.*)","Read(./**/*.pem)","Read(./**/*.pfx)","Read(./**/*.p12)","Read(./**/appsettings.*.local.json)","Read(./.claude/settings.local.json)","Bash(git push --force:*)","Bash(git push -f:*)","Bash(gh pr merge:*)"]'
piso_ask='["Edit(./.claude/hooks/**)","Edit(./.claude/settings.json)","Edit(./.claude/risk.conf)","Edit(./.claude/scripts/**)","Edit(./**/.claude/hooks/**)","Edit(./**/.claude/settings.json)","Edit(./**/.claude/risk.conf)","Edit(./**/.claude/scripts/**)","Edit(./.claude/cloud/**)","Edit(./.claude/.verify-ok)","Edit(./.claude/.session/checkpoint-ok-*)","Edit(./.github/workflows/**)","Edit(./.claude/settings.local.json)","Edit(./.mcp.json)"]'
for r in $(jq -r --argjson d "$piso_deny" '$d - .permissions.deny | .[]' "$p/.claude/settings.json"); do fail "deny do modelo sem $r"; done
for r in $(jq -r --argjson a "$piso_ask" '$a - .permissions.ask | .[]' "$p/.claude/settings.json"); do fail "ask do modelo sem $r"; done
jq -e '[.permissions.allow[] | select(test("\\.claude/(scripts|hooks)/"))] | length == 0' "$p/.claude/settings.json" > /dev/null \
  || fail "settings.json ainda libera script ou hook do .claude/ do projeto"
grep -qx 'default_branch = main' "$p/.claude/risk.conf" || fail "risk.conf sem default_branch = main"
grep -q '^Loja Exemplo: ' "$p/CLAUDE.md" || fail "CLAUDE.md sem o nome do projeto"
grep -qx '@docs/gotchas.md' "$p/CLAUDE.md" || fail "CLAUDE.md sem o import dos gotchas"
grep -q "^Última manutenção: $(date -u +%Y-%m-%d)$" "$p/docs/review-calibration.md" || fail "calibração sem a data"
for s in 'Sempre verificar' 'Não reportar' 'Projeto'; do grep -qx "## $s" "$p/docs/review-rubric.md" || fail "rubrica sem a seção $s"; done
grep -q '^| Domínio | Glob | Skill |$' "$p/.claude/project.md" || fail "project.md sem a tabela Domínios que a skill lead lê"
for l in .claude/settings.local.json .claude/.session/ .claude/worktrees/ .claude/worktree.env .claude/.verify-ok; do
  grep -qxF "$l" "$p/.gitignore" || fail ".gitignore sem $l"
done
# o projeto gerado classifica as próprias defesas como CRITICA e código comum abaixo disso
for f in .claude/settings.json .claude/risk.conf .claude/cloud/hosts.conf CLAUDE.md docs/review-rubric.md .github/workflows/ci.yml; do
  n=$(cd "$p" && bash "$classify" --paths "$f" 2> /dev/null | head -1); [ "$n" = CRITICA ] || fail "classificador: $f saiu $n"
done
# (--paths nunca dá TRIVIAL: só o diff real confirma)
n=$(cd "$p" && bash "$classify" --paths src/a.txt 2> /dev/null | head -1); [ "$n" = SIMPLES ] || fail "classificador: src/a.txt saiu $n"

# segunda vez: nada muda, tudo listado como existente, código 1
before=$(snapshot "$p")
out=$(boot "$p"); rc=$?
[ "$rc" = 1 ] || fail "segunda execução saiu $rc"
[ "$(snapshot "$p")" = "$before" ] || fail "segunda execução alterou arquivo"
grep -q '^existe: \.claude/settings\.json' <<< "$out" || fail "segunda execução não listou o settings.json existente: $out"

# projeto com CLAUDE.md e settings.json próprios: os dois ficam byte a byte, o resto é criado
p=$(newrepo existente)
mkdir -p "$p/.claude" && printf '# meu\n' > "$p/CLAUDE.md" && printf '{"agent":"outro"}\n' > "$p/.claude/settings.json"
printf 'bin/\n' > "$p/.gitignore"
h1=$(sha256sum "$p/CLAUDE.md" "$p/.claude/settings.json")
out=$(boot "$p"); rc=$?
[ "$rc" = 1 ] || fail "projeto com arquivos próprios saiu $rc"
[ "$(sha256sum "$p/CLAUDE.md" "$p/.claude/settings.json")" = "$h1" ] || fail "sobrescreveu CLAUDE.md ou settings.json"
[ -f "$p/.claude/risk.conf" ] || fail "não criou o risk.conf ao lado dos existentes"
[ "$(head -1 "$p/.gitignore")" = 'bin/' ] && grep -qxF .claude/.session/ "$p/.gitignore" || fail ".gitignore perdeu linha ou não ganhou as novas"

# --plan não grava nada
p=$(newrepo plano)
out=$(boot "$p" --plan --app web); rc=$?
[ "$rc" = 0 ] || fail "--plan saiu $rc"
[ -z "$(git -C "$p" status --porcelain --ignored)" ] || fail "--plan gravou: $(git -C "$p" status --porcelain --ignored)"
grep -q '^criado: \.claude/skills/verify-web/SKILL\.md$' <<< "$out" || fail "--plan não listou a verify-web"

# --app: esqueleto da verify-<app>
p=$(newrepo app)
boot "$p" --app web > /dev/null
grep -qx 'name: verify-web' "$p/.claude/skills/verify-web/SKILL.md" 2> /dev/null || fail "verify-web sem o nome"
[ -f "$p/.claude/skills/verify-web/features/README.md" ] || fail "verify-web sem o mapa de features"

# branch padrão do remoto
p=$(newrepo remoto)
git -C "$p" update-ref refs/remotes/origin/develop HEAD && git -C "$p" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
boot "$p" > /dev/null
grep -qx 'default_branch = develop' "$p/.claude/risk.conf" || fail "risk.conf sem a branch padrão do remoto"

# link: nada gravado através dele
p=$(newrepo link); fora="$work/fora"; mkdir -p "$fora"
ln -s "$fora" "$p/.claude"
out=$(boot "$p"); rc=$?
[ "$rc" = 1 ] || fail "pasta .claude como link saiu $rc"
[ -z "$(ls -A "$fora")" ] || fail "gravou através do link: $(ls -A "$fora")"
grep -q '^link: \.claude/settings\.json' <<< "$out" || fail "não listou o link: $out"
p=$(newrepo linkignore); printf 'x\n' > "$fora/ignore"; ln -s "$fora/ignore" "$p/.gitignore"
boot "$p" > /dev/null
[ "$(cat "$fora/ignore")" = x ] || fail "acrescentou ao .gitignore através do link"

# argumentos fora do alfabeto
p=$(newrepo args)
recusa() { (cd "$p" && bash "$boot" "$@" > /dev/null 2>&1); local rc=$?; [ "$rc" = 2 ] || fail "argumentos '$*' saíram $rc"; }
recusa --projeto 'a;b'
recusa --projeto -x
recusa --app Web
recusa --app ../x
recusa --ref ../x
recusa --ref 'a;b'
recusa --nada
recusa --app
[ -z "$(git -C "$p" status --porcelain --ignored)" ] || fail "argumento recusado gravou algo"
(cd "$work" && bash "$boot" > /dev/null 2>&1); [ $? = 3 ] || fail "fora de repositório não saiu 3"

if [ "$fails" -eq 0 ]; then echo "test-bootstrap: todos os casos passaram"; exit 0; fi
echo "test-bootstrap: $fails falha(s)"
exit 1
