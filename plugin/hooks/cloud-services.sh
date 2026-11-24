#!/usr/bin/env bash
# Hook SessionStart para sessões na nuvem: sobe os serviços de que a aplicação precisa (banco, cache,
# fila) e espera ficarem prontos. O snapshot do ambiente guarda imagens e pacotes, não processos, então os
# serviços sobem a cada sessão. Fora da nuvem (CLAUDE_CODE_REMOTE diferente de true) não faz nada.
# Configuração no .claude/risk.conf:
#   cloud_service = <comando que sobe um serviço>     ex.: cloud_service = docker compose -f compose.dev.yml up -d sql redis
#   cloud_ready = <comando que sai 0 quando pronto>   ex.: cloud_ready = docker compose -f compose.dev.yml exec -T sql /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT 1"
#   cloud_ready_timeout = 180                         segundos para todos ficarem prontos
# Antes dos serviços, sobe o daemon do Docker e põe no contexto o que falta do ambiente por stack (setup.sh --check),
# com o comando que corrige na própria sessão.
# A saída vai para o contexto da sessão. Nunca falha a sessão: serviço que não sobe vira aviso para o lead.
set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
root=${CLAUDE_PROJECT_DIR:-$(pwd)}
conf="$root/.claude/risk.conf"
cd "$root" || exit 0

# Orçamento: o hook morre em 300 s (settings.json); Docker e retrato usam no máximo 130 s e os serviços, o que sobrar até 280 s.
budget=280
setup="$(cd "$(dirname "$0")/.." && pwd -P)/cloud/setup.sh"
if [ -f "$setup" ]; then
  # Só o stdout do setup chega ao contexto, e só as linhas que o próprio setup formata: o stderr pode citar nomes de
  # arquivo do repositório (mensagens de erro de ferramentas), e texto do repositório no contexto é instrução em potencial.
  if ! why=$(timeout 70 bash "$setup" --docker 2> /dev/null); then
    why=$(grep -m1 '^o daemon do Docker não subiu: ' <<< "$why")
    echo "Sessão na nuvem: ${why:-o daemon do Docker não subiu (prazo de 70 s esgotado)}; tentar 'bash $setup --docker'."
  fi
  lacking=$(timeout 60 bash "$setup" --check 2> /dev/null)
  case $? in
    0) ;;
    1)
      echo "Sessão na nuvem: o ambiente não tem tudo o que as stacks do projeto pedem:"
      grep '^- falta: ' <<< "$lacking"
      echo "Rodar 'bash $setup' na sessão (idempotente) antes de implementar; o que ele não resolver vira bloqueio registrado."
      ;;
    *) echo "Sessão na nuvem: a conferência do ambiente não concluiu (setup.sh --check); rodar 'bash $setup --check' na sessão." ;;
  esac
fi

[ -f "$conf" ] || exit 0 # sem risk.conf, nenhum serviço a subir (o retrato acima vale mesmo assim)
val() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$conf"; }
mapfile -t services < <(val cloud_service)
mapfile -t ready < <(val cloud_ready)
[ "${#services[@]}" -gt 0 ] || [ "${#ready[@]}" -gt 0 ] || exit 0
limit=$(val cloud_ready_timeout | grep -E '^[0-9]+$' | tail -1)
limit=${limit:-180}
log=$(mktemp "${TMPDIR:-/tmp}/cloud-services.XXXXXX")
left() { local l=$((budget - SECONDS)); echo $((l > 1 ? l : 1)); }

problems=()
for cmd in "${services[@]+"${services[@]}"}"; do
  timeout "$(left)" bash -c "$cmd" >> "$log" 2>&1 || problems+=("não subiu: $cmd")
done

[ "$(left)" -lt "$limit" ] && limit=$(left)
deadline=$((SECONDS + limit))
for cmd in "${ready[@]+"${ready[@]}"}"; do
  until timeout "$(left)" bash -c "$cmd" >> "$log" 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then problems+=("não ficou pronto em ${limit}s: $cmd"); break; fi
    sleep 3
  done
done

if [ "${#problems[@]}" -eq 0 ]; then
  echo "Sessão na nuvem: ${#services[@]} serviço(s) no ar e prontos (cloud_service no risk.conf)."
else
  echo "Sessão na nuvem: problema ao subir serviços; log em $log"
  printf -- '- %s\n' "${problems[@]}"
  echo "Testes de integração e a condução da verify-<app> dependem deles: resolver antes de implementar ou registrar o bloqueio."
fi
exit 0
