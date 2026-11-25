// Resume a telemetria do workflow: custo, tokens e requisições da telemetria nativa do Claude Code (otlp-sink.mjs),
// eventos de gate dos hooks e as linhas de Registro de docs/review-calibration.md. Sem dependências.
//   node <pasta do plugin>/scripts/summarize-runs.mjs [--since AAAA-MM-DD] [--json]
// Custo é a estimativa da própria plataforma, não a fatura. Campo sem fonte aparece como null.
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const since = (() => { const i = process.argv.indexOf("--since"); return i > 0 ? process.argv[i + 1] : null; })();
const asJson = process.argv.includes("--json");
const OTEL = ".claude/telemetry/otel", HOOKS = ".claude/telemetry/sessions", REG = "docs/review-calibration.md";

const jsonl = (d) => (existsSync(d) ? readdirSync(d).filter((f) => f.endsWith(".jsonl")).sort() : [])
  .flatMap((f) => readFileSync(join(d, f), "utf8").split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }))
  .filter(Boolean);
const inRange = (iso) => !since || (iso ?? "") >= since;

// Métricas: delta soma; cumulativa vale o maior valor visto por série (o último ponto).
const series = new Map();
for (const r of jsonl(OTEL).filter((r) => r.kind === "metric" && inRange(r.time))) {
  const key = r.name + JSON.stringify(Object.entries(r.attrs).sort());
  const s = series.get(key) ?? { name: r.name, attrs: r.attrs, value: 0 };
  s.value = r.temporality === "cumulative" ? Math.max(s.value, r.value) : s.value + r.value;
  series.set(key, s);
}
const sessions = new Map();
const S = (id) => {
  if (!sessions.has(id)) sessions.set(id, {
    session: id, first: null, cost_usd: null, tokens: { input: null, output: null, cacheRead: null, cacheCreation: null },
    models: new Set(), api_requests: null, verification_passed: 0, verification_failed: 0, learning_blocked: 0, verification_exception: 0,
    iteration_limit: 0, has_hook_events: false,
  });
  return sessions.get(id);
};
for (const s of series.values()) {
  const id = s.attrs["session.id"] ?? "(sem sessão)";
  const x = S(id);
  if (s.attrs.model) x.models.add(s.attrs.model);
  if (s.name === "claude_code.cost.usage") x.cost_usd = (x.cost_usd ?? 0) + s.value;
  if (s.name === "claude_code.token.usage" && s.attrs.type in x.tokens) x.tokens[s.attrs.type] = (x.tokens[s.attrs.type] ?? 0) + s.value;
}
for (const e of jsonl(OTEL).filter((r) => r.kind === "event" && inRange(r.time))) {
  const x = S(e.attrs["session.id"] ?? "(sem sessão)");
  if (/api_request$/.test(e.name)) x.api_requests = (x.api_requests ?? 0) + 1;
  if (!x.first || e.time < x.first) x.first = e.time;
}
for (const e of jsonl(HOOKS).filter((r) => inRange(r.timestamp))) {
  const x = S(e.session_id ?? "(sem sessão)");
  x.has_hook_events = true;
  if (e.event in x && typeof x[e.event] === "number") x[e.event]++;
  if (!x.first || e.timestamp < x.first) x.first = e.timestamp;
}

// Registro: uma linha por tarefa, no formato da skill lead.
const tasks = { total: 0, byLevel: {}, confirmed: 0, refuted: 0, rejected: 0, escaped: 0, principles: {} };
if (existsSync(REG)) {
  for (const line of readFileSync(REG, "utf8").split("\n")) {
    const m = line.match(/^-?\s*(\d{4}-\d{2}-\d{2}) — .+? — (TRIVIAL|SIMPLES|COMPLEXA|CRITICA|interrompida|investigação)(?![\p{L}\d_])(.*)$/u);
    if (!m || !inRange(m[1])) continue;
    tasks.total++;
    tasks.byLevel[m[2]] = (tasks.byLevel[m[2]] ?? 0) + 1;
    const n = (re) => Number((m[3].match(re) ?? [0, 0])[1]);
    tasks.confirmed += n(/(\d+) confirmados/); tasks.refuted += n(/(\d+) refutados/);
    tasks.rejected += n(/(\d+) recusados/); tasks.escaped += n(/(\d+) escaparam/);
    // "— princípios: tdd, query-plan (carregadas: 5)": quantas tarefas citaram cada skill
    const p = /— princípios: ([^—(]*)/u.exec(m[3]);
    for (const s of p ? p[1].split(',').map((x) => x.trim()).filter((x) => x && x !== 'nenhum') : []) {
      tasks.principles[s] = (tasks.principles[s] ?? 0) + 1;
    }
  }
}

const list = [...sessions.values()].map((x) => ({ ...x, models: [...x.models] }))
  .sort((a, b) => (a.first ?? "").localeCompare(b.first ?? ""));
const sum = (f) => { const v = list.map(f).filter((n) => n !== null); return v.length ? v.reduce((a, b) => a + b, 0) : null; };
const costs = list.map((x) => x.cost_usd).filter((n) => n !== null).sort((a, b) => a - b);
const summary = {
  since, sessions: list.length,
  cost_usd_estimated: { total: sum((x) => x.cost_usd), median_per_session: costs.length ? costs[Math.floor(costs.length / 2)] : null, n: costs.length },
  tokens: { input: sum((x) => x.tokens.input), output: sum((x) => x.tokens.output), cacheRead: sum((x) => x.tokens.cacheRead), cacheCreation: sum((x) => x.tokens.cacheCreation) },
  gates: { verification_failed: sum((x) => x.verification_failed), learning_blocked: sum((x) => x.learning_blocked), verification_exception: sum((x) => x.verification_exception), iteration_limit: sum((x) => x.iteration_limit) },
  tasks, list, warnings: [],
};

// Avisos de diagnóstico: o que só aparece olhando o agregado.
const hookOnly = list.filter((x) => x.has_hook_events && x.cost_usd === null && x.tokens.input === null);
const withHooks = list.filter((x) => x.has_hook_events).length;
if (hookOnly.length > 0) summary.warnings.push(
  `telemetria nativa ausente em ${hookOnly.length} de ${withHooks} sessões com eventos de gate: o receptor não subiu ou o bloco env do settings.json não está ativo`);
const t = summary.tokens;
const prompt = (t.input ?? 0) + (t.cacheRead ?? 0) + (t.cacheCreation ?? 0);
const nTok = list.filter((x) => x.tokens.input !== null).length;
if (t.cacheRead !== null && prompt > 0 && nTok >= 3) {
  summary.cache_hit = t.cacheRead / prompt;
  if (summary.cache_hit < 0.5) summary.warnings.push(
    `cache de prompt baixo: ${(summary.cache_hit * 100).toFixed(0)}% do prompt veio do cache (n=${nTok} sessões); algo no início do contexto muda entre turnos (imports do CLAUDE.md, arquivos lidos no começo)`);
} else summary.cache_hit = null;

if (asJson) { console.log(JSON.stringify(summary, null, 2)); process.exit(0); }
const fmt = (v, d = 0) => (v === null || v === undefined ? "n/d" : Number(v).toFixed(d));
console.log(`Sessões: ${summary.sessions}${since ? ` desde ${since}` : ""}`);
console.log(`Custo estimado pela plataforma: total US$ ${fmt(summary.cost_usd_estimated.total, 2)}, mediana por sessão US$ ${fmt(summary.cost_usd_estimated.median_per_session, 2)} (n=${costs.length})`);
console.log(`Tokens: entrada ${fmt(summary.tokens.input)}, saída ${fmt(summary.tokens.output)}, cache lido ${fmt(summary.tokens.cacheRead)}, cache criado ${fmt(summary.tokens.cacheCreation)}`);
console.log(`Gates: verificação falhou ${fmt(summary.gates.verification_failed)}x, aprendizado bloqueou ${fmt(summary.gates.learning_blocked)}x, exceção de verificação ${fmt(summary.gates.verification_exception)}x, limite de iteração ${fmt(summary.gates.iteration_limit)}x`);
console.log(`Cache de prompt: ${summary.cache_hit === null ? "n/d" : (summary.cache_hit * 100).toFixed(0) + "%"}`);
console.log(`Tarefas no Registro: ${tasks.total} ${JSON.stringify(tasks.byLevel)}; achados: ${tasks.confirmed} confirmados, ${tasks.refuted} refutados, ${tasks.rejected} recusados, ${tasks.escaped} escaparam`);
const cited = Object.entries(tasks.principles).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
console.log(`Princípios citados no Registro: ${cited.length ? cited.map(([s, n]) => `${s} ${n}`).join(', ') : 'nenhum'}`);
for (const w of summary.warnings) console.log(`AVISO: ${w}`);
console.log("\nÚltimas sessões:");
console.log("início                 sessão    custo US$  entrada   saída     req  falhas  bloq.aprend.");
for (const x of list.slice(-20)) {
  console.log(`${(x.first ?? "n/d").slice(0, 19).padEnd(22)} ${x.session.slice(0, 8).padEnd(9)} ${fmt(x.cost_usd, 2).padStart(9)}  ${fmt(x.tokens.input).padStart(8)}  ${fmt(x.tokens.output).padStart(8)}  ${fmt(x.api_requests).padStart(4)}  ${String(x.verification_failed).padStart(6)}  ${String(x.learning_blocked).padStart(6)}`);
}
