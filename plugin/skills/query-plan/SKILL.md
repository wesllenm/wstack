---
name: query-plan
description: >
  Carregar sempre que o diff criar ou alterar acesso a banco (LINQ do EF Core,
  SQL bruto via FromSql/SqlQuery, comandos de escrita, ExecuteUpdate/ExecuteDelete,
  busca vetorial pgvector). Identifica o motor e a versão do banco, captura o
  comando realmente enviado, obtém o plano de execução no banco real via MCP
  Toolbox e avalia o comando contra as boas práticas e a documentação oficial
  daquele motor e versão.
---

# Query Plan

## Objetivo

Nenhum comando de banco novo ou alterado entra no commit sem o plano de execução conferido no banco real, com volume representativo, com os mesmos tipos de parâmetro que a aplicação envia e avaliado pelas regras do motor e da versão em uso. [DAT-05]

## Quando aplicar

- Query nova ou alterada em LINQ (EF Core), SQL bruto (`FromSql`, `SqlQuery`), view ou função.
- Comando de escrita novo ou alterado (`UPDATE`, `DELETE`, `INSERT ... SELECT`, `ExecuteUpdate`, `ExecuteDelete`).
- Busca por similaridade em pgvector (`<->`, `<=>`, `<#>`) nova ou alterada.
- Mudança de índice, de tipo de coluna ou de mapeamento que possa alterar planos existentes.
- Nova listagem paginada por cursor (skill `api-design`): o índice precisa casar com a ordenação.

Não se aplica a SQL de migration (DDL); isso é da skill `db-evolution` e do `database-reviewer`. Também não se aplica ao state store do Dapr Workflow (tabelas gerenciadas pelo Dapr).

## Princípios

- Avaliar o comando que chega ao banco, nunca o código-fonte que o gera.
- Boa prática depende do motor e da versão: avaliar sempre pela versão detectada.
- A boa prática orienta onde olhar; o plano decide. Regra que o plano não confirma com volume representativo é observação, não achado.
- Plano em banco sem volume não prova nada.
- Evidência antes de recomendação: todo ajuste proposto vem com o plano antes e o plano depois.
- Índice é decisão de schema: recomendar, nunca criar sozinho. [DAT-06]

## Divisão de trabalho

- `database-helper` (Haiku): passos 0 a 5 e veredito preliminar. Devolve métricas, não planos brutos.
- `database-reviewer` (Opus): passo 6 nos comandos sinalizados e veredito final. Consulta a documentação oficial quando a referência não cobrir o caso.
- `lead`: decide o que vira ajuste no escopo, o que vira recomendação e o que interrompe.

## Arquivos de referência

- `reference/postgresql.md` — PostgreSQL 18.
- `reference/ef-core.md` — EF Core 10 com Npgsql.

Cada regra tem a versão a partir da qual vale e o link da documentação oficial. Lacunas conhecidas (pgvector e Npgsql, cujas documentações estão fora dos domínios liberados) ficam registradas no próprio arquivo como follow-up.

## Processo

### 0. Identificar motor, versão e configuração relevante

No código:

- pacotes (`Npgsql.EntityFrameworkCore.PostgreSQL`, `Pgvector.EntityFrameworkCore`) e versões em `Directory.Packages.props`;
- imagem do Postgres no AppHost do Aspire (tag da imagem);
- configuração de exemplo (`appsettings.json` sem segredos); nunca ler `.env`.

No banco real (via `database-helper`):

- `SELECT version()`;
- `SHOW plan_cache_mode; SHOW random_page_cost; SHOW work_mem; SHOW default_statistics_target;`
- `SELECT extversion FROM pg_extension WHERE extname = 'vector';`

Comparar com o que está registrado em `.claude/architecture.md`. Se divergir, reportar: regras da referência podem não valer mais.

A versão de produção prevalece sobre a de desenvolvimento. Se forem diferentes, avaliar pelas regras da versão de produção e registrar a divergência como risco.

### 1. Inventariar os comandos

Listar cada comando de banco tocado pelo diff: arquivo, método e se é leitura ou escrita.

### 2. Capturar o SQL real

- **EF Core**: rodar os testes de integração que exercitam o código com log de comandos ligado (`LogTo` filtrado para `DbLoggerCategory.Database.Command`, com `EnableSensitiveDataLogging` só em teste), gravando na pasta temporária da sessão. Alternativa pontual: `ToQueryString()` num teste. Verificar também quantos comandos cada operação gera; N+1 aparece aqui, não no plano. [PRF-04]
- **SQL bruto**: usar o SQL do código e registrar o tipo .NET de cada parâmetro e o tipo Npgsql resultante (`NpgsqlDbType`).

### 3. Escolher valores de parâmetro representativos

Para cada parâmetro de filtro, testar pelo menos:

- um valor comum (muitas linhas);
- um valor raro (poucas linhas);
- o caso vazio ou nulo, quando existir.

Se os planos divergirem entre esses valores, há risco de plano genérico ruim (`plan_cache_mode = auto` passa a plano genérico após cinco execuções preparadas): registrar.

### 4. Conferir o volume

Antes de interpretar, consultar `pg_class.reltuples` e `pg_stat_user_tables` das tabelas envolvidas. Se o volume do ambiente não for representativo do esperado em produção (meta em `.claude/project.md`), o veredito máximo é **não conclusivo**.

### 5. Obter o plano (via `database-helper`, MCP Toolbox, somente leitura)

| Tipo | Comando |
|---|---|
| Leitura | `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` com `SET statement_timeout` antes; `EXPLAIN (GENERIC_PLAN)` (16+) para ver o plano genérico do comando parametrizado (não combina com `ANALYZE`) |
| Escrita | `EXPLAIN (FORMAT JSON)` sem `ANALYZE` |

Nunca executar o comando de escrita para obter plano real. Usar os mesmos tipos da aplicação: literal com cast explícito para o tipo do parâmetro (`'...'::uuid`, `'...'::timestamptz`, `'[...]'::vector`).

**Sem MCP (nuvem).** O `.mcp.json` aponta para `localhost:15432`, um Postgres que só existe com o AppHost no ar, então na nuvem o MCP falha com `CONNECTION_CLOSED`. Sem MCP, subir um Postgres descartável (Testcontainers num teste temporário fora do repositório, ou a imagem do AppHost) com as migrations aplicadas, gerar volume sintético coerente com a meta de `.claude/project.md` e rodar por `psql` o `EXPLAIN (ANALYZE, BUFFERS)` em plano personalizado e em plano genérico (`PREPARE` com `SET plan_cache_mode = force_generic_plan`). O veredito vale como plano real, e o relatório diz que veio do banco descartável; contêiner e arquivos temporários saem no fim.

Planos brutos (JSON) vão para a pasta temporária da sessão. O retorno ao `lead` traz só as métricas: operadores principais, linhas estimadas e reais, linhas removidas por filtro, buffers (shared hit/read), duração e avisos (sort em disco, `Rows Removed by Filter` alto).

### 6. Avaliar contra o motor

1. Ler `reference/postgresql.md` e, quando a query vier do EF Core, `reference/ef-core.md`.
2. Aplicar os sinais de alerta gerais:
   - Seq Scan em tabela com volume relevante;
   - linhas lidas muito maiores que linhas retornadas;
   - estimativa e real divergindo em uma ordem de grandeza ou mais;
   - cast no lado da coluna (tipo do parâmetro diferente do tipo da coluna);
   - predicado não sargável: função ou cálculo sobre a coluna, `LIKE '%x'`, `OR` entre colunas diferentes;
   - heap fetch repetido em muitas linhas (candidato a índice com `INCLUDE`);
   - sort ou hash com spill para disco (`Sort Method: external merge`);
   - escrita (`UPDATE`/`DELETE`) sem índice no `WHERE`, com risco de lock amplo;
   - paginação por cursor sem índice composto na ordem da ordenação;
   - explosão cartesiana em `Include` múltiplo do EF Core;
   - `SELECT` de colunas desnecessárias (entidade inteira) impedindo index-only scan;
   - busca vetorial sem índice HNSW/IVFFlat ou com filtro que impede o uso do índice.
3. Aplicar as regras específicas do motor e da versão detectados.
4. Quando o caso não estiver na referência, consultar a documentação oficial da versão detectada, somente nos domínios liberados no `settings.json`:
   - PostgreSQL: `www.postgresql.org/docs/<versão>/`;
   - EF Core: `learn.microsoft.com`.
   Fonte fora desses domínios não fundamenta recomendação. Na nuvem o proxy pode bloquear `www.postgresql.org` (403): o revisor usa a referência local e marca o link como não reconferido.

Toda recomendação traz:

- a evidência do plano (operador, linhas, custo, antes e depois);
- a regra aplicada e o link da documentação oficial da versão;
- o motivo de valer para esta versão e configuração.

Recomendação sem link oficial e sem evidência de plano não entra no relatório.

### 7. Ajustar e medir de novo

- Ajuste que não muda schema (reescrever a query, projeção, tipo de parâmetro, `AsSplitQuery`, `AsNoTracking`): aplicar dentro do escopo e repetir os passos 2 a 6.
- Ajuste que muda schema (índice, coluna gerada, estatística estendida): recomendar com o plano atual e a hipótese, e encaminhar para `db-evolution` e `database-reviewer`. Não criar índice fora do plano aprovado.
- Regra útil que apareceu na documentação e não estava na referência: propor a inclusão em `reference/<motor>.md` como aprendizado (seção Aprendizado da skill `lead`), com versão e link.

## Veredito por comando

- **ok**: plano adequado ao volume e aos valores testados, sem violação relevante das regras do motor.
- **ajustado**: problema corrigido dentro do escopo, com plano antes e depois.
- **recomendação**: exige mudança de schema ou decisão; vai para o relatório.
- **não conclusivo**: volume não representativo, versão de produção desconhecida, MCP Toolbox indisponível ou plano indisponível; motivo registrado.
- **bloqueia**: escrita sem índice em tabela grande, scan em caminho crítico de alta frequência ou cast no lado da coluna em tabela grande, sem correção possível no escopo.

Qualquer **bloqueia** ou **recomendação** de índice aciona o `database-reviewer`.

## Greenfield

Aplicar desde a primeira query. Motor, versão alvo de produção e meta de volume ficam em `.claude/project.md` e `.claude/architecture.md`. Popular o banco local com dados sintéticos em volume (seed do AppHost), nunca com cópia de produção. [DAT-07]

## Brownfield

Avaliar apenas os comandos tocados pelo diff. Problemas encontrados em queries não tocadas vão para `docs/gotchas.md` como follow-up, não para correção oportunista.

## Restrições e cuidados

- Somente leitura: nada de DML real, DDL, `ANALYZE` de tabela, `VACUUM` ou `SET enable_*` para "fazer passar".
- Resultados podem conter dados pessoais: resumir, contar ou mascarar; nada do banco vai para memória, `docs/`, referências ou commit.
- Hints e ajustes de planner (`SET enable_seqscan = off`, `plan_cache_mode` por sessão) só para diagnóstico, nunca como solução sem justificativa medida e registrada no plano. [DAT-11]
- Documentação de versão diferente da detectada não fundamenta recomendação.

## Testes obrigatórios

Esta skill não substitui testes de comportamento. Quando um ajuste corrigir problema real (N+1, cast implícito), adicionar teste de integração que proteja o comportamento observável relevante, por exemplo o número de comandos gerados por operação, passando pelo gate da `test-audit`.

## Exceções e limites

- Lookup por chave primária ou índice único em tabela pequena e estável pode ser marcado **ok** sem plano, com a justificativa. [DAT-05]
- Sem MCP Toolbox conectado ou sem permissão de plano: usar o banco descartável do passo 5; sem ele, veredito **não conclusivo** e limitação no relatório.

## Checklist de saída

- [ ] motor, versão e configuração conferidos com `.claude/architecture.md`;
- [ ] todos os comandos tocados pelo diff inventariados;
- [ ] SQL real capturado pelo log do EF Core;
- [ ] volume das tabelas conferido;
- [ ] plano obtido com valores comuns e raros;
- [ ] sinais gerais e regras do motor e da versão avaliados;
- [ ] toda recomendação com evidência de plano e link oficial;
- [ ] ajustes medidos antes e depois;
- [ ] índices recomendados, não criados;
- [ ] planos brutos fora do repositório;
- [ ] veredito por comando no relatório.
