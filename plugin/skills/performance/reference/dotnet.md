# Performance — .NET (backend do SquadOS)

Versões: .NET 10 (SDK do `global.json`), EF Core 10 + Npgsql, xUnit v2. Ferramentas de diagnóstico (`dotnet-counters`, `dotnet-trace`, `dotnet-gcdump`) ainda **não** estão instaladas: instalar como ferramenta global só quando houver uma investigação (camada 4), com aprovação.

## Camada 1 — regras estáticas

`Directory.Build.props` já liga `AnalysisLevel 10.0-recommended`, `EnforceCodeStyleInBuild` e `TreatWarningsAsErrors`. Regras de performance a conferir no `.editorconfig` (por regra, valem também as desligadas por padrão): CA1826, CA1827, CA1829, CA1851, CA1859 e CA1860 como `warning`; CA1848 (`LoggerMessage`) como `suggestion`, obrigatória só em caminho quente. Analisadores extras (`SonarAnalyzer.CSharp`, `Meziantou.Analyzer`) dependem de uma medição de avisos aprovada pelo projeto e registrada em `docs/decisions.md`; `.editorconfig`, `Directory.Build.props`, `GlobalSuppressions.cs` e `*.ruleset` ficam em `ask`.

## Camada 2 — contagem nos testes

- **Comandos de banco (EF Core)**: `tests/SquadOS.IntegrationTests/Support/CommandCounter.cs` é um `DbCommandInterceptor` que conta leitura, escrita e escalar; registrar no host de teste com `services.ConfigureDbContext<SquadOsDbContext>(o => o.AddInterceptors(counter))` (interceptador não vem do DI). O teste mede a operação com poucos e com muitos itens e afirma que a contagem **não cresce**; exemplo: `tests/SquadOS.IntegrationTests/Performance/` (`GET /v1/demands/{id}` com 2 e 150 artefatos).
- **Chamadas HTTP**: `DelegatingHandler` de teste que conta as requisições do `HttpClient` da integração; retry não multiplica chamadas além do configurado.
- **Alocação** só em código síncrono e puro, com `GC.GetAllocatedBytesForCurrentThread()` (por exemplo `Quantiles` e o builder do resumo de métricas).

## Camada 3 — BenchmarkDotNet

Ainda não há projeto de benchmark nem caminho `hot` declarado. Quando o primeiro for criado (tarefa própria, com aprovação do pacote `BenchmarkDotNet` e do projeto `tests/SquadOS.Benchmarks`):

```csharp
[BenchmarkCategory("MetricsSummary")]
public class MetricsSummaryBuilderBenchmarks
{
    [Params(1_000, 100_000)]
    public int Size;

    [GlobalSetup]
    public void Setup() => /* monta Size DemandFlow sintéticos */;

    [Benchmark]
    public MetricsSummaryResponse Build() => MetricsSummaryBuilder.Build(/* ... */);
}
```

Linhas do `.claude/risk.conf` (descomentar quando o benchmark existir):

```ini
hot     = src/SquadOS.App/Features/Metrics/Summary/* -> MetricsSummary
bench   = MetricsSummary -> dotnet run -c Release --project tests/SquadOS.Benchmarks -- --filter '*' --anyCategories "$BENCH_CATEGORY" --job short --memory --threading --exceptions --exporters json --artifacts "$BENCH_RAW" && dotnet run "$BENCH_SCRIPTS/bdn-to-tsv.cs" -- "$BENCH_RAW" > "$BENCH_TSV"
profile = MetricsSummary -> dotnet run -c Release --project tests/SquadOS.Benchmarks -- --filter '*' --anyCategories "$BENCH_CATEGORY" --job short --profiler EP --artifacts "$BENCH_RAW" && dotnet run "$BENCH_SCRIPTS/hot-methods.cs" -- "$BENCH_RAW" 15 > "$BENCH_PROFILE_OUT"
```

Adaptadores prontos na pasta de scripts do plugin, que o `bench-compare.sh` exporta em `$BENCH_SCRIPTS` para os comandos `bench` e `profile` (`bdn-to-tsv.cs`, `hot-methods.cs`; apps de arquivo único do .NET 10, rodam sob o `global.json` do repositório). Conferir, no primeiro uso real, as opções `--memory`, `--threading`, `--exceptions`, `--profiler EP` e os campos do JSON (`Benchmarks`, `FullName`, `Parameters`, `Statistics.Mean`, `Memory.BytesAllocatedPerOperation`, `Memory.Gen2Collections`, `Memory.TotalOperations`, `Metrics[].Descriptor.Id`) contra `--help` e um relatório real.

## Camada 3b — suíte instrumentada

`tests/SquadOS.IntegrationTests/Support/PerfSnapshot.cs`, inerte sem a variável:

```bash
PERF_SNAPSHOT_OUT=/c/Users/wesll/AppData/Local/Temp/claude-squados-perf dotnet test tests/SquadOS.IntegrationTests --no-build
```

Gera `<pasta>/SquadOS.IntegrationTests.json` (fila e threads do thread pool, GC por geração, alocação, contenção de lock, CPU, top 20 exceções). A suíte completa leva ~6 min e exige o Docker no ar (gotcha do WSL: manter `wsl -d Ubuntu -- sleep <s>`).

## Camada 4 — profiling

`dotnet-counters monitor` (CPU, GC, heap, thread pool, exceções) → `dotnet-trace collect` (CPU) ou `dotnet-gcdump` (memória) → `dotnet-trace convert --format speedscope` → `hot-methods.cs`. Para consultas, o plano vem da skill `query-plan` (MCP Toolbox só funciona com o AppHost no ar; senão, PostgreSQL descartável em contêiner). Aspire: dashboard (traces e métricas do `ServiceDefaults`) é o ponto de partida local.
