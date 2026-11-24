---
name: query-plan
description: >
  Carregar sempre que o diff criar ou alterar acesso a banco (LINQ do EF Core,
  SQL do Dapper, queries brutas, comandos de escrita, pipelines do MongoDB).
  Identifica o motor e a versão do banco, captura o comando realmente enviado,
  obtém o plano de execução no banco real via MCP Toolbox e avalia o comando
  contra as boas práticas e a documentação oficial daquele motor e versão.
---

# Query Plan

## Objetivo

Nenhum comando de banco novo ou alterado entra no commit sem o plano de execução conferido no banco real, com volume representativo, com os mesmos tipos de parâmetro que a aplicação envia e avaliado pelas regras do motor e da versão em uso.

## Quando aplicar

- Query nova ou alterada em LINQ (EF Core), Dapper, SQL bruto, procedure, view ou pipeline de agregação, ou no ORM e driver de outra stack (Prisma, knex, `pg`, sqlx, Diesel).
- Comando de escrita novo ou alterado (`UPDATE`, `DELETE`, `MERGE`, `INSERT ... SELECT`).
- Mudança de índice, de tipo de coluna ou de mapeamento que possa alterar planos existentes.
- Nova listagem paginada por cursor (skill `api-design`): o índice precisa casar com a ordenação.

Não se aplica a SQL de migration (DDL); isso é da skill `db-evolution` e do `database-reviewer`. Também não se aplica a tabelas gerenciadas por uma dependência de terceiros (por exemplo, o estado interno de um motor de workflow).

## Princípios

- Avaliar o comando que chega ao banco, nunca o código-fonte que o gera.
- Boa prática depende do motor e da versão: avaliar sempre pela versão detectada.
- A boa prática orienta onde olhar; o plano decide. Regra que o plano não confirma com volume representativo é observação, não achado.
- Plano em banco sem volume não prova nada.
- Evidência antes de recomendação: todo ajuste proposto vem com o plano antes e o plano depois.
- Índice é decisão de schema: recomendar, nunca criar sozinho.

## Divisão de trabalho

- `database-helper` (Haiku): passos 0 a 5 e veredito preliminar. Devolve métricas, não planos brutos.
- `database-reviewer` (Opus): passo 6 nos comandos sinalizados e veredito final. Consulta a documentação oficial quando a referência não cobrir o caso.
- `lead`: decide o que vira ajuste no escopo, o que vira recomendação e o que interrompe.

## Arquivos de referência

`reference/<motor>.md` (por exemplo `sqlserver.md`, `postgresql.md`, `mongodb.md`) e `reference/ef-core.md`, gerados pelo bootstrap só para os motores e ORMs em uso. Cada regra tem a versão a partir da qual vale e o link da documentação oficial daquela versão. Se o motor em uso não tiver referência, avaliar só pelos sinais gerais e pela documentação oficial, e registrar a lacuna como follow-up.

## Processo

### 0. Identificar motor, versão e configuração relevante

No código:

- pacotes e drivers (`Microsoft.Data.SqlClient`, `Npgsql`, `MongoDB.Driver`, provider do EF Core e versão);
- `docker-compose.yml` e tags de imagem;
- configuração de exemplo (`appsettings.*.json` sem segredos); nunca ler `.env`.

No banco real (via `database-helper`):

- SQL Server: `SELECT @@VERSION`, `compatibility_level` do banco em `sys.databases`, se Query Store e RCSI estão ligados, e se é Azure SQL ou on-premises;
- PostgreSQL: `SELECT version()` e os parâmetros que afetam plano (`plan_cache_mode`, `random_page_cost`, `work_mem`, `default_statistics_target`);
- MongoDB: `buildInfo` e topologia (replica set, sharded).

Comparar com o que está registrado em `.claude/architecture.md`. Se divergir, reportar: regras da referência podem não valer mais.

A versão de produção prevalece sobre a de desenvolvimento. Se forem diferentes, avaliar pelas regras da versão de produção e registrar a divergência como risco.

### 1. Inventariar os comandos

Listar cada comando de banco tocado pelo diff: arquivo, método e se é leitura ou escrita.

### 2. Capturar o SQL real

- **EF Core**: rodar os testes de integração que exercitam o código com log de comandos ligado (`LogTo` ou logging do provider, com valores de parâmetro habilitados só em ambiente de teste), gravando na pasta temporária da sessão. Alternativa pontual: `ToQueryString()` num teste. Verificar também quantos comandos cada operação gera; N+1 aparece aqui, não no plano.
- **Dapper / SQL bruto**: usar o SQL do código e registrar o tipo .NET de cada parâmetro e como ele é mapeado (`DbString`, `DbType`, `IsAnsi`).
- **MongoDB**: capturar o filtro, a projeção, a ordenação ou o pipeline efetivamente enviado.
- **Outras stacks**: ligar o log de query do ORM ou driver nos testes de integração (evento `query` do Prisma e do knex, `log_statements` do sqlx, `debug_query` do Diesel) e capturar o SQL com os tipos de parâmetro.

### 3. Escolher valores de parâmetro representativos

Para cada parâmetro de filtro, testar pelo menos:

- um valor comum (muitas linhas);
- um valor raro (poucas linhas);
- o caso vazio ou nulo, quando existir.

Se os planos divergirem entre esses valores, há risco de parameter sniffing ou de plano genérico ruim: registrar.

### 4. Conferir o volume

Antes de interpretar, consultar a contagem ou as estatísticas das tabelas e coleções envolvidas. Se o volume do ambiente não for representativo do esperado em produção (informação de `.claude/project.md` ou do desenvolvedor), o veredito máximo é **não conclusivo**.

### 5. Obter o plano (via `database-helper`, MCP Toolbox, somente leitura)

| Motor | Leitura | Escrita |
|---|---|---|
| PostgreSQL | `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` com `statement_timeout`; no 16+, `EXPLAIN (GENERIC_PLAN)` para ver o plano genérico de comando parametrizado | `EXPLAIN (FORMAT JSON)` sem `ANALYZE` |
| SQL Server | depois dos testes de integração: Query Store, ou `sys.dm_exec_query_stats` + `sys.dm_exec_query_plan`, ou o último plano real em `sys.dm_exec_query_plan_stats` (2019+ com `LAST_QUERY_PLAN_STATS`); plano estimado com `SET SHOWPLAN_XML ON` quando o caminho do Toolbox permitir | somente plano estimado ou o plano em cache gerado pelos testes |
| MongoDB | `explain("executionStats")` | `explain` no modo `queryPlanner` |

Nunca executar o comando de escrita para obter plano real. Usar os mesmos tipos da aplicação: no PostgreSQL, literal com cast explícito para o tipo do parâmetro; no SQL Server, preferir o plano em cache gerado pela própria aplicação nos testes, que já tem os tipos reais.

**Sem MCP (nuvem).** Sem MCP Toolbox conectado (na nuvem, o banco do projeto costuma só existir com a aplicação no ar, e o MCP falha com `CONNECTION_CLOSED`), subir um banco descartável do mesmo motor e versão (contêiner, por exemplo Testcontainers num teste temporário fora do repositório, ou a imagem do projeto) com as migrations aplicadas, gerar volume sintético coerente com a meta de `.claude/project.md` e obter o plano pelo cliente de linha de comando do motor (no PostgreSQL, `EXPLAIN (ANALYZE, BUFFERS)` em plano personalizado e em plano genérico). O veredito vale como plano real, e o relatório diz que veio do banco descartável; contêiner e arquivos temporários saem no fim.

Planos brutos (XML, JSON) vão para a pasta temporária da sessão. O retorno ao `lead` traz só as métricas: operadores principais, linhas estimadas e reais, linhas lidas e retornadas, leituras lógicas ou buffers, duração e avisos do plano.

### 6. Avaliar contra o motor

1. Ler `reference/<motor>.md` e, quando a query vier do EF Core, `reference/ef-core.md`.
2. Aplicar os sinais de alerta gerais:
   - scan completo (Seq Scan, Clustered Index Scan, Table Scan, `COLLSCAN`) em tabela ou coleção com volume relevante;
   - linhas lidas muito maiores que linhas retornadas;
   - estimativa e real divergindo em uma ordem de grandeza ou mais;
   - conversão implícita (`CONVERT_IMPLICIT`, cast no lado da coluna), em especial `nvarchar` contra `varchar`;
   - predicado não sargável: função ou cálculo sobre a coluna, `LIKE '%x'`, `OR` entre colunas diferentes;
   - Key Lookup ou heap fetch repetido em muitas linhas (candidato a índice de cobertura);
   - sort ou hash com spill para disco, memory grant excessivo;
   - escrita (`UPDATE`/`DELETE`) sem índice no `WHERE`, com risco de lock amplo ou escalonamento;
   - paginação por cursor sem índice composto na ordem da ordenação;
   - explosão cartesiana em `Include` múltiplo do EF Core;
   - `SELECT *` ou colunas desnecessárias impedindo índice de cobertura.
3. Aplicar as regras específicas do motor e da versão detectados.
4. Quando o caso não estiver na referência, consultar a documentação oficial da versão detectada, somente nos domínios liberados no `settings.json`:
   - SQL Server, Azure SQL e EF Core: `learn.microsoft.com`;
   - PostgreSQL: `www.postgresql.org/docs/<versão>/`;
   - MongoDB: `www.mongodb.com/docs/`.
   Fonte fora desses domínios não fundamenta recomendação. Na nuvem o proxy pode bloquear algum desses domínios (403): o revisor usa a referência local e marca o link como não reconferido.

Toda recomendação traz:

- a evidência do plano (operador, linhas, custo, antes e depois);
- a regra aplicada e o link da documentação oficial da versão;
- o motivo de valer para esta versão e configuração.

Recomendação sem link oficial e sem evidência de plano não entra no relatório.

### 7. Ajustar e medir de novo

- Ajuste que não muda schema (reescrever a query, projeção, tipo de parâmetro, `AsSplitQuery`, `AsNoTracking`): aplicar dentro do escopo e repetir os passos 2 a 6.
- Ajuste que muda schema (índice, coluna computada, estatística): recomendar com o plano atual e a hipótese, e encaminhar para `db-evolution` e `database-reviewer`. Não criar índice fora do plano aprovado.
- Regra útil que apareceu na documentação e não estava na referência: propor a inclusão em `reference/<motor>.md` como aprendizado (seção Aprendizado da skill `lead`), com versão e link.

## Veredito por comando

- **ok**: plano adequado ao volume e aos valores testados, sem violação relevante das regras do motor.
- **ajustado**: problema corrigido dentro do escopo, com plano antes e depois.
- **recomendação**: exige mudança de schema ou decisão; vai para o relatório.
- **não conclusivo**: volume não representativo, versão de produção desconhecida, MCP Toolbox indisponível ou plano indisponível; motivo registrado.
- **bloqueia**: escrita sem índice em tabela grande, scan em caminho crítico de alta frequência ou conversão implícita em tabela grande, sem correção possível no escopo.

Qualquer **bloqueia** ou **recomendação** de índice aciona o `database-reviewer`.

## Greenfield

Aplicar desde a primeira query. Registrar motor, versão alvo de produção e meta de volume em `.claude/project.md` e `.claude/architecture.md`. Quando viável, popular o banco local com dados sintéticos em volume (seed do projeto), nunca com cópia de produção.

## Brownfield

Avaliar apenas os comandos tocados pelo diff. Problemas encontrados em queries não tocadas vão para `docs/gotchas.md` como follow-up, não para correção oportunista.

## Restrições e cuidados

- Somente leitura: nada de DML real, DDL, `UPDATE STATISTICS`, `ANALYZE` de tabela, `VACUUM`, `SET enable_*` ou hints de índice forçados para "fazer passar".
- Resultados podem conter dados pessoais: resumir, contar ou mascarar; nada do banco vai para memória, `docs/`, referências ou commit.
- Hint de query ou ajuste de planner (`OPTION (RECOMPILE)`, `FORCESEEK`, hints de índice, `SET enable_seqscan = off`, `plan_cache_mode` por sessão) só para diagnóstico, nunca como solução sem justificativa medida e registrada no plano.
- Documentação de versão diferente da detectada não fundamenta recomendação.

## Testes obrigatórios

Esta skill não substitui testes de comportamento. Quando um ajuste corrigir problema real (N+1, conversão implícita), adicionar teste de integração que proteja o comportamento observável relevante, por exemplo o número de comandos gerados por operação, passando pelo gate da `test-audit`.

## Exceções e limites

- Lookup por chave primária ou índice único em tabela pequena e estável pode ser marcado **ok** sem plano, com a justificativa.
- Banco não suportado pelo MCP Toolbox, MCP não conectado ou sem permissão de plano: usar o banco descartável do passo 5; sem ele, veredito **não conclusivo** e limitação no relatório.

## Checklist de saída

- [ ] motor, versão e configuração conferidos com `.claude/architecture.md`;
- [ ] todos os comandos tocados pelo diff inventariados;
- [ ] SQL real capturado (EF Core pelo log, Dapper com os tipos de parâmetro);
- [ ] volume das tabelas conferido;
- [ ] plano obtido com valores comuns e raros;
- [ ] sinais gerais e regras do motor e da versão avaliados;
- [ ] toda recomendação com evidência de plano e link oficial;
- [ ] ajustes medidos antes e depois;
- [ ] índices recomendados, não criados;
- [ ] planos brutos fora do repositório;
- [ ] veredito por comando no relatório.
