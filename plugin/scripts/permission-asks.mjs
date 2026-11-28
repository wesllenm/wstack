// Conta os pedidos de permissão (decisão `ask` de hook PreToolUse) de uma sessão do Claude Code a partir da transcrição
// JSONL, agrupados por hook e motivo, com o comando de cada um. Sem dependências.
//   node <pasta do plugin>/scripts/permission-asks.mjs <transcrição.jsonl> [<pasta de subagentes>] [--until <data ISO>]
// Com --until, só conta o pedido cujo evento é daquele instante ou anterior (o gate do Stop passa a hora do commit que
// gravou a linha de Registro: o push que grava a linha não pode reabrir a contagem). Evento sem data conta sempre.
// Com --until-edit <caminho>, o instante é o da última edição desse arquivo pela ferramenta Edit, Write ou MultiEdit na
// transcrição principal: vem da transcrição, e não de data de commit, que o agente controla (GIT_COMMITTER_DATE). Sem
// edição achada, conta tudo.
// A transcrição fica em ~/.claude/projects/<projeto>/<sessão>.jsonl e os subagentes em <sessão>/subagents/*.jsonl.
// Formato medido (2.1.330): o ask é um anexo `hook_success` de `hookEvent: PreToolUse` cujo `stdout` é o JSON do hook
// (`hookSpecificOutput.permissionDecision: "ask"`), e `toolUseID` aponta para o `tool_use` com o comando. A aprovação
// manual aparece no resultado da ferramenta como `permissionDecision.source: "user_*"`. Texto que apenas cita um ask
// (resultado de ferramenta, mensagem) não conta: só o anexo de hook.
// Código: 0 contou, 1 arquivo ou pasta ilegível, 2 uso errado.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { basename, join } from "node:path";

const argv = process.argv.slice(2);
const ui = argv.indexOf("--until");
const until = ui >= 0 ? Date.parse(argv[ui + 1] ?? "") : NaN;
if (ui >= 0 && Number.isNaN(until)) {
  console.error("permission-asks: --until precisa de uma data ISO");
  process.exit(2);
}
const ue = argv.indexOf("--until-edit");
const editPath = ue >= 0 ? String(argv[ue + 1] ?? "").replace(/\\/g, "/") : "";
if (ue >= 0 && !editPath) {
  console.error("permission-asks: --until-edit precisa de um caminho");
  process.exit(2);
}
const flagged = new Set([ui, ue].filter((i) => i >= 0).flatMap((i) => [i, i + 1]));
const [file, subDir] = argv.filter((_, i) => !flagged.has(i));
if (!file) {
  console.error("uso: permission-asks.mjs <transcrição.jsonl> [<pasta de subagentes>]");
  process.exit(2);
}

const MAX_COMMAND = 120;
const unreadable = { count: 0 };

function fail(message) {
  console.error(`permission-asks: ${message}`);
  process.exit(1);
}

function readJsonl(path) {
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch (e) {
    return fail(`não consegui ler ${path}: ${e.code ?? e.message}`);
  }
  return text.split("\n").filter(Boolean).flatMap((line) => {
    try {
      return [JSON.parse(line)];
    } catch {
      unreadable.count++;
      return [];
    }
  });
}

function askReasons(stdout) {
  const text = stdout.trim();
  const candidates = [text, ...text.split("\n")];
  for (const c of candidates) {
    let parsed;
    try {
      parsed = JSON.parse(c);
    } catch {
      continue;
    }
    const out = parsed?.hookSpecificOutput;
    if (out?.permissionDecision === "ask") return [String(out.permissionDecisionReason ?? "")];
    if (out) return [];
  }
  return [];
}

function summarize(use) {
  if (!use) return "(ferramenta não encontrada)";
  const input = use.input ?? {};
  const detail = use.name === "Bash" ? input.command : (input.file_path ?? input.path ?? input.pattern ?? "");
  const flat = `${use.name}: ${detail ?? ""}`.replace(/\s+/g, " ").trim();
  return flat.length > MAX_COMMAND ? `${flat.slice(0, MAX_COMMAND)}...` : flat;
}

const asks = [];
let cut = NaN; // instante de corte: --until, --until-edit ou os dois (o menor)
const seen = new Set();
let manual = 0;

function collect(entries, label) {
  const uses = new Map();
  for (const e of entries) {
    const content = e.message?.content;
    if (!Array.isArray(content)) continue;
    for (const b of content) if (b?.type === "tool_use") uses.set(b.id, b);
  }
  for (const e of entries) {
    if (String(e.permissionDecision?.source ?? "").startsWith("user_")) manual++;
    const a = e.attachment;
    if (e.type !== "attachment" || a?.type !== "hook_success" || a.hookEvent !== "PreToolUse" || typeof a.stdout !== "string") continue;
    if (!Number.isNaN(cut) && Date.parse(e.timestamp ?? "") > cut) continue;
    for (const reason of askReasons(a.stdout)) {
      const key = `${e.uuid ?? a.toolUseID}|${reason}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const m = /^([\w.-]+):\s*([\s\S]*)$/.exec(reason);
      asks.push({ hook: m ? m[1] : "(hook sem nome)", reason: m ? m[2] : reason, label, command: summarize(uses.get(a.toolUseID)) });
    }
  }
}

const mainEntries = readJsonl(file);
cut = until;
if (editPath) {
  let last = NaN;
  for (const e of mainEntries) {
    const content = e.message?.content;
    if (!Array.isArray(content)) continue;
    for (const b of content) {
      const p = String(b?.input?.file_path ?? "").replace(/\\/g, "/");
      if (b?.type === "tool_use" && ["Edit", "Write", "MultiEdit"].includes(b.name) && (p === editPath || p.endsWith(`/${editPath}`))) {
        const t = Date.parse(e.timestamp ?? "");
        if (!Number.isNaN(t) && !(t <= last)) last = t;
      }
    }
  }
  if (!Number.isNaN(last)) cut = Number.isNaN(cut) ? last : Math.min(cut, last);
}
collect(mainEntries, "principal");
if (subDir) {
  let names;
  try {
    if (!statSync(subDir).isDirectory()) fail(`${subDir} não é uma pasta`);
    names = readdirSync(subDir).filter((n) => n.endsWith(".jsonl")).sort();
  } catch (e) {
    fail(`não consegui ler ${subDir}: ${e.code ?? e.message}`);
  }
  for (const n of names) collect(readJsonl(join(subDir, n)), basename(n, ".jsonl"));
}

const perHook = new Map();
for (const a of asks) perHook.set(a.hook, (perHook.get(a.hook) ?? 0) + 1);
const hooks = [...perHook].sort((x, y) => y[1] - x[1] || x[0].localeCompare(y[0])).map(([h, n]) => `${h} ${n}`);
const mainCount = asks.filter((a) => a.label === "principal").length;

console.log(asks.length ? `pedidos: ${asks.length} (${hooks.join(", ")})` : "pedidos: 0");
console.log(`aprovações manuais: ${manual}`);
console.log(`principal: ${mainCount}, subagentes: ${asks.length - mainCount}`);
if (unreadable.count) console.log(`linhas ilegíveis ignoradas: ${unreadable.count}`);

const groups = new Map();
for (const a of asks) {
  const key = `${a.hook}: ${a.reason}`;
  groups.set(key, [...(groups.get(key) ?? []), a]);
}
for (const [key, items] of [...groups].sort((x, y) => y[1].length - x[1].length || x[0].localeCompare(y[0]))) {
  console.log(`\n${items.length}x ${key}`);
  for (const i of items) console.log(`  - ${i.label} | ${i.command}`);
}
