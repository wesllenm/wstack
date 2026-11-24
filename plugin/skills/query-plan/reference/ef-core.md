# EF Core — referência de avaliação de queries

Versões cobertas: EF Core 10 com `Npgsql.EntityFrameworkCore.PostgreSQL` 10 (.NET 10 LTS).
Documentação conferida em learn.microsoft.com em 2026-10-23. Revisar ao mudar a versão principal.

## Regras

- Leitura sem alteração usa `AsNoTracking` (ou projeção): tracking custa snapshot e identity resolution. [https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying]
- Projetar só as colunas necessárias com `Select`; entidade inteira traz colunas grandes (conteúdo de artefato, prompts) e impede index-only scan. [https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying]
- Limitar o resultado (`Take`) e paginar por keyset com ordenação única (ex.: data + id), com índice composto na mesma ordem. [https://learn.microsoft.com/en-us/ef/core/querying/pagination]
- `Include` de duas ou mais coleções no mesmo nível gera explosão cartesiana: usar `AsSplitQuery` (atenção à consistência entre as queries) ou projeção. O EF emite aviso `MultipleCollectionIncludeWarning`; configurar para lançar em teste. [https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries]
- Lazy loading é proibido por padrão (N+1); carregar relacionados por eager loading ou projeção. [https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying]
- Atualização ou remoção em massa usa `ExecuteUpdateAsync`/`ExecuteDeleteAsync` em vez de carregar e salvar em laço; não abrem transação implícita, não atualizam o change tracker e não aplicam concorrência otimista sozinhas (conferir o número de linhas afetadas). [https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete]
- Queries compiladas (`EF.CompileAsyncQuery`) e `AddDbContextPool` só em caminho quente medido. [https://learn.microsoft.com/en-us/ef/core/performance/advanced-performance-topics]
- Valores variáveis entram como variável capturada (parametrizado), nunca como constante em expression tree montada dinamicamente: constantes poluem o cache do EF e geram SQL diferente por valor. [https://learn.microsoft.com/en-us/ef/core/performance/advanced-performance-topics]
- Avaliação no cliente fora da projeção final lança exceção; `AsEnumerable()` para forçar avaliação no cliente é erro, não fallback, salvo volume pequeno justificado. [https://learn.microsoft.com/en-us/ef/core/querying/client-eval]
- Captura do SQL: `LogTo` filtrado para `DbLoggerCategory.Database.Command`; `EnableSensitiveDataLogging` só em teste. [https://learn.microsoft.com/en-us/ef/core/logging-events-diagnostics/simple-logging]

## Lacunas (follow-up)

- Mapeamento de tipos do Npgsql (ex.: `DateTime` para `timestamptz`, enums, `vector`): documentação em www.npgsql.org, fora dos domínios liberados. Decidir se o domínio entra em `WebFetch`.

## Como obter evidência

- SQL real: log dos testes de integração (Testcontainers com Postgres 18) gravado na pasta temporária da sessão.
- Contagem de comandos por operação: interceptor `DbCommandInterceptor` em teste de integração, quando o ajuste corrigir N+1.
