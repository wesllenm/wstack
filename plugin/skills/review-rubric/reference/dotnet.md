# Review — Sempre verificar, .NET (backend do SquadOS)

Aplicar às linhas do diff em `*.cs`, além do "Sempre verificar" genérico da `SKILL.md`.

Assíncrono e recursos:
- sync-over-async (`.Result`, `.Wait()`, `GetAwaiter().GetResult()`), `async void` fora de handler de evento, `Task` disparada sem observação;
- `CancellationToken` recebido e repassado em todo I/O; `catch (Exception)` que pega também `OperationCanceledException`;
- `IDisposable` sem `using`; `HttpClient` criado por requisição em vez de `IHttpClientFactory`; estado estático mutável.

Corretude:
- `DateTime.Now` em vez de `UtcNow` ou `TimeProvider` (o domínio é sem relógio e o `TimeProvider` é injetado); `decimal` para dinheiro; parsing e formatação com cultura explícita (`CultureInfo.InvariantCulture`);
- regex de identificador com `$` em vez de `\z` (casa antes de `\n` final); o mesmo no `pattern` de JSON Schema de artefato, onde o fim é `(?![\s\S])`.

EF Core e dados:
- leitura sem `AsNoTracking`; lazy loading em laço (N+1); `ToList()` antes de filtrar; `IQueryable` vazando para fora do repositório ou da consulta de leitura;
- enum comparado por variável capturada em vez de constante (`EF.Constant`) quando o índice parcial depende do literal;
- `Update()`/`Attach` de entidade desconectada contornando o token `Version`; escrita por `ExecuteUpdate`/`ExecuteDelete` contornando triggers, outbox e versão;
- tabela só-inserção (`artifacts`, `approvals`, `audit_events`) alterada por `UPDATE`/`DELETE`.

Observabilidade:
- log com interpolação de string em vez de template estruturado; dado pessoal, segredo ou conteúdo de prompt em log ou atributo de span sem a trava do Langfuse;
- erro de programação embrulhado como "falha de infraestrutura" ou "timeout" (filtros de `catch` largos).

Performance (categorias do diff): contagem de comandos e de chamadas nos testes; `bench-compare.sh` quando houver `quente:` (skill `performance`).

Camada determinística de referência (o `lead` e o `risk.conf` são donos; aqui só o que a revisão assume):
- build com `TreatWarningsAsErrors`, `AnalysisLevel` recomendado e `EnforceCodeStyleInBuild`; `dotnet format --verify-no-changes`; `SquadOS.ArchitectureTests`; `dotnet list SquadOS.slnx package --vulnerable --include-transitive`; gitleaks no CI. Stryker.NET está previsto para o CI (pendência em `ci/README.md`); sem ferramenta local, não há mutante para triar.
- `SonarAnalyzer.CSharp` (licença SSAL) e `Meziantou.Analyzer` só entram por decisão do projeto em `docs/decisions.md`, o segundo com perfil enxuto e depois de limpar o residual: não cobrar do revisor o que esses analisadores cobririam.
- Sinais de qualidade (`quality-signals.sh`): produtor `cobertura` com `coverlet.collector` sobre o filtro da suíte rápida (`Category!=Integration&Category!=E2E`), mais `jscpd` com `--format csharp`; async aparece com o nome do método. Linha no `risk.conf` é decisão do `lead`.
- Em `ask`: `.editorconfig`, `Directory.Build.props`, `GlobalSuppressions.cs`, `*.ruleset` e os projetos de teste de arquitetura.

Não é achado (o analisador, o formatador ou o contrato já cobrem): `var` vs tipo explícito, ordem de `using`, nomenclatura (IDE1006), `ConfigureAwait(false)` em código de aplicação ASP.NET, XML doc em membro não público, `record` vs `class` por gosto, `sealed` ausente sem uso medido.
