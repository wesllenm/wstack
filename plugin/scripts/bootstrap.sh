#!/usr/bin/env bash
# Cria no projeto os arquivos modelo do wstack (plugin/templates), para o /wstack:bootstrap. Cópia determinística: nunca
# sobrescreve arquivo que existe (lista como conflito, para o desenvolvedor e o modelo decidirem), nunca grava através de
# link e só troca os marcadores {{PROJETO}}, {{DATA}}, {{WSTACK_REF}} e {{APP}}, e a linha "default_branch = main" pela
# branch padrão detectada (origin/HEAD; sem ela, main ou master se for a atual). O resto do conteúdo
# (comandos, globs, domínios, o "<...>" dos modelos) é preenchido depois pela skill bootstrap, com a aprovação única.
# Acrescenta ao .gitignore as linhas de estado local do workflow (antes do settings.json, que põe .gitignore no deny).
# Pede aprovação de propósito: grava no projeto, então fica fora do hook script-allow.
# Uso: bootstrap.sh [--plan] [--projeto <nome>] [--app <nome>] [--ref <ref do plugin>]
#   --plan      mostra o que faria, sem gravar nada
#   --projeto   nome do projeto nos modelos (padrão: nome da pasta do repositório)
#   --app       gera também o esqueleto .claude/skills/verify-<app>/ (só quando o projeto tem aplicação para subir)
#   --ref       referência do plugin fixada no .claude/settings.json (padrão: v<versão deste plugin>, a tag dela)
# Roda na raiz do repositório do projeto. Saída: uma linha por arquivo (criado, existe, link) e por linha do .gitignore.
# Código: 0 tudo criado; 1 algum arquivo já existia ou é link (nada sobrescrito); 2 uso errado; 3 fora de repositório git.
set -uo pipefail
shopt -u patsub_replacement 2> /dev/null # bash 5.2: "&" na substituição de ${v//a/b} viraria o texto casado

plugin=$(cd "$(dirname "$0")/.." && pwd -P)
templates=$plugin/templates
mode=run projeto="" app="" ref=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) mode=plan ;;
    --projeto) [ $# -ge 2 ] || { echo "bootstrap: --projeto sem valor" >&2; exit 2; }; projeto=$2; shift ;;
    --app) [ $# -ge 2 ] || { echo "bootstrap: --app sem valor" >&2; exit 2; }; app=$2; shift ;;
    --ref) [ $# -ge 2 ] || { echo "bootstrap: --ref sem valor" >&2; exit 2; }; ref=$2; shift ;;
    *) echo "uso: bootstrap.sh [--plan] [--projeto <nome>] [--app <nome>] [--ref <ref>]" >&2; exit 2 ;;
  esac
  shift
done

root=$(git rev-parse --show-toplevel 2> /dev/null) || { echo "bootstrap: fora de um repositório git" >&2; exit 3; }
cd "$root" || exit 3
[ "$(pwd -P)" != "$(cd "$plugin/.." && pwd -P)" ] || { echo "bootstrap: este é o repositório do próprio plugin" >&2; exit 2; }

version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9A-Za-z.+-]*\)".*/\1/p' "$plugin/.claude-plugin/plugin.json" | head -1)
projeto=${projeto:-$(basename "$root")}
ref=${ref:-v$version}
data=$(date -u +%Y-%m-%d)
branch=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2> /dev/null); branch=${branch#origin/}
[ -n "$branch" ] || { branch=$(git symbolic-ref --short -q HEAD 2> /dev/null); case "$branch" in main | master) ;; *) branch=main ;; esac; }

# alfabetos fechados: os valores entram em arquivo de configuração lido por hooks e no texto que toda sessão carrega
[[ $projeto =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]{0,63}$ ]] || { echo "bootstrap: nome do projeto fora do alfabeto (letra, dígito, espaço, ponto, hífen, sublinhado)" >&2; exit 2; }
[ -z "$app" ] || [[ $app =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || { echo "bootstrap: --app fora do alfabeto (minúsculas, dígitos, hífen)" >&2; exit 2; }
[[ $ref =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ && $ref != *..* ]] || { echo "bootstrap: --ref fora do alfabeto" >&2; exit 2; }
[[ $branch =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] || branch=main

render() { # render <modelo>: o conteúdo com os marcadores trocados; falha se o modelo não pôde ser lido
  local c
  c=$(cat "$1" && printf x) || return 1
  c=${c%x} # preserva as quebras de linha do fim
  c=${c//'{{PROJETO}}'/$projeto}; c=${c//'{{DATA}}'/$data}; c=${c//'{{WSTACK_REF}}'/$ref}
  c=${c//'{{APP}}'/$app}
  # o risk.conf modelo traz a linha literal (os testes do plugin o copiam como está); aqui vira a branch detectada
  c=${c//$'\ndefault_branch = main\n'/$'\ndefault_branch = '"$branch"$'\n'}
  printf '%s' "$c"
}
linked() { # algum trecho do caminho (o próprio arquivo ou uma pasta acima, dentro do projeto) é link
  local p=$1
  while [ "$p" != . ] && [ -n "$p" ]; do [ -L "$p" ] && return 0; p=$(dirname "$p"); done
  return 1
}

# modelo -> destino; a verify-<app> só com --app
pairs=()
while IFS= read -r f; do
  rel=${f#"$templates"/}
  case "$rel" in
    verify-app/*) [ -n "$app" ] && pairs+=("$f|.claude/skills/verify-$app/${rel#verify-app/}") ;;
    *) pairs+=("$f|$rel") ;;
  esac
done < <(find "$templates" -type f | LC_ALL=C sort)

conflicts=0
# .gitignore primeiro: estado local do workflow fora do git (depois do settings.json, editar o .gitignore é deny)
ignore_lines=(.claude/settings.local.json .claude/.verify-ok .claude/verify-blocked.md .claude/.session/ .claude/worktrees/
  .claude/worktree.env .claude/telemetry/ .claude/SESSION.md)
if linked .gitignore; then
  echo "link: .gitignore (não alterado; acrescentar à mão: ${ignore_lines[*]})"; conflicts=$((conflicts + 1))
else
  for l in "${ignore_lines[@]}"; do
    [ -f .gitignore ] && grep -qxF -- "$l" .gitignore && continue
    if [ "$mode" = run ]; then
      { [ ! -s .gitignore ] || [ -z "$(tail -c1 .gitignore)" ] || printf '\n' >> .gitignore; } && printf '%s\n' "$l" >> .gitignore \
        || { echo "bootstrap: falhou ao gravar no .gitignore" >&2; exit 3; }
    fi
    echo "gitignore: + $l"
  done
fi

for pair in "${pairs[@]}"; do
  src=${pair%%|*} dest=${pair#*|}
  if linked "$dest"; then echo "link: $dest (não gravado)"; conflicts=$((conflicts + 1)); continue; fi
  if [ -e "$dest" ]; then echo "existe: $dest (não sobrescrito; comparar com o modelo $src)"; conflicts=$((conflicts + 1)); continue; fi
  [ "$mode" = run ] || { echo "criado: $dest"; continue; }
  # grava num temporário ao lado e só então põe no lugar, sem sobrescrever (mv -n): falha no meio não deixa arquivo
  # vazio ou truncado com o nome do destino, que a próxima rodada leria como "existe"
  tmp="$dest.bootstrap-$$"
  why=""
  if ! { mkdir -p "$(dirname "$dest")" && render "$src" > "$tmp"; }; then why="falhou ao gravar o temporário"
  elif grep -q '{{[A-Z_]*}}' "$tmp"; then why="o modelo $src tem marcador sem valor"
  elif ! mv -n "$tmp" "$dest" || [ -e "$tmp" ]; then why="o destino apareceu durante a gravação ou o mv falhou"
  fi
  [ -z "$why" ] || { rm -f "$tmp"; echo "bootstrap: $dest: $why (nada ficou no lugar dele)" >&2; exit 3; }
  echo "criado: $dest"
done

[ "$mode" = plan ] && echo "plano: nada gravado (projeto '$projeto', plugin $ref, branch padrão $branch${app:+, app $app})"
[ "$conflicts" -eq 0 ] && exit 0
echo "bootstrap: $conflicts arquivo(s) já existiam ou são link; nada foi sobrescrito"
exit 1
