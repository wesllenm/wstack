# PostgreSQL — referência de avaliação de queries

Versões cobertas: 18 (dev, imagem do AppHost) e 18 (produção, suposição do bootstrap — confirmar com o cliente piloto).
Documentação conferida: PostgreSQL 18.6 em 2026-10-23. Revisar ao mudar versão principal.

## Regras dependentes de versão

- 12+: CTE não recursiva, sem efeito colateral e referenciada uma vez é incorporada à query (inlined). Use `MATERIALIZED` só quando a barreira de otimização for desejada (por exemplo, função cara referenciada duas vezes); `NOT MATERIALIZED` força a incorporação. [https://www.postgresql.org/docs/18/queries-with.html]
- 11+: `INCLUDE` em índice B-tree adiciona colunas não-chave para index-only scan; só vale a pena se a tabela não muda tanto a ponto de o visibility map ficar majoritariamente desmarcado. Expressões não podem ser incluídas. [https://www.postgresql.org/docs/18/indexes-index-only-scans.html]
- 16+: `EXPLAIN (GENERIC_PLAN)` aceita placeholders `$1` e mostra o plano genérico de comando preparado; não combina com `ANALYZE`. [https://www.postgresql.org/docs/18/sql-explain.html]
- 18: `EXPLAIN ANALYZE` já inclui `BUFFERS` automaticamente; `SERIALIZE`, `WAL` e `MEMORY` ajudam a separar custo de rede/serialização, WAL e planejamento. [https://www.postgresql.org/docs/18/sql-explain.html]

## Regras gerais do motor

- `plan_cache_mode` (default `auto`) escolhe entre plano custom e genérico para comandos preparados; o Npgsql prepara comandos automaticamente quando configurado. Se o plano genérico for ruim para valores raros, comparar com `GENERIC_PLAN` antes de propor `force_custom_plan`. [https://www.postgresql.org/docs/18/runtime-config-query.html]
- `random_page_cost` default 4.0 pressupõe disco rotacional; em SSD/nuvem costuma ser reduzido. Divergência entre dev e produção muda a escolha entre index scan e seq scan: registrar o valor dos dois. [https://www.postgresql.org/docs/18/runtime-config-query.html]
- Colunas correlacionadas (ex.: `tenant_id` + `system_id`) geram subestimativa de linhas; `CREATE STATISTICS (dependencies | ndistinct | mcv)` corrige. É mudança de schema: recomendar. `dependencies` só ajuda igualdade e `IN` com constantes. [https://www.postgresql.org/docs/18/planner-stats.html]
- Índice parcial para filtros fixos frequentes (ex.: demandas não encerradas `WHERE state NOT IN (...)`); o planner só o usa se provar que o `WHERE` da query implica o predicado, e não reconhece isso com parâmetro (`x < $1`). [https://www.postgresql.org/docs/18/indexes-partial.html]
- `jsonb` consultado com `@>`, `@?`, `@@`: índice GIN; `jsonb_path_ops` é menor e mais específico, mas não atende `?` (existência de chave). [https://www.postgresql.org/docs/18/datatype-json.html#JSON-INDEXING]
- `OFFSET` grande é ineficiente: as linhas puladas são computadas no servidor. Paginar por keyset com `ORDER BY` único. [https://www.postgresql.org/docs/18/queries-limit.html]
- `SELECT ... FOR UPDATE` e escritas concorrentes: ordem consistente de aquisição de locks para evitar deadlock; o Postgres detecta e aborta uma das transações. [https://www.postgresql.org/docs/18/explicit-locking.html]

## Lacunas (follow-up)

- pgvector (HNSW/IVFFlat, `ef_search`, filtro combinado com índice vetorial): documentação oficial fica em github.com/pgvector, fora dos domínios liberados. Até decisão de liberar o domínio, avaliar busca vetorial só pelo plano e marcar recomendações como **não conclusivo** quando dependerem de regra da extensão.

## Como obter evidência

- Caminho previsto: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` pela tool de SQL do prebuilt `postgres` do MCP Toolbox, com `SET statement_timeout = '5s'` na mesma chamada. **Ainda não validado** (banco e Toolbox inexistentes no bootstrap).
- Permissões do usuário somente leitura: `CONNECT` no banco, `USAGE` no schema, `SELECT` nas tabelas; `pg_read_all_stats` para `pg_stat_statements` e estatísticas.
- Nós a procurar no JSON: `Seq Scan`, `Rows Removed by Filter`, `Heap Fetches`, `Sort Method` (external), divergência entre `Plan Rows` e `Actual Rows`, `Shared Read Blocks` alto.

## Aprendizado (S3, PostgreSQL 18)

- Com Npgsql, `EXPLAIN (GENERIC_PLAN)` com `$1` enviado como parâmetro devolve plano custom (valor literal no `Index Cond`). O plano genérico real sai com `PREPARE` + `EXPLAIN EXECUTE` sob `SET plan_cache_mode = force_generic_plan` (só diagnóstico, em conexão descartável); o `Index Cond` mostra `$1`. Pelo MCP Toolbox `GENERIC_PLAN` falha porque a ferramenta exige o bind. Fontes: https://www.postgresql.org/docs/18/sql-explain.html e https://www.postgresql.org/docs/18/sql-prepare.html
- `EXPLAIN` de `UPDATE`/`INSERT` exige o privilégio da operação: o usuário somente leitura não gera plano de escrita (SQLSTATE 42501).

## Aprendizado (S5.7, PostgreSQL 18)

- `EXISTS`/`Any` correlacionado pode virar join (semi-join), e, quando o planner desconhece uma correlação entre colunas (ex.: `state` do filtro × `id` da ordenação), o plano pode perder o limite na chave de junção (Merge Join lendo as duas pontas inteiras, medido no reconciliador). A subconsulta escalar correlacionada (`(SELECT max(...) ... WHERE ... = outer.id) < @x`) mantém uma busca indexada por linha do lado externo e deixa o `LIMIT` parar a leitura. Em EF Core: `Max(e => (T?)e.Coluna)` sobre a coleção filtrada, não `Any`. Fonte: https://www.postgresql.org/docs/18/planner-stats.html
- Coluna que aparece no predicado de um índice parcial impede a atualização HOT daquela coluna: o `UPDATE` que muda `dispatched_at` (índice parcial `WHERE dispatched_at IS NULL`) ou `state` (`WHERE state = 'Captured'`) deixa de ser HOT e passa a manter o índice. Avaliar o custo de escrita (inchaço do índice, VACUUM) ao criar um índice parcial sobre coluna que muda com frequência. Fontes: https://www.postgresql.org/docs/18/storage-hot.html e https://www.postgresql.org/docs/18/indexes-partial.html
