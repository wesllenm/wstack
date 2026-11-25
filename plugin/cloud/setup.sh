#!/usr/bin/env bash
# Setup do ambiente de nuvem. Colar no campo Setup script do ambiente em claude.ai/code (esta é a versão de
# referência, versionada no plugin wstack em cloud/setup.sh) e rodar na própria sessão quando o retrato do cloud-services.sh
# acusar falta. Detecta as stacks pelos arquivos rastreados do repositório e provisiona cada uma por uma cadeia de
# rotas: o instalador oficial; se o proxy de saída o recusar (403 é política: não insistir), a imagem oficial no
# registro, copiada com o Docker (o Engine confere o digest de cada camada); se nada servir, aviso, nunca silêncio.
# Idempotente: o que já está instalado na versão pedida é pulado. Rede: o --plan e o fim da instalação listam os hosts das
# stacks detectadas (.claude/cloud/hosts.conf e o WebFetch do settings.json) para liberar na rede do ambiente.
# Uso: setup.sh            provisiona tudo (root; a VM roda o setup como root)
#      setup.sh --plan     mostra o que faria, sem rede e sem instalar (testável: test-cloud-setup.sh)
#      setup.sh --check    lista o que falta, sem rede, inclusive o host que o proxy recusou (403) na última instalação;
#                          código 1 se faltar algo (lido pelo cloud-services.sh)
#      setup.sh --docker   só garante o daemon do Docker no ar (processo não entra no snapshot)
# Fronteira: --plan, --check e --docker tratam o repositório como DADO (não executam nada dele, não seguem link, e o
# --check, que vai para o contexto da sessão, não ecoa texto do repositório). O modo run executa código do projeto e
# das dependências como root, como qualquer build (dotnet restore avalia o MSBuild; npm, pnpm, yarn e pip têm config
# e hooks próprios): os scripts de instalação vão desligados como redução de risco, não como garantia; a fronteira é a
# VM descartável. Versão, imagem e caminho só viram argumento depois de passar num alfabeto fechado.
# Código: 0 ok (com avisos no fim, se houver); 1 em --check com falta; 2 uso errado.
set -uo pipefail

mode=run
case "${1:-}" in
  '') ;;
  --plan) mode=plan ;;
  --check) mode=check ;;
  --docker) mode=docker ;;
  *) echo "uso: setup.sh [--plan|--check|--docker]" >&2; exit 2 ;;
esac

# raiz do repositório clonado: o diretório atual quando é um checkout, senão o primeiro checkout em $HOME
repo=$(git rev-parse --show-toplevel 2> /dev/null || true)
if [ -z "$repo" ]; then
  for d in "$HOME"/*/ /home/user/*/; do
    [ -d "$d/.git" ] && { repo=${d%/}; break; }
  done
fi
[ -n "$repo" ] || { echo "setup: checkout do repositório não encontrado" >&2; exit 2; }
cd "$repo" || exit 2

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
problems=()
missing=()
note() { echo "setup: $*"; }
warn() { problems+=("$*"); echo "setup: AVISO: $*" >&2; }
plan() { echo "plano: $*"; }
lack() { missing+=("$*"); }
safe() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]]; }             # versão ou tag
safe_image() { [[ $1 =~ ^[a-z0-9][a-z0-9._/:@-]{0,199}$ ]]; }          # referência de imagem
safe_path() { [[ $1 =~ ^[~/][A-Za-z0-9._/-]{0,199}$ && $1 != *..* ]]; } # caminho absoluto (ou ~), sem ..
tracked() { git ls-files -- "$@" 2> /dev/null | grep -vE '(^|/)node_modules/'; }
# com pipefail, "lista | grep -q ." fecha o pipe cedo e o SIGPIPE de quem escreve vira falso (medido com 3000 csproj)
has_tracked() { [ -n "$(tracked "$@")" ]; }
regular() { [ -f "$1" ] && [ ! -L "$1" ]; } # arquivo do repositório lido como dado: nunca link (para .js, /dev/zero...)
name_ok() { [[ $1 =~ ^[A-Za-z0-9._/@-]{1,200}$ && $1 != -* ]]; } # pasta do repositório (@ do escopo npm) que pode aparecer em comando e no contexto
conf() { [ -f .claude/risk.conf ] && sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" .claude/risk.conf; }

# ---------- Docker ----------
docker_up() { command -v docker > /dev/null && docker info > /dev/null 2>&1; }
docker_why=""
ensure_docker() {
  docker_up && return 0
  command -v dockerd > /dev/null || { docker_why="dockerd não instalado"; return 1; }
  [ "$(id -u)" = 0 ] || { docker_why="sem root para subir o dockerd"; return 1; }
  # PID gravado antes de a VM ser retomada pode estar ocupado por outro processo, e o dockerd se recusa a subir
  # ("process with PID N is still running"): o arquivo só fica se o PID for mesmo de um dockerd.
  local pidfile=${DOCKER_PIDFILE:-/var/run/docker.pid} pid
  if [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile" 2> /dev/null)
    if ! [[ $pid =~ ^[0-9]+$ ]] || [ "$(cat "/proc/$pid/comm" 2> /dev/null)" != dockerd ]; then rm -f "$pidfile"; fi
  fi
  # sessão própria: o timeout do hook manda SIGTERM ao grupo de processos e mataria o daemon ainda subindo
  setsid nohup dockerd --pidfile "$pidfile" > /var/log/dockerd.log 2>&1 &
  for _ in $(seq 1 60); do docker_up && return 0; sleep 1; done
  docker_why="o dockerd não respondeu em 60 s (log em /var/log/dockerd.log)"
  return 1
}
docker_needed() { # Docker só para quem o usa: imagens e binários do risk.conf, compose ou Testcontainers
  [ -n "$(conf cloud_pull)$(conf cloud_extract)" ] && return 0
  has_tracked '*compose*.yml' '*compose*.yaml' && return 0
  local f
  while IFS= read -r f; do
    regular "$f" && grep -qi -- 'testcontainers' "$f" && return 0
  done < <(tracked '*.csproj' '*package.json' '*pom.xml' '*build.gradle*' '*go.mod' '*Cargo.toml' '*requirements*.txt' '*pyproject.toml')
  return 1
}
# copia <caminho> da imagem para dentro de <destino> (rota do registro: o Engine baixa e confere as camadas);
# "<pasta>/." copia o conteúdo da pasta, "<arquivo>" copia o arquivo
from_image() {
  local image=$1 src=$2 dest=$3 c
  ensure_docker || return 1
  # pull só se a imagem faltar: o Docker Hub anônimo responde 429 ao IP compartilhado da VM mesmo com a imagem no disco
  docker image inspect "$image" > /dev/null 2>&1 || docker pull -q "$image" > /dev/null || return 1
  c=$(docker create "$image" true) || return 1 # imagem sem ENTRYPOINT/CMD exige comando; ele nunca roda
  mkdir -p "$dest" && docker cp "$c:$src" "$dest/"
  local rc=$?
  docker rm "$c" > /dev/null
  return $rc
}

if [ "$mode" = docker ]; then
  docker_needed || exit 0
  ensure_docker || { echo "o daemon do Docker não subiu: $docker_why"; exit 1; }
  exit 0
fi

# ---------- detecção ----------
dotnet_repo() { [ -f global.json ] || has_tracked '*.csproj' '*.fsproj' '*.sln' '*.slnx'; }
dotnet_want() {
  local v=""
  regular global.json && v=$(tr -d '\r' < global.json | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  echo "$v"
}
dotnet_has() { # SDK exato do global.json, ou qualquer SDK quando não há versão fixada
  command -v dotnet > /dev/null || return 1
  local sdks
  sdks=$(dotnet --list-sdks 2> /dev/null)
  if [ -n "$1" ]; then grep -q "^$1 " <<< "$sdks"; else [ -n "$sdks" ]; fi
}
node_want() { # .nvmrc ou .node-version rastreado (o primeiro); "24", "v24.1.0" ou "lts/*" (lts fica com o Node da VM)
  local f v
  f=$(tracked '.nvmrc' '*/.nvmrc' '.node-version' '*/.node-version' | head -1)
  regular "$f" || return 0
  v=$(tr -d '\r[:space:]' < "$f"); v=${v#v}
  [[ $v =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] && echo "$v"
}
node_has() { command -v node > /dev/null && [[ "$(node --version 2> /dev/null)" == "v$1" || "$(node --version 2> /dev/null)" == "v$1".* ]]; }
node_dirs() { tracked '*package-lock.json' '*pnpm-lock.yaml' '*yarn.lock' | while IFS= read -r f; do dirname -- "$f"; done | sort -u; }
pw_dotnet_version() {
  tracked '*Directory.Packages.props' '*.csproj' | while IFS= read -r f; do
    regular "$f" && grep -o -- 'Include="Microsoft.Playwright"[^>]*Version="[^"]*"' "$f" 2> /dev/null
  done | sed -n 's/.*Version="\([^"]*\)".*/\1/p' | head -1
}
pw_node_version() { # versão resolvida no lockfile (npm), lido como dado pelo jq: nunca require/import
  command -v jq > /dev/null || return 0
  node_dirs | while IFS= read -r d; do
    name_ok "$d" || continue
    regular "$d/package-lock.json" || continue
    jq -r '(.packages // {}) | (.["node_modules/playwright-core"] // .["node_modules/@playwright/test"] // .["node_modules/playwright"] // {}).version // empty' < "$d/package-lock.json" 2> /dev/null
  done | head -1
}
browsers_dir() { echo "${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"; }
pw_browsers_json() { # o browsers.json do pacote restaurado diz as revisões exigidas (nunca um node_modules rastreado)
  local v=$1 d f
  f="$HOME/.nuget/packages/microsoft.playwright/$v/.playwright/package/browsers.json"
  regular "$f" && echo "$f"
  while IFS= read -r d; do
    f="$d/node_modules/playwright-core/browsers.json"
    name_ok "$d" && regular "$f" && [ -z "$(git ls-files -- ":(literal)$d/node_modules" 2> /dev/null)" ] && echo "$f"
  done < <(node_dirs)
}
pw_has() { # todo navegador "installByDefault" do browsers.json tem <nome>-<revisão> completo (marcador do Playwright)
  local files f dir
  command -v jq > /dev/null || return 1
  files=$(pw_browsers_json "$1" | head -1)
  [ -n "$files" ] || return 1
  dir=$(browsers_dir)
  local names
  names=$(timeout 10 jq -r '.browsers[] | select(.installByDefault) | "\(.name | gsub("-"; "_"))-\(.revision)"' < "$files" 2> /dev/null) || return 1
  [ -n "$names" ] || return 1
  for f in $names; do
    safe "$f" || return 1 # nome e revisão vêm de arquivo: nada de / ou .. no caminho
    [ -f "$dir/$f/INSTALLATION_COMPLETE" ] || return 1 # cópia interrompida deixa a pasta sem o marcador
  done
}
rust_repo() { has_tracked 'Cargo.toml' '*/Cargo.toml'; }
python_reqs() { tracked '*requirements*.txt'; }
go_repo() { has_tracked 'go.mod' '*/go.mod'; }

# ---------- rede: hosts por stack (.claude/cloud/hosts.conf) e recusas do proxy ----------
# O proxy da nuvem recusa com 403 no CONNECT o host fora da rede liberada do ambiente. fetch registra a recusa num arquivo
# de estado (o modo run zera a cada execução) e o --check a aponta sem rede; o host só aparece no --check se estiver no
# hosts.conf (o destino de um redirecionamento é texto de fora e iria para o contexto da sessão).
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/cloud-setup
refused_file=$state_dir/recusados
host_ok() { [[ $1 =~ ^(\*\.)?[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]; }
fetch() { # fetch <stack> <url> <arquivo>
  local w code url host
  w=$(curl -fsSL -w '%{http_connect} %{url_effective}' -o "$3" "$2" 2> /dev/null) && return 0
  read -r code url <<< "$w"
  host=${url#*://}; host=${host%%[/:?#]*}; host=${host,,}
  if [ "$code" = 403 ] && host_ok "$host"; then mkdir -p "$state_dir" && printf '%s %s\n' "$1" "$host" >> "$refused_file"; fi
  return 1
}
[ "$mode" = run ] && rm -f "$refused_file"
host_stacks=() # stacks detectadas, preenchidas abaixo
host_lines() { # "<host> <stack>" do hosts.conf das stacks detectadas, mais os domínios do WebFetch (documentação)
  local s h _ want
  if regular .claude/cloud/hosts.conf; then
    while read -r s h _; do
      [[ $s =~ ^[a-z]+$ ]] && host_ok "$h" || continue
      for want in "${host_stacks[@]+"${host_stacks[@]}"}"; do [ "$s" = "$want" ] && echo "$h $s"; done
    done < <(tr -d '\r' < .claude/cloud/hosts.conf | grep -v '^[[:space:]]*#')
  fi
  if regular .claude/settings.json && command -v jq > /dev/null; then
    jq -r '.permissions.allow[]? | strings | capture("^WebFetch\\(domain:(?<d>[^)]+)\\)$").d' < .claude/settings.json 2> /dev/null |
      while IFS= read -r h; do host_ok "$h" && echo "$h documentação"; done
  fi
}
print_hosts() { # um host por linha, com as stacks que o usam
  local out
  out=$(host_lines | sort -u | awk '{s[$1] = s[$1] (s[$1] ? ", " : "") $2} END {for (h in s) print "- " h " (" s[h] ")"}' | sort)
  [ -n "$out" ] || return 0
  echo "hosts para liberar na rede do ambiente (stacks detectadas; lista em .claude/cloud/hosts.conf):"
  echo "$out"
}

# ---------- .NET ----------
if dotnet_repo; then
  host_stacks+=(dotnet)
  want=$(dotnet_want)
  if [ -n "$want" ] && ! safe "$want"; then warn "versão do global.json fora do alfabeto permitido; ignorada"; want=""; fi
  tag=${want:-latest}
  if dotnet_has "$want"; then
    [ "$mode" = plan ] && plan "dotnet: SDK ${want:-qualquer} já instalado"
  elif [ "$mode" = plan ]; then
    plan "dotnet: instalar SDK ${want:-mais recente} (dotnet-install.sh; senão imagem mcr.microsoft.com/dotnet/sdk:$tag)"
  elif [ "$mode" = check ]; then
    if [ -n "$want" ]; then lack "SDK do .NET fixado no global.json"; else lack "SDK do .NET"; fi
  else
    dir=/usr/share/dotnet
    ok=1
    if fetch dotnet https://dot.net/v1/dotnet-install.sh /tmp/dotnet-install.sh; then
      if [ -n "$want" ]; then bash /tmp/dotnet-install.sh --version "$want" --install-dir "$dir" --no-path || ok=0
      else bash /tmp/dotnet-install.sh --channel LTS --install-dir "$dir" --no-path || ok=0; fi
    else ok=0; fi
    if [ "$ok" = 0 ]; then
      note "dotnet-install.sh recusado ou falhou; usando a imagem mcr.microsoft.com/dotnet/sdk:$tag"
      if from_image "mcr.microsoft.com/dotnet/sdk:$tag" /usr/share/dotnet/. "$dir"; then
        docker rmi "mcr.microsoft.com/dotnet/sdk:$tag" > /dev/null 2>&1 || true # ~1,3 GB que o snapshot não precisa
      else
        warn "SDK do .NET não instalado (instalador e imagem falharam)"
      fi
    fi
    ln -sf "$dir/dotnet" /usr/local/bin/dotnet
  fi
  if [ "$mode" = run ] && dotnet_has "$want"; then
    note "dotnet $(dotnet --version)"
    [ -f .config/dotnet-tools.json ] && { dotnet tool restore || warn "dotnet tool restore falhou"; }
    # restaura a solução da raiz para o cache do NuGet entrar no snapshot; feed privado precisa de segredo de rede
    sln=""
    for f in ./*.slnx ./*.sln; do [ -f "$f" ] && { sln=$f; break; }; done
    if [ -n "$sln" ]; then dotnet restore "$sln" || warn "dotnet restore falhou; as sessões restauram sob demanda"; fi
  elif [ "$mode" = plan ]; then
    plan "dotnet: restaurar ferramentas e a solução da raiz"
  fi
fi

# ---------- Node: versão fixada no repositório ----------
nwant=$(node_want)
{ [ -n "$nwant" ] || [ -n "$(node_dirs)" ]; } && host_stacks+=(node)
if [ -n "$nwant" ] && ! node_has "$nwant"; then
  case "$mode" in
    plan) plan "node: instalar Node $nwant (nodejs.org/dist com SHASUMS256; senão imagem node:$nwant) e ligar em ~/.local/bin" ;;
    check) lack "Node $nwant (a VM tem $(node --version 2> /dev/null || echo nenhum))" ;;
    run)
      tmp=$(mktemp -d)
      full=""
      fetch node https://nodejs.org/dist/index.json "$tmp/index.json" \
        && full=$(jq -r --arg v "v$nwant" '[.[] | select(.version == $v or (.version | startswith($v + ".")))][0].version // empty' < "$tmp/index.json" 2> /dev/null)
      dest=/usr/local/lib/nodejs/node-$nwant
      ok=0
      if [[ $full =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        tarball=node-$full-linux-x64.tar.xz
        if fetch node "https://nodejs.org/dist/$full/$tarball" "$tmp/$tarball" && fetch node "https://nodejs.org/dist/$full/SHASUMS256.txt" "$tmp/SHASUMS256.txt" \
          && (cd "$tmp" && grep " $tarball\$" SHASUMS256.txt | sha256sum -c --quiet); then
          mkdir -p "$dest" && tar -xJf "$tmp/$tarball" -C "$dest" --strip-components=1 && ok=1
        fi
      fi
      rm -rf "$tmp"
      if [ "$ok" = 0 ]; then
        note "nodejs.org recusado ou falhou; usando a imagem node:$nwant"
        from_image "node:$nwant" /usr/local/. "$dest" && ok=1 && docker rmi "node:$nwant" > /dev/null 2>&1
      fi
      if [ "$ok" = 1 ]; then
        mkdir -p "$HOME/.local/bin"
        for b in node npm npx corepack; do [ -e "$dest/bin/$b" ] && ln -sf "$dest/bin/$b" "$HOME/.local/bin/$b"; done
        # shell de login: o /etc/profile.d da imagem pode pôr o Node dela na frente; este arquivo vem depois na ordem
        [ -d /etc/profile.d ] && [ -w /etc/profile.d ] && printf "export PATH=\"%s/bin:\$PATH\"\n" "$dest" > /etc/profile.d/zz-cloud-setup-node.sh
        hash -r
        node_has "$nwant" || warn "Node $nwant instalado em $dest, mas outro vem antes no PATH ($(command -v node)): ponha ~/.local/bin antes"
      else
        warn "Node $nwant não instalado (nodejs.org e imagem falharam)"
      fi
      ;;
  esac
fi

# ---------- Node (cada pasta com lockfile, instalada DENTRO dela: o corepack escolhe o gerenciador pelo package.json
# do diretório atual). Scripts, pnpmfile, yarnPath e .corepack.env desligados: redução de risco, não garantia (cabeçalho).
node_missing=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  name_ok "$d" || { warn "pasta com lockfile e nome fora do alfabeto permitido; ignorada"; continue; }
  if ! command -v node > /dev/null; then
    [ "$mode" = plan ] && plan "node: Node ausente para $d (instalar pela imagem do ambiente)"
    [ "$mode" = check ] && node_missing=$((node_missing + 1))
    [ "$mode" = run ] && warn "Node ausente; dependências de $d não instaladas"
    continue
  fi
  cp_env=(env COREPACK_ENV_FILE=0 COREPACK_ENABLE_UNSAFE_CUSTOM_URLS=0)
  if [ -f "$d/package-lock.json" ]; then cmd=(npm ci --ignore-scripts --git=git --no-audit --no-fund)
  elif [ -f "$d/pnpm-lock.yaml" ]; then cmd=("${cp_env[@]}" corepack pnpm install --frozen-lockfile --ignore-scripts --ignore-pnpmfile)
  elif [ -f "$d/.yarnrc.yml" ]; then cmd=("${cp_env[@]}" YARN_IGNORE_PATH=1 YARN_ENABLE_SCRIPTS=false corepack yarn install --immutable --mode=skip-build)
  else cmd=("${cp_env[@]}" YARN_IGNORE_PATH=1 corepack yarn install --frozen-lockfile --ignore-scripts); fi
  case "$mode" in
    plan) plan "node: (em $d) ${cmd[*]}" ;;
    check) [ -d "$d/node_modules" ] || node_missing=$((node_missing + 1)) ;;
    run) (cd "$d" && "${cmd[@]}") || warn "instalação das dependências do Node em $d falhou" ;;
  esac
done < <(node_dirs)
# o --check vai para o contexto da sessão: conta as pastas, sem ecoar nomes do repositório (o --plan lista quais)
[ "$node_missing" -gt 0 ] && lack "dependências do Node em $node_missing pasta(s) (setup.sh --plan lista quais)"

# ---------- Playwright (navegadores da revisão que o pacote fixa) ----------
for kind in dotnet node; do
  if [ "$kind" = dotnet ]; then v=$(pw_dotnet_version); image_repo=mcr.microsoft.com/playwright/dotnet
  else v=$(pw_node_version); image_repo=mcr.microsoft.com/playwright; fi
  [ -n "$v" ] || continue
  host_stacks+=(playwright)
  safe "$v" || { warn "versão do Playwright ($kind) fora do alfabeto permitido; ignorada"; continue; }
  dir=$(browsers_dir)
  if pw_has "$v"; then
    [ "$mode" = plan ] && plan "playwright ($kind) $v: navegadores já em $dir"
    continue
  fi
  case "$mode" in
    plan) plan "playwright ($kind) $v: copiar /ms-playwright da imagem $image_repo:v$v-noble para $dir" ;;
    check) lack "navegadores do Playwright ($kind) em $dir" ;;
    run)
      # o instalador oficial baixa de cdn.playwright.dev; a imagem traz as mesmas revisões
      if from_image "$image_repo:v$v-noble" /ms-playwright/. "$dir"; then
        docker rmi "$image_repo:v$v-noble" > /dev/null 2>&1 || true # ~2 GB que o snapshot não precisa
      else
        warn "navegadores do Playwright $v não instalados"
      fi
      ;;
  esac
done

# ---------- Rust ----------
if rust_repo; then
  host_stacks+=(rust)
  if command -v cargo > /dev/null; then
    [ "$mode" = plan ] && plan "rust: cargo fetch"
    [ "$mode" = run ] && { cargo fetch || warn "cargo fetch falhou"; }
  else
    case "$mode" in
      plan) plan "rust: instalar pelo rustup (sh.rustup.rs); senão copiar da imagem rust:latest" ;;
      check) lack "toolchain do Rust" ;;
      run)
        if ! { fetch rust https://sh.rustup.rs /tmp/rustup.sh && sh /tmp/rustup.sh -y --profile minimal; }; then
          # os caminhos padrão do rustup (~/.cargo e ~/.rustup), para os proxies acharem o toolchain sem variável
          if from_image rust:latest /usr/local/cargo/. "$HOME/.cargo" && from_image rust:latest /usr/local/rustup/. "$HOME/.rustup"; then
            ln -sf "$HOME"/.cargo/bin/* /usr/local/bin/
          else
            warn "Rust não instalado"
          fi
        fi
        export PATH="$HOME/.cargo/bin:$PATH"
        command -v cargo > /dev/null && { cargo fetch || warn "cargo fetch falhou"; }
        ;;
    esac
  fi
fi

# ---------- Python (requirements em .venv na raiz) ----------
reqs=$(python_reqs)
if [ -n "$reqs" ]; then
  host_stacks+=(python)
  case "$mode" in
    plan) plan "python: .venv com $(echo "$reqs" | tr '\n' ' ')" ;;
    check) [ -d .venv ] || lack "ambiente Python (.venv)" ;;
    run)
      python3 -m venv .venv || warn "python3 -m venv falhou"
      while IFS= read -r r; do .venv/bin/pip install -q -r "$r" || warn "pip install -r $r falhou"; done <<< "$reqs"
      ;;
  esac
fi

# ---------- Go ----------
if go_repo; then
  host_stacks+=(go)
  if command -v go > /dev/null; then
    [ "$mode" = plan ] && plan "go: go mod download"
    [ "$mode" = run ] && { go mod download || warn "go mod download falhou"; }
  else
    case "$mode" in
      plan) plan "go: copiar /usr/local/go da imagem golang:latest" ;;
      check) lack "toolchain do Go" ;;
      run)
        if from_image golang:latest /usr/local/go/. /usr/local/go; then
          ln -sf /usr/local/go/bin/* /usr/local/bin/
          go mod download || warn "go mod download falhou"
        else
          warn "Go não instalado"
        fi
        ;;
    esac
  fi
fi

# ---------- Docker, imagens e binários tirados de imagem (risk.conf) ----------
mapfile -t pulls < <(conf cloud_pull)
mapfile -t extracts < <(conf cloud_extract)
if docker_needed; then
  host_stacks+=(docker)
  case "$mode" in
    plan) plan "docker: subir o daemon" ;;
    check) docker_up || lack "daemon do Docker (setup.sh --docker)" ;;
    run) ensure_docker || warn "o daemon do Docker não subiu: $docker_why" ;;
  esac
fi
# cloud_pull = <comando> (o risk.conf é protegido; o comando roda como está, igual ao cloud_service)
for cmd in "${pulls[@]+"${pulls[@]}"}"; do
  [ -n "$cmd" ] || continue
  case "$mode" in
    plan) plan "pull: $cmd" ;;
    run) bash -c "$cmd" || warn "falhou: $cmd" ;;
  esac
done
# cloud_extract = <imagem> <caminho na imagem> -> <destino>   (binário que só existe em imagem, como o daemon de um runtime distribuído só por imagem)
for line in "${extracts[@]+"${extracts[@]}"}"; do
  [ -n "$line" ] || continue
  if [[ ! $line =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]*-\>[[:space:]]*([^[:space:]]+)$ ]]; then
    warn "cloud_extract inválido: $line"; continue
  fi
  image=${BASH_REMATCH[1]} src=${BASH_REMATCH[2]} dest=${BASH_REMATCH[3]}
  if ! safe_image "$image" || ! safe_path "$src" || ! safe_path "$dest"; then warn "cloud_extract fora do alfabeto permitido: $line"; continue; fi
  dest=${dest/#\~/$HOME}
  case "$mode" in
    plan) plan "extract: $src de $image para $dest" ;;
    check) [ "$(cat "$dest/.$(basename "$src").ref" 2> /dev/null)" = "$image" ] || lack "$(basename "$src") de $image em $dest" ;;
    run)
      # o marcador guarda a imagem de onde o binário veio: trocar a versão ou o digest no risk.conf reextrai
      ref="$dest/.$(basename "$src").ref"
      [ -e "$dest/$(basename "$src")" ] && [ "$(cat "$ref" 2> /dev/null)" = "$image" ] && continue
      if from_image "$image" "$src" "$dest"; then
        printf '%s\n' "$image" > "$ref"
        note "$(basename "$src") de $image em $dest"
      else
        warn "falhou: extrair $src de $image"
      fi
      ;;
  esac
done

# ---------- plugin wstack na versão que o projeto fixa ----------
# O .claude/settings.json do projeto (modelo do /wstack:bootstrap) declara o marketplace wstack com a referência (tag
# vX.Y.Z ou commit) e liga o plugin; a sessão na nuvem não instala sozinha pelo settings.json do projeto (docs/sonda.md,
# fato 1), então o setup instala no escopo do usuário. O projeto que cita o plugin sem ref não instala por aqui (o
# ambiente do próprio wstack instala do clone). O projeto que não cita o plugin ainda não passou pelo /wstack:bootstrap:
# recebe a maior tag v<versão> publicada, para a primeira sessão na nuvem já ter o bootstrap (que fixa essa mesma tag);
# sem o risk.conf o plugin fica inerte, salvo as travas (docs/decisions.md, plugin antes do bootstrap na nuvem).
# O arquivo é lido como dado pelo jq; repositório e ref só viram argumento depois do alfabeto fechado.
WSTACK_REPO=wesllenm/wstack
pin_ok() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}#[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ && $1 != *..* ]]; }
wstack_pin() { # "<dono>/<repo>#<ref>"; "!" se o projeto liga o plugin e a referência não pôde ser lida; "?" se não cita o
  # plugin (sem bootstrap); nada se cita sem ref
  regular .claude/settings.json && grep -q '"wstack@wstack"' .claude/settings.json || { echo '?'; return 0; }
  command -v jq > /dev/null || { echo '!'; return 0; }
  local r
  r=$(jq -r '.extraKnownMarketplaces.wstack.source as $s | if .enabledPlugins["wstack@wstack"] == true and $s.source == "github"
    and ($s.ref != null) then "\($s.repo)#\($s.ref)" else empty end' < .claude/settings.json 2> /dev/null) || { echo '!'; return 0; }
  [ -z "$r" ] && return 0
  if pin_ok "$r"; then echo "$r"; else echo '!'; fi
}
wstack_ok() { # wstack_ok <pin>: o marketplace do usuário está nessa ref e o plugin instalado é ela (tag pela versão, commit pelo sha)
  local ref=${1#*#} known v c
  known=$(jq -r '.wstack.source | "\(.repo)#\(.ref // "")"' "$HOME/.claude/plugins/known_marketplaces.json" 2> /dev/null)
  [ "$known" = "$1" ] || return 1
  read -r v c < <(jq -r '.plugins["wstack@wstack"][]? | select(.scope == "user") | "\(.version) \(.gitCommitSha)"' \
    "$HOME/.claude/plugins/installed_plugins.json" 2> /dev/null)
  [ -n "${v:-}" ] || return 1
  if [[ $ref =~ ^v[0-9] ]]; then [ "$ref" = "v$v" ]
  elif [[ $ref =~ ^[0-9a-f]{7,40}$ ]]; then [[ ${c:-} == "$ref"* ]]
  else return 0; fi # branch: a ref do marketplace basta
}
wstack_any() { # algum wstack instalado no escopo do usuário
  [ -n "$(jq -r '.plugins["wstack@wstack"][]? | select(.scope == "user") | .version' \
    "$HOME/.claude/plugins/installed_plugins.json" 2> /dev/null)" ]
}
latest_tag() { # maior tag v<maior>.<menor>.<correção> publicada; vazio sem rede ou sem tag (pré-release fica de fora). Fora do
  # repositório do projeto (-C /): o .git/config local (insteadOf, proxy, credencial) não escolhe de onde vem o plugin
  GIT_TERMINAL_PROMPT=0 timeout 60 git -C / ls-remote --tags --refs "https://github.com/$WSTACK_REPO" 2> /dev/null \
    | sed -n 's|^[0-9a-f]*[[:space:]]*refs/tags/||p' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}
pin=$(wstack_pin) fresh=""
if [ "$pin" = '?' ]; then
  pin=""
  host_stacks+=(wstack)
  if wstack_any; then
    [ "$mode" = plan ] && plan "wstack: plugin já instalado (projeto sem bootstrap)"
  else
    case "$mode" in
      plan) plan "wstack: instalar o plugin da última tag v<versão> de $WSTACK_REPO (projeto sem bootstrap; o /wstack:bootstrap fixa a versão)" ;;
      check) lack "plugin wstack (projeto sem bootstrap; rodar setup.sh)" ;;
      run)
        tag=$(latest_tag)
        if [ -n "$tag" ] && pin_ok "$WSTACK_REPO#$tag"; then pin="$WSTACK_REPO#$tag" fresh=1
        else warn "plugin wstack não instalado: nenhuma tag v<versão> de $WSTACK_REPO alcançável (rede, ou github.com fora da rede do ambiente)"; fi
        ;;
    esac
  fi
fi
if [ "$pin" = '!' ]; then
  # texto fixo: o valor do repositório não vai para o contexto da sessão
  msg="referência do plugin wstack no .claude/settings.json ilegível (jq ausente, JSON inválido ou ref fora do alfabeto): plugin não instalado"
  case "$mode" in plan | run) warn "$msg" ;; check) lack "$msg" ;; esac
elif [ -n "$pin" ]; then
  [ -n "$fresh" ] || host_stacks+=(wstack)
  if wstack_ok "$pin"; then
    [ "$mode" = plan ] && plan "wstack: plugin já instalado de $pin"
  else
    case "$mode" in
      plan) plan "wstack: instalar o plugin de $pin (claude plugin marketplace add e install, escopo do usuário)" ;;
      check) lack "plugin wstack na versão fixada no .claude/settings.json (rodar setup.sh)" ;;
      run)
        if ! command -v claude > /dev/null; then warn "claude ausente: plugin wstack de $pin não instalado"
        else
          # a mesma entrada com outra ref é recusada pelo claude: sai e volta na ref nova. O remove desinstala o plugin
          # (Claude Code 2.1.332), então, se a ref nova falhar (tag ainda não publicada, rede), volta a anterior: ficar sem o
          # plugin é ficar sem as travas dele
          prev=$(jq -r '.wstack.source | select(.source == "github") | "\(.repo)#\(.ref // "")"' \
            "$HOME/.claude/plugins/known_marketplaces.json" 2> /dev/null)
          pin_ok "$prev" || prev=""
          claude plugin marketplace remove wstack > /dev/null 2>&1
          if claude plugin marketplace add "$pin" && claude plugin install wstack@wstack; then
            wstack_ok "$pin" && note "plugin wstack de $pin" || warn "plugin wstack instalado, mas o registro não confere com $pin"
          elif [ -n "$prev" ] && [ "$prev" != "$pin" ] && { claude plugin marketplace remove wstack > /dev/null 2>&1
            claude plugin marketplace add "$prev" && claude plugin install wstack@wstack; }; then
            warn "plugin wstack de $pin não instalado (claude plugin falhou); mantido o anterior, $prev"
          else
            warn "plugin wstack de $pin não instalado (claude plugin falhou) e nenhum anterior voltou: as sessões ficam sem as travas do plugin"
          fi
        fi
        ;;
    esac
  fi
fi

# ---------- git: repositório bare só explícito ----------
# O git descobre um repositório bare pela pasta atual. Um bare forjado pela ferramenta de escrita (HEAD, objects, refs e
# config, sem .git no nome, que o write-guard não barra) faria um git status do allow executar a config dele.
git_ge_238() { [[ $(git version) =~ ([0-9]+)\.([0-9]+) ]] && { [ "${BASH_REMATCH[1]}" -gt 2 ] || [ "${BASH_REMATCH[2]}" -ge 38 ]; }; } # antes, a chave é ignorada
bare_ok() { git_ge_238 && [ "$(git config --global --get safe.bareRepository 2> /dev/null)" = explicit ]; }
case "$mode" in
  plan) bare_ok || plan "git: safe.bareRepository=explicit na config global" ;;
  check) bare_ok || lack "safe.bareRepository=explicit na config global do git (git 2.38 ou mais novo)" ;;
  run)
    git_ge_238 || warn "git anterior ao 2.38 ignora safe.bareRepository: atualize o git"
    [ "$(git config --global --get safe.bareRepository 2> /dev/null)" = explicit ] || git config --global safe.bareRepository explicit || warn "falhou: git config --global safe.bareRepository explicit"
    ;;
esac

# ---------- rede ----------
listed() { # listed <host> <stack>: imprime a entrada do hosts.conf da stack que cobre o host (ele mesmo ou um curinga
  # *.<sufixo>); o --check ecoa a entrada, nunca o prefixo que veio de fora
  local h s
  while read -r h s; do
    [ "$s" = "$2" ] || continue
    if [ "$h" = "$1" ] || [[ $h == \*.* && $1 == *."${h#\*.}" ]]; then echo "$h"; return 0; fi
  done < <(host_lines)
  return 1
}
if regular "$refused_file"; then
  while read -r s h; do
    [[ $s =~ ^[a-z]+$ ]] && host_ok "$h" || continue
    case "$mode" in
      plan) plan "rede: o proxy recusou $h ($s) na última instalação" ;;
      check)
        if e=$(listed "$h" "$s"); then lack "host $e recusado pelo proxy ($s): liberar na rede do ambiente"
        else lack "host fora do hosts.conf recusado pelo proxy ($s): setup.sh --plan mostra qual"; fi
        ;;
    esac
  done < <(sort -u "$refused_file")
fi
[ "$mode" = check ] || print_hosts

# ---------- resumo ----------
if [ "$mode" = check ]; then
  [ "${#problems[@]}" -gt 0 ] && lack "${#problems[@]} aviso(s) do setup (setup.sh --plan mostra quais)"
  [ "${#missing[@]}" -eq 0 ] && exit 0
  printf -- '- falta: %s\n' "${missing[@]}"
  exit 1
fi
[ "$mode" = plan ] && exit 0
if [ "${#problems[@]}" -eq 0 ]; then
  note "concluído"
else
  note "concluído com ${#problems[@]} aviso(s):"
  printf -- '- %s\n' "${problems[@]}"
fi
exit 0
