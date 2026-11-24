// Receptor OTLP local e mínimo para a telemetria nativa do Claude Code. Sem dependências.
//   node <pasta do plugin>/scripts/otlp-sink.mjs [--port 4318] [--dir .claude/telemetry/otel] [--retention-days 30]
// Escuta só em 127.0.0.1, aceita OTLP/HTTP com JSON (OTEL_EXPORTER_OTLP_PROTOCOL=http/json), grava um JSONL por dia
// e guarda só os atributos da lista abaixo: e-mail, IDs de conta e organização, prompts, parâmetros de ferramenta e
// mensagens de erro (podem trazer stderr com segredo) nunca chegam ao disco, mesmo se a plataforma os enviar. Recusa
// requisição com Origin (navegador), Content-Type diferente de application/json e corpo acima de 4 MiB. Se a porta já
// estiver em uso, sai em silêncio: outra instância já está recebendo.
import { createServer } from "node:http";
import { appendFileSync, mkdirSync, readdirSync, statSync, unlinkSync } from "node:fs";
import { join } from "node:path";

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : fallback;
};
const port = Number(arg("port", 4318));
const dir = arg("dir", ".claude/telemetry/otel");
const retentionDays = Number(arg("retention-days", 30));

const MAX_BODY = 4 * 1024 * 1024;
const KEEP = new Set([
  "session.id", "model", "type", "decision", "source", "tool_name", "success",
  "duration_ms", "cost_usd", "input_tokens", "output_tokens", "cache_read_tokens", "cache_creation_tokens",
  "event.name", "event.timestamp", "query_source", "skill.name", "agent.name", "agent_type", "status_code",
  "service.version", "app.version",
]);

mkdirSync(dir, { recursive: true });
const cutoff = Date.now() - retentionDays * 86400_000;
for (const f of readdirSync(dir)) {
  const p = join(dir, f);
  if (f.endsWith(".jsonl") && statSync(p).mtimeMs < cutoff) unlinkSync(p);
}

const value = (v = {}) => {
  if ("stringValue" in v) return v.stringValue;
  if ("intValue" in v) return Number(v.intValue);
  if ("doubleValue" in v) return Number(v.doubleValue);
  if ("boolValue" in v) return v.boolValue;
  return undefined;
};
const attrs = (list = []) => {
  const out = {};
  for (const a of list) if (KEEP.has(a.key)) out[a.key] = value(a.value);
  return out;
};
const nanoToIso = (n) => (n ? new Date(Number(BigInt(n) / 1_000_000n)).toISOString() : null);

function metricRecords(body) {
  const out = [];
  for (const rm of body.resourceMetrics ?? []) {
    const res = attrs(rm.resource?.attributes);
    for (const sm of rm.scopeMetrics ?? []) {
      for (const m of sm.metrics ?? []) {
        const data = m.sum ?? m.gauge;
        if (!data) continue;
        // 1 = DELTA, 2 = CUMULATIVE (OTLP); gauge não tem temporalidade
        const temporality = m.sum ? (data.aggregationTemporality === 2 || data.aggregationTemporality === "AGGREGATION_TEMPORALITY_CUMULATIVE" ? "cumulative" : "delta") : "gauge";
        for (const dp of data.dataPoints ?? []) {
          out.push({
            kind: "metric", name: m.name, unit: m.unit ?? null, temporality,
            value: Number(dp.asDouble ?? dp.asInt ?? 0),
            start: nanoToIso(dp.startTimeUnixNano), time: nanoToIso(dp.timeUnixNano),
            attrs: { ...res, ...attrs(dp.attributes) },
          });
        }
      }
    }
  }
  return out;
}

function logRecords(body) {
  const out = [];
  for (const rl of body.resourceLogs ?? []) {
    const res = attrs(rl.resource?.attributes);
    for (const sl of rl.scopeLogs ?? []) {
      for (const lr of sl.logRecords ?? []) {
        const a = { ...res, ...attrs(lr.attributes) };
        const name = a["event.name"] ?? "event";
        out.push({ kind: "event", name, time: nanoToIso(lr.timeUnixNano ?? lr.observedTimeUnixNano), attrs: a });
      }
    }
  }
  return out;
}

const server = createServer((req, res) => {
  if (req.method !== "POST" || !["/v1/metrics", "/v1/logs", "/v1/traces"].includes(req.url)) {
    res.writeHead(404).end();
    return;
  }
  if ("origin" in req.headers) {
    res.writeHead(403).end();
    return;
  }
  if ((req.headers["content-type"] ?? "").split(";")[0].trim().toLowerCase() !== "application/json") {
    res.writeHead(415, { "content-type": "text/plain" }).end("use OTEL_EXPORTER_OTLP_PROTOCOL=http/json");
    return;
  }
  const chunks = [];
  let size = 0, tooBig = false;
  const reject = () => {
    if (tooBig) return;
    tooBig = true;
    chunks.length = 0;
    res.writeHead(413, { connection: "close" });
    res.end(() => req.destroy());
  };
  if (Number(req.headers["content-length"]) > MAX_BODY) reject();
  req.on("data", (c) => {
    if (tooBig) return;
    size += c.length;
    if (size > MAX_BODY) return reject();
    chunks.push(c);
  });
  req.on("end", () => {
    if (tooBig) return;
    try {
      const body = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
      const records = req.url === "/v1/metrics" ? metricRecords(body) : req.url === "/v1/logs" ? logRecords(body) : [];
      if (records.length) {
        const file = join(dir, `${new Date().toISOString().slice(0, 10)}.jsonl`);
        appendFileSync(file, records.map((r) => JSON.stringify(r)).join("\n") + "\n");
      }
      res.writeHead(200, { "content-type": "application/json" }).end("{}");
    } catch {
      res.writeHead(400).end();
    }
  });
});
server.on("error", (e) => process.exit(e.code === "EADDRINUSE" ? 0 : 1));
server.listen(port, "127.0.0.1");
