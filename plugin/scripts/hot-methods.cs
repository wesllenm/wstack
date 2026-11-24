// Resume traces de CPU no formato speedscope (gerados pelo EventPipeProfiler do BenchmarkDotNet ou por
// "dotnet-trace convert --format speedscope") nos métodos que mais consomem tempo. App de arquivo único do .NET 10:
//   dotnet run .claude/scripts/hot-methods.cs -- <pasta-ou-arquivo> [top]
// Exclusivo: tempo com o método no topo da pilha (onde o trabalho acontece).
// Inclusivo: tempo com o método em qualquer ponto da pilha (o que ele custa contando o que chama).
using System.Text.Json;

if (args.Length is < 1 or > 2)
{
    Console.Error.WriteLine("uso: dotnet run hot-methods.cs -- <pasta-ou-arquivo .speedscope.json> [top]");
    return 2;
}
var top = args.Length == 2 ? int.Parse(args[1]) : 15;
var files = File.Exists(args[0])
    ? new[] { args[0] }
    : Directory.Exists(args[0])
        ? Directory.EnumerateFiles(args[0], "*.speedscope.json", SearchOption.AllDirectories).OrderBy(f => f).ToArray()
        : Array.Empty<string>();
if (files.Length == 0)
{
    Console.Error.WriteLine($"nenhum .speedscope.json em {args[0]}");
    return 3;
}

foreach (var file in files)
{
    using var doc = JsonDocument.Parse(File.ReadAllText(file));
    var names = doc.RootElement.GetProperty("shared").GetProperty("frames").EnumerateArray()
        .Select(f => f.TryGetProperty("name", out var n) ? n.GetString() ?? "?" : "?").ToArray();
    var exclusive = new double[names.Length];
    var inclusive = new double[names.Length];
    double total = 0;

    foreach (var profile in doc.RootElement.GetProperty("profiles").EnumerateArray())
    {
        var type = profile.GetProperty("type").GetString();
        if (type == "sampled")
        {
            var weights = profile.GetProperty("weights").EnumerateArray().Select(w => w.GetDouble()).ToArray();
            var i = 0;
            foreach (var sample in profile.GetProperty("samples").EnumerateArray())
            {
                var stack = sample.EnumerateArray().Select(f => f.GetInt32()).ToArray();
                var w = i < weights.Length ? weights[i] : 1;
                i++;
                if (stack.Length == 0) continue;
                total += w;
                exclusive[stack[^1]] += w;
                foreach (var f in stack.Distinct()) inclusive[f] += w;
            }
        }
        else if (type == "evented")
        {
            var stack = new List<int>();
            double? last = null;
            foreach (var ev in profile.GetProperty("events").EnumerateArray())
            {
                var at = ev.GetProperty("at").GetDouble();
                if (last is double l && stack.Count > 0)
                {
                    var dt = at - l;
                    total += dt;
                    exclusive[stack[^1]] += dt;
                    foreach (var f in stack.Distinct()) inclusive[f] += dt;
                }
                last = at;
                var frame = ev.GetProperty("frame").GetInt32();
                if (ev.GetProperty("type").GetString() == "O") stack.Add(frame);
                else
                {
                    var idx = stack.LastIndexOf(frame);
                    if (idx >= 0) stack.RemoveRange(idx, stack.Count - idx);
                }
            }
        }
    }

    Console.WriteLine($"== {Path.GetFileName(file)}");
    if (total <= 0) { Console.WriteLine("   sem amostras"); continue; }
    Print("exclusivo", exclusive);
    Print("inclusivo", inclusive);

    void Print(string title, double[] values)
    {
        Console.WriteLine($"-- top {top} {title}");
        foreach (var (v, idx) in values.Select((v, idx) => (v, idx)).Where(x => x.v > 0)
                     .OrderByDescending(x => x.v).Take(top))
            Console.WriteLine($"   {v / total,6:P1}  {names[idx]}");
    }
}
return 0;
