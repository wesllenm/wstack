#!/usr/bin/env node
// Princípios lidos de fato numa sessão do Claude Code, a partir da transcrição JSONL (skill lead, seção Relatório):
// as skills carregadas pela ferramenta Skill, por /comando digitado ou pela pré-carga (skills: do frontmatter) do agente
// da sessão e dos subagentes chamados, e os arquivos de reference/ e playbooks/ das skills lidos pelo Read.
// Com --report, confere o relatório: cada skill citada em "Princípios aplicados:" precisa ter sido carregada, e cada
// arquivo de "Referências lidas:" precisa ter sido lido. Sem dependências.
//   node <pasta do plugin>/scripts/principles.mjs <transcrição.jsonl> [<pasta de subagentes>] [--agent <nome>]
//        [--report <relatório>]
// A transcrição fica em ~/.claude/projects/<projeto>/<sessão>.jsonl e os subagentes em <sessão>/subagents/*.jsonl.
// --agent: o agente da sessão principal (padrão lead, o "agent" do settings.json que o bootstrap gera).
// Saída: "carregadas:", "referências:" e, com --report, "citadas:" e uma linha "SEM LEITURA:" por citação sem leitura.
// Código: 0 ok, 1 arquivo ou pasta ilegível, 2 uso errado, 3 citação sem leitura.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const fail = (code, msg) => { console.error(`principles: ${msg}`); process.exit(code); };
const pos = [];
let agent = 'lead', report = null;
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i], v = () => (i + 1 < argv.length ? argv[++i] : fail(2, `${a} sem valor`));
  if (a === '--agent') agent = v();
  else if (a === '--report') report = v();
  else if (a.startsWith('--')) fail(2, `opção desconhecida: ${a}`);
  else pos.push(a);
}
if (pos.length < 1 || pos.length > 2) fail(2, 'uso: principles.mjs <transcrição.jsonl> [<pasta de subagentes>] [--agent <nome>] [--report <relatório>]');
if (!/^[a-z0-9-]+$/.test(agent)) fail(2, `--agent inválido: ${agent}`);
const [file, subDir] = pos;

// Nome curto da skill: sem o prefixo do plugin wstack; skill de outro plugin fica com o prefixo dele.
const short = (s) => String(s).trim().replace(/^\/+/, '').replace(/^wstack:/, '');

// Pré-carga de um agente do plugin: o campo skills: do frontmatter de agents/<nome>.md.
const agentsDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'agents');
function preloads(name) {
  const p = join(agentsDir, `${name}.md`);
  if (!/^[a-z0-9-]+$/.test(name) || !existsSync(p)) return [];
  const fm = /^---\n([\s\S]*?)\n---\n/.exec(readFileSync(p, 'utf8'))?.[1] ?? '';
  const lines = fm.split('\n');
  const i = lines.findIndex((l) => l.startsWith('skills:'));
  if (i < 0) return [];
  const inline = lines[i].slice('skills:'.length).trim();
  if (inline) return inline.split(',').map(short).filter(Boolean);
  const out = [];
  for (const l of lines.slice(i + 1)) { const m = /^\s+-\s+(.*)$/.exec(l); if (!m) break; out.push(short(m[1])); }
  return out;
}

function readJsonl(path) {
  let text;
  try { text = readFileSync(path, 'utf8'); } catch (e) { return fail(1, `não consegui ler ${path}: ${e.code ?? e.message}`); }
  return text.split('\n').filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
}

const loaded = new Map(); // skill -> origem
const refs = new Set();   // <skill>/<reference|playbooks>/<arquivo>.md
const add = (skill, origin) => { if (skill && !loaded.has(skill)) loaded.set(skill, origin); };
for (const s of preloads(agent)) add(s, `pré-carga de ${agent}`);

function collect(entries) {
  for (const e of entries) {
    const content = e.message?.content;
    const texts = typeof content === 'string' ? [content] : [];
    if (Array.isArray(content)) {
      for (const b of content) {
        if (b?.type === 'text' && e.message?.role === 'user') texts.push(String(b.text ?? ''));
        if (b?.type !== 'tool_use') continue;
        const input = b.input ?? {};
        if (b.name === 'Skill' && input.skill) add(short(input.skill), 'ferramenta Skill');
        if ((b.name === 'Agent' || b.name === 'Task') && input.subagent_type) {
          const sub = short(input.subagent_type);
          for (const s of preloads(sub)) add(s, `pré-carga de ${sub}`);
        }
        if (b.name === 'Read' && typeof input.file_path === 'string') {
          const m = /\/skills\/([a-z0-9-]+)\/(reference|playbooks)\/([^/]+\.md)$/.exec(input.file_path.replace(/\\/g, '/'));
          if (m) refs.add(`${m[1]}/${m[2]}/${m[3]}`);
        }
      }
    }
    // /comando digitado pelo desenvolvedor: o Claude Code registra <command-name>/plugin:skill</command-name>
    if (e.message?.role === 'user') {
      for (const t of texts) for (const m of t.matchAll(/<command-name>\/?([\w:-]+)<\/command-name>/g)) add(short(m[1]), '/comando');
    }
  }
}

collect(readJsonl(file));
if (subDir) {
  let names;
  try {
    if (!statSync(subDir).isDirectory()) fail(1, `${subDir} não é uma pasta`);
    names = readdirSync(subDir).filter((n) => n.endsWith('.jsonl')).sort();
  } catch (e) { fail(1, `não consegui ler ${subDir}: ${e.code ?? e.message}`); }
  for (const n of names) collect(readJsonl(join(subDir, n)));
}

const sorted = (it) => [...it].sort();
console.log(`carregadas: ${loaded.size ? sorted(loaded.keys()).join(', ') : 'nenhuma'}`);
console.log(`referências: ${refs.size ? sorted(refs).join(', ') : 'nenhuma'}`);
if (!report) process.exit(0);

// Relatório: o campo é a linha "Princípios aplicados:" e as linhas seguintes que começam com "-", até o próximo campo.
let text;
try { text = readFileSync(report, 'utf8'); } catch (e) { fail(1, `não consegui ler ${report}: ${e.code ?? e.message}`); }
function field(name) {
  const lines = text.split(/\r?\n/);
  const i = lines.findIndex((l) => l.startsWith(`${name}:`));
  if (i < 0) return null;
  const items = [lines[i].slice(name.length + 1)];
  for (const l of lines.slice(i + 1)) { if (!/^\s*-\s/.test(l)) break; items.push(l.replace(/^\s*-\s/, '')); }
  return items.map((x) => x.trim()).filter((x) => x && !/^nenhum[a]?$/i.test(x));
}
const missing = [];
const cited = new Set();
const principles = field('Princípios aplicados');
if (principles === null) missing.push('campo "Princípios aplicados:" ausente no relatório');
for (const item of principles ?? []) {
  const skill = short(item.split(/\s+—\s+/)[0].replace(/`/g, ''));
  cited.add(skill);
  if (!loaded.has(skill)) missing.push(`${skill} citado sem ter sido carregado`);
}
for (const item of field('Referências lidas') ?? []) {
  for (const m of item.matchAll(/([a-z0-9-]+\/)?(reference|playbooks)\/([^\s`—;,]+\.md)/g)) {
    const key = `${m[1] ? m[1].slice(0, -1) : 'lead'}/${m[2]}/${m[3]}`;
    if (!refs.has(key)) missing.push(`${key} listado em Referências lidas sem ter sido lido`);
  }
}
console.log(`citadas: ${cited.size ? sorted(cited).join(', ') : 'nenhuma'}`);
for (const m of missing) console.log(`SEM LEITURA: ${m}`);
process.exit(missing.length ? 3 : 0);
