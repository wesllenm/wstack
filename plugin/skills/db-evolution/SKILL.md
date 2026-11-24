---
name: db-evolution
description: >
  Orienta migrations, schema, dados, compatibilidade, expansão-contração,
  rollback, índices, locks e testes de banco.
---

# Database Evolution

## Objetivo

Evoluir o schema sem downtime e sem impedir a volta para a versão anterior (release N-1 funciona com o schema N).

## Quando aplicar

Toda migration, novo índice, mudança de tipo, constraint, dados de referência ou mudança de mapeamento que gere migration.

## Princípios

- Toda mudança considera schema, código de acesso, dados existentes, migration, compatibilidade, volume, locks e rollback.
- Migrations geradas pela ferramenta do projeto e revisadas como código: ler o SQL que ela vai executar (vai para a pasta temporária) antes de aceitar.
- Uma migration por mudança lógica, com nome descritivo.
- Para incompatibilidades, usar expansão-contração: adicionar (nullable/default) → código escreve nos dois/lê do novo → backfill → contrair numa release posterior.
- Quando o MCP Toolbox estiver configurado, confirmar schema, índices, cardinalidade e planos no banco real (via `database-helper`) em vez de inferir só pelo código.
- Índice recomendado pela skill `query-plan` entra por aqui: migration própria, expansão-contração quando necessário e plano antes e depois como evidência.

## Greenfield

Schema nasce com coluna de versão para concorrência otimista nas entidades editáveis (skill `concurrency`) e com a convenção de nomes do perfil de stack.

## Brownfield

Migrations já aplicadas no sistema existente permanecem como estão (ver Restrições).

## Restrições e cuidados

- Nunca editar migration já aplicada em ambiente compartilhado (greenfield ou brownfield); corrigir com nova migration.
- Não aplicar migration produtiva, alteração destrutiva ou mudança de dados reais automaticamente (o comando que aplica migration fica em `permissions.ask`).
- Migration destrutiva (drop de coluna/tabela, mudança de tipo com perda) sempre bloqueia para humano e aciona `review-critical`.

## Testes obrigatórios

- Migration aplicada em ida e volta (`Up` e `Down`) contra o mesmo motor de banco do projeto, em ambiente descartável.
- Teste de integração do código novo contra o schema migrado.
- Em expansão-contração: código N-1 (ou o caminho antigo) funcionando com o schema N.

## Exceções e limites

Banco descartável de teste pode ser recriado; isso não vale para nenhum ambiente compartilhado.

## Checklist de saída

- [ ] SQL da migration lido;
- [ ] compatível com a release anterior;
- [ ] locks e volume avaliados (`database-reviewer`);
- [ ] ida e volta testadas;
- [ ] nada aplicado fora do ambiente local/teste.
