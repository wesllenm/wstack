// Converte relatórios JSON do BenchmarkDotNet para o TSV comum do comparador. App de arquivo único do .NET 10:
//   dotnet run "$BENCH_SCRIPTS/bdn-to-tsv.cs" -- <pasta de artefatos do BenchmarkDotNet>  > "$BENCH_TSV"
// Parâmetro "Size" vira a coluna size (teste de escala). Métricas de exceção e lock vêm dos diagnosers.
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

if (args.Length != 1 || !Directory.Exists(args[0]))
{
    Console.Error.WriteLine("uso: dotnet run bdn-to-tsv.cs -- <pasta de artefatos>");
    return 2;
}

var inv = CultureInfo.InvariantCulture;
var rows = 0;
foreach (var file in Directory.EnumerateFiles(args[0], "*-report*.json", SearchOption.AllDirectories))
{
    using var doc = JsonDocument.Parse(File.ReadAllText(file));
    if (!doc.RootElement.TryGetProperty("Benchmarks", out var benchmarks)) continue;

    foreach (var b in benchmarks.EnumerateArray())
    {
        if (!b.TryGetProperty("FullName", out var fn) || fn.GetString() is not string name) continue;
        if (!b.TryGetProperty("Statistics", out var st) || st.ValueKind != JsonValueKind.Object) continue;
        if (Number(st, "Mean") is not double mean) continue;

        string bytes = "-", gen2 = "-";
        if (b.TryGetProperty("Memory", out var mem) && mem.ValueKind == JsonValueKind.Object)
        {
            if (Number(mem, "BytesAllocatedPerOperation") is double bpo) bytes = bpo.ToString("0", inv);
            if (Number(mem, "Gen2Collections") is double g2 && Number(mem, "TotalOperations") is double ops && ops > 0)
                gen2 = (g2 / ops * 1000).ToString("0.###", inv);
        }

        double? exceptions = null, locks = null;
        if (b.TryGetProperty("Metrics", out var ms) && ms.ValueKind == JsonValueKind.Array)
        {
            foreach (var m in ms.EnumerateArray())
            {
                if (!m.TryGetProperty("Descriptor", out var d) || !d.TryGetProperty("Id", out var idEl)) continue;
                if (Number(m, "Value") is not double v) continue;
                var id = idEl.GetString() ?? "";
                if (id.Contains("Exception", StringComparison.OrdinalIgnoreCase)) exceptions = (exceptions ?? 0) + v;
                if (id.Contains("Lock", StringComparison.OrdinalIgnoreCase)) locks = (locks ?? 0) + v;
            }
        }

        var size = "-";
        if (b.TryGetProperty("Parameters", out var p) && p.GetString() is string ps)
        {
            var match = Regex.Match(ps, @"(?:^|&)Size=(\d+)");
            if (match.Success) size = match.Groups[1].Value;
        }

        var method = Regex.Replace(name, @"\(.*\)$", "");
        Console.WriteLine(string.Join('\t', "bench", name, method, size, mean.ToString("0.###", inv), bytes, gen2,
            exceptions?.ToString("0.####", inv) ?? "-", locks?.ToString("0.####", inv) ?? "-"));
        rows++;
    }
}

if (rows == 0) Console.Error.WriteLine($"nenhum benchmark encontrado em {args[0]}");
return rows == 0 ? 3 : 0;

static double? Number(JsonElement e, string prop) =>
    e.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
