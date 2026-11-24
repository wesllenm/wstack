---
name: db-evolution
description: >
  Orienta migrations EF Core, schema, dados, compatibilidade, expansão-contração,
  rollback, índices, locks e testes de banco no PostgreSQL.
---

# Database Evolution

## Objetivo

Evoluir o schema sem downtime e sem impedir a volta para a versão anterior (release N-1 funciona com o schema N).

## Quando aplicar

Toda migration, novo índice, mudança de tipo, constraint, dados de referência ou mudança de mapeamento EF que gere migration.

## Princípios

- Toda mudança considera schema, código de acesso, dados existentes, migration, compatibilidade, volume, locks e rollback.
- Migrations EF Core geradas com `dotnet ef migrations add` e revisadas como código: ler o SQL com `dotnet ef migrations script <anterior> <nova>` (vai para a pasta temporária) antes de aceitar. [DAT-10]
- Uma migration por mudança lógica, com nome descritivo.
- Para incompatibilidades, usar expansão-contração: adicionar (nullable/default) → código escreve nos dois/lê do novo → backfill → contrair numa release posterior. [DAT-01]
- Quando o MCP Toolbox estiver configurado, confirmar schema, índices, cardinalidade e planos no banco real (via `database-helper`) em vez de inferir só pelo código.
- Índice recomendado pela skill `query-plan` entra por aqui: migration própria, expansão-contração quando necessário e plano antes e depois como evidência. [DAT-06]

## Greenfield

Schema nasce com: chaves `uuid` (v7 gerado na aplicação, fora de código de workflow), `timestamptz` para datas, coluna de versão para concorrência otimista em entidades editáveis [CON-01], nomes em snake_case (convenção Npgsql; tabelas no plural, chave primária `id`, chave estrangeira `<entidade>_id`, datas `*_at`, booleanos `is_`/`has_`, restrições e índices com prefixo `pk_`, `fk_`, `ix_`, `ux_`) [NOM-02], extensões do Postgres (ex.: `vector`) habilitadas por migration quando usadas.

## Brownfield

Migrations já aplicadas no sistema existente permanecem como estão (ver Restrições).

## Restrições e cuidados

- Nunca editar migration já aplicada em ambiente compartilhado (greenfield ou brownfield); corrigir com nova migration. [DAT-09]
- Não aplicar migration produtiva, alteração destrutiva ou mudança de dados reais automaticamente (`dotnet ef database update` fica em `permissions.ask`). [DAT-10]
- Migration destrutiva (drop de coluna/tabela, mudança de tipo com perda) sempre bloqueia para humano e aciona `review-critical`. [DAT-08]
- Postgres: `CREATE INDEX` em tabela grande usa `CONCURRENTLY` (exige `migrationBuilder.Sql` fora de transação, `suppressTransaction: true`); `ALTER TABLE ... ADD COLUMN` com default volátil reescreve a tabela; `ALTER COLUMN TYPE` costuma reescrever e travar. Migration com `suppressTransaction` (CONCURRENTLY) se aplica por `IMigrator`, `dotnet ef database update`, bundle ou script NÃO idempotente com `psql -v ON_ERROR_STOP=1`; `migrations script --idempotent` embrulha o comando em `DO $EF$` e o CONCURRENTLY falha (25001), e sem `ON_ERROR_STOP` a migration é registrada sem o índice.
- Tabelas de outra ferramenta (ex.: state store do Dapr) não são gerenciadas pelo EF.

## Testes obrigatórios

- Migration aplicada em ida e volta (`Up` e `Down`) contra o banco em contêiner (Testcontainers, Postgres 18). [DAT-03] [DAT-10] [ENV-03]
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
