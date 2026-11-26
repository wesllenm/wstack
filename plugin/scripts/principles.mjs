#!/usr/bin/env node
// Princípios lidos de fato numa sessão do Claude Code, a partir da transcrição JSONL (skill lead, seção Relatório):
// as skills carregadas pela ferramenta Skill, por /comando digitado ou pela pré-carga (skills: do frontmatter) do agente
// da sessão e dos subagentes chamados, e os arquivos de reference/ e playbooks/ das skills lidos pelo Read.
// Com --report, confere o relatório: cada skill citada em "Princípios aplicados:" precisa ter sido carregada, e cada
// arquivo de "Referências lidas:" precisa ter sido lido. Sem dependências.
//   node <pasta do plugin>/scripts/principles.mjs <transcrição.jsonl> [<pasta de subagentes>] [--agent <nome>]
//        [--report <relatório> | --cited <skills citadas, separadas por vírgula, ou nenhum>]
// --cited: confere só a lista do campo "princípios:" da linha de Registro (o hook Stop usa); sai 3 se alguma não foi
// carregada.
// A transcrição fica em ~/.claude/projects/<projeto>/<sessão>.jsonl e os subagentes em <sessão>/subagents/*.jsonl.
// --agent: o agente da sessão principal (padrão lead, o "agent" do settings.json que o bootstrap gera).
// Saída: "carregadas:", "referências:", "AVISO:" com linhas ilegíveis e, com --report, "citadas:" e uma linha por
// problema: "NÃO CARREGADA:" (skill citada sem carga), "NÃO LIDA:" (referência sem leitura), "CAMPO AUSENTE:".
// Chamada de ferramenta que falhou (is_error) não conta como carga nem leitura.
// Código: 0 ok, 1 arquivo ou pasta ilegível, 2 uso errado, 3 citação sem leitura.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const fail = (code, msg) => { console.error(`principles: ${msg}`); process.exit(code); };
const pos = [];
let agent = 'lead', report = null, citedArg = null;
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i], v = () => (i + 1 < argv.length ? argv[++i] : fail(2, `${a} sem valor`));
  if (a === '--agent') agent = v();
  else if (a === '--report') report = v();
  else if (a === '--cited') citedArg = v();
  else if (a.startsWith('--')) fail(2, `opção desconhecida: ${a}`);
  else pos.push(a);
}
if (pos.length < 1 || pos.length > 2) fail(2, 'uso: principles.mjs <transcrição.jsonl> [<pasta de subagentes>] [--agent <nome>] [--report <relatório> | --cited <lista>]');
if (report !== null && citedArg !== null) fail(2, '--report e --cited são exclusivos');
if (!/^[a-z0-9-]+$/.test(agent)) fail(2, `--agent inválido: ${agent}`);
const [file, subDir] = pos;

// Nome curto da skill: sem o prefixo do plugin wstack; skill de outro plugin fica com o prefixo dele.
const short = (s) => String(s).trim().replace(/^\/+/, '').replace(/^wstack:/, '');

// Pré-carga de um agente do plugin: o campo skills: do frontmatter de agents/<nome>.md.
const agentsDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'agents');
function preloads(name) {
  const p = join(agentsDir, `${name}.md`);
  if (!/^[a-z0-9-]+$/.test(name) || !existsSync(p)) return [];
  // CRLF tolerado: arquivo salvo no Windows não pode passar sem pré-carga e sem aviso
  const fm = /^---\n([\s\S]*?)\n---\n/.exec(readFileSync(p, 'utf8').replace(/\r\n/g, '\n'))?.[1] ?? '';
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
  return text.split('\n').filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { unreadable++; return []; } });
}
let unreadable = 0; // linhas que não são JSON: evidência que pode estar faltando, contada e avisada

const loaded = new Map(); // skill -> origem
const refs = new Set();   // <skill>/<reference|playbooks>/<arquivo>.md
const add = (skill, origin) => { if (skill && !loaded.has(skill)) loaded.set(skill, origin); };
for (const s of preloads(agent)) add(s, `pré-carga de ${agent}`);

// Chamada de ferramenta que falhou (tool_result com is_error) não conta: Skill recusada não carregou nada, Read que
// falhou não leu. O id da chamada liga o tool_use ao resultado dele, no mesmo arquivo.
function failedIds(entries) {
  const ids = new Set();
  for (const e of entries) {
    const content = e.message?.content;
    if (!Array.isArray(content)) continue;
    for (const b of content) if (b?.type === 'tool_result' && b.is_error === true && b.tool_use_id) ids.add(b.tool_use_id);
  }
  return ids;
}

function collect(entries) {
  const failed = failedIds(entries);
  for (const e of entries) {
    const content = e.message?.content;
    const texts = typeof content === 'string' ? [content] : [];
    if (Array.isArray(content)) {
      for (const b of content) {
        if (b?.type === 'text' && e.message?.role === 'user') texts.push(String(b.text ?? ''));
        if (b?.type !== 'tool_use' || failed.has(b.id)) continue;
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
if (unreadable) console.log(`AVISO: ${unreadable} linha(s) da transcrição não são JSON e foram ignoradas: o que estava nelas não conta como leitura`);
// --cited: a lista da linha de Registro ("tdd, query-plan" ou "nenhum"); cada nome precisa ter sido carregado
if (citedArg !== null) {
  const names = citedArg.split(',').map((x) => short(x.replace(/`/g, ''))).filter(Boolean);
  if (!names.length) { console.log('CAMPO AUSENTE: lista de princípios vazia (use "nenhum")'); process.exit(3); }
  const bad = names.filter((n) => !/^nenhum[a]?$/i.test(n) && !loaded.has(n));
  if (names.some((n) => /^nenhum[a]?$/i.test(n)) && names.length > 1) bad.push('"nenhum" junto de outros nomes');
  console.log(`citadas: ${names.join(', ')}`);
  for (const b of bad) console.log(`NÃO CARREGADA: ${b} citada em princípios: da linha de Registro`);
  process.exit(bad.length ? 3 : 0);
}
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
const missing = []; // [rótulo, texto]
const cited = new Set();
const principles = field('Princípios aplicados');
if (principles === null) missing.push(['CAMPO AUSENTE', '"Princípios aplicados:" não está no relatório']);
for (const item of principles ?? []) {
  // travessão e meia-risca separam com ou sem espaço ("lead—motivo"); hífen só com espaço, porque nome de skill tem
  // hífen (query-plan)
  const skill = short(item.split(/\s*[—–]\s*|\s+-\s+/)[0].replace(/`/g, ''));
  cited.add(skill);
  if (!loaded.has(skill)) missing.push(['NÃO CARREGADA', `${skill} citada em Princípios aplicados`]);
}
const readRefs = field('Referências lidas');
if (readRefs === null) missing.push(['CAMPO AUSENTE', '"Referências lidas:" não está no relatório']);
for (const item of readRefs ?? []) {
  for (const m of item.matchAll(/([a-z0-9-]+\/)?(reference|playbooks)\/([^\s`—–;,]+\.md)/g)) {
    // sem o nome da skill, a referência é da skill do agente da sessão (--agent, padrão lead: o relatório do lead
    // escreve "reference/revisao.md"); referência de outra skill leva o nome dela ("performance/reference/dotnet.md"),
    // para um arquivo lido de uma skill não valer pela citação de outra
    const key = `${m[1] ? m[1].slice(0, -1) : agent}/${m[2]}/${m[3]}`;
    if (!refs.has(key)) missing.push(['NÃO LIDA', `${key} listada em Referências lidas`]);
  }
}
console.log(`citadas: ${cited.size ? sorted(cited).join(', ') : 'nenhuma'}`);
for (const [label, msg] of missing) console.log(`${label}: ${msg}`);
process.exit(missing.length ? 3 : 0);
