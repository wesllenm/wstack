#!/usr/bin/env node
// Válvulas de escape e comentários nas linhas que o diff adicionou.
//   ESCAPE            supressão de aviso, tipo que desliga o compilador, exceção engolida, bloqueio de async
//   CODIGO_COMENTADO  comentário cujo corpo é código
//   MARCADOR          TODO, FIXME, HACK, XXX, workaround, gambiarra, temporário
//   RESTRICAO         comentário que descreve uma regra ("não", "nunca", "sempre", "deve", "obrigatório", "never",
//                     "always", "must", "do not", "required"): regra que só o modelo lê; a review-simplicity propõe
//                     como garanti-la no código (tipo, checagem, teste, lint). Conta no limite de COMENTARIO
//   COMENTARIO        qualquer outro comentário novo: o lead justifica cada um (porquê não óbvio) ou remove
//   DOC               comentário de documentação (///, /** */, docstring): informativo
// Linha movida (o mesmo texto removido em outro ponto do diff) não conta: só o que o diff introduziu.
// Uso: node diff-smells.mjs [--base <ref>] [--text] [--gate]
//   --gate  código 1 quando há CODIGO_COMENTADO, MARCADOR, ou ESCAPE/COMENTARIO acima dos limites do risk.conf
// Código: 0 ok, 1 limite estourado (só com --gate), 2 uso errado, 3 falha ao ler o diff ou a configuração.
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, posix } from 'node:path';
import { validValues } from '../hooks/conf-exception.mjs';

function die(code, msg) { console.error(`diff-smells: ${msg}`); process.exit(code); }
const argv = process.argv.slice(2);
let baseArg = null, text = false, gate = false;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--base') { if (i + 1 >= argv.length) die(2, '--base sem valor'); baseArg = argv[++i]; }
  else if (a === '--text') text = true;
  else if (a === '--gate') gate = true;
  else die(2, `argumento desconhecido: ${a}`);
}
if (baseArg !== null && baseArg.startsWith('-')) die(2, 'base inválida');

const git = (...a) => execFileSync('git', ['-c', 'core.quotePath=false', ...a],
  { encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'pipe'] });
let root;
try { root = git('rev-parse', '--show-toplevel').trim(); } catch { die(3, 'fora de um repositório git'); }
process.chdir(root);

// ---------- configuração ----------
const conf = { base: 'main', smell_escape_limit: 0, smell_comment_limit: 3 };
const exclude = [];
const confPath = join(root, '.claude', 'risk.conf');
if (existsSync(confPath)) {
  for (const raw of readFileSync(confPath, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([a-z_]+)\s*=\s*(.*?)\s*$/.exec(raw);
    if (!m || raw.trim().startsWith('#')) continue;
    if (m[1] === 'smell_exclude') exclude.push(...validValues([m[2]])); // exceção com validade
    else if (m[1] in conf) conf[m[1]] = m[1] === 'base' ? m[2] : Number(m[2]);
  }
}
for (const k of ['smell_escape_limit', 'smell_comment_limit'])
  if (!Number.isInteger(conf[k]) || conf[k] < 0) die(3, `${k} inválido no risk.conf`);

function globRe(glob) {
  let re = '', i = 0;
  while (i < glob.length) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      if (glob[i + 2] === '/') { re += '(?:.*/)?'; i += 3; } else { re += '.*'; i += 2; }
    } else if (c === '*') { re += '[^/]*'; i++; }
    else if (c === '?') { re += '[^/]'; i++; }
    else { re += c.replace(/[.+^$()|[\]\\{}]/g, '\\$&'); i++; }
  }
  return new RegExp('^' + re + '$', 'i');
}
const matcher = (g) => { const re = globRe(g); return g.includes('/') ? (p) => re.test(p) : (p) => re.test(posix.basename(p)); };
const EXCLUDED = ['**/bin/**', '**/obj/**', '**/node_modules/**', '**/dist/**', '**/build/**', '**/target/**',
  '*.Designer.cs', '*.g.cs', '*.g.i.cs', '*.generated.*', '*ModelSnapshot.cs', '**/Migrations/**', '**/Generated/**',
  '*.min.js', '*.d.ts', '.claude/**', 'docs/**', '*.md', ...exclude].map(matcher);
const isExcluded = (p) => EXCLUDED.some((m) => m(p));

// ---------- linguagens ----------
const C_LIKE = { line: '//', block: true };
const LANGS = [
  { re: /\.(cs|razor)$/i, name: 'cs', ...C_LIKE, doc: /^\s*\/\/\//, escapes: [
    [/#pragma\s+warning\s+disable/, 'aviso desligado (#pragma)'],
    [/\[\s*(assembly:\s*)?SuppressMessage\s*\(/, 'aviso suprimido ([SuppressMessage])'],
    [/#nullable\s+disable/, 'nullable desligado'],
    [/(?:^|[^\w.])dynamic\s+\w/, 'tipo dynamic'],
    [/\(\s*object\s*\)\s*\w/, 'cast para object'],
    // null! e default! são o idioma de teste de guarda de argumento nulo: não contam
    [/[\w)\]](?<!\bnull)(?<!\bdefault)!(?=[.;,)\]\s?]|$)/, 'null-forgiving (!)'],
    // .Result e .Wait() só depois de chamada ou de nome com Task/Async: result.Result de um Result<T> não conta
    [/\.GetAwaiter\(\)\s*\.GetResult\(\)|(?:\)|\b\w*(?:[Tt]ask|Async)\w*)\s*\.(?:Result\b(?!\s*=)|Wait\(\s*\))/, 'bloqueio de async (.Result/.Wait)'],
    [/catch\s*(\(\s*(System\.)?Exception(\s+\w+)?\s*\))?\s*\{\s*\}/, 'exceção engolida'],
  ] },
  { re: /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|svelte|vue)$/i, name: 'ts', ...C_LIKE, doc: /^\s*\/\*\*/, escapes: [
    [/@ts-(ignore|nocheck|expect-error)/, 'checagem de tipo desligada (@ts-)', true],
    [/eslint-disable/, 'regra de lint desligada', true],
    [/:\s*any\b|<any>|\bas\s+any\b|\bany\[\]/, 'tipo any'],
    [/\bas\s+unknown\s+as\b/, 'cast duplo (as unknown as)'],
    [/[\w)\]]!(?=[.;,)\]\s]|$)/, 'non-null assertion (!)'],
    [/catch\s*(\(\s*\w*\s*\))?\s*\{\s*\}/, 'exceção engolida'],
  ] },
  { re: /\.rs$/i, name: 'rs', ...C_LIKE, doc: /^\s*\/\/[\/!]/, escapes: [
    [/#!?\[allow\(/, 'lint desligado (#[allow])'],
    [/\.unwrap\(\)/, 'unwrap'],
    [/\bunsafe\s*\{/, 'bloco unsafe'],
  ] },
  { re: /\.py$/i, name: 'py', line: '#', block: false, doc: /^\s*("""|''')/, escapes: [
    [/#\s*type:\s*ignore/, 'checagem de tipo desligada', true],
    [/#\s*noqa/, 'lint desligado (noqa)', true],
    [/except\s*(Exception\s*)?:\s*pass\b/, 'exceção engolida'],
    [/\bAny\b/, 'tipo Any'],
  ] },
  { re: /\.(sh|bash)$/i, name: 'sh', line: '#', block: false, doc: null, escapes: [
    [/#\s*shellcheck\s+disable/, 'shellcheck desligado', true],
    [/\|\|\s*true\s*$/, 'erro ignorado (|| true)'],
  ] },
  { re: /\.(go|java|kt|kts|swift|c|cc|cpp|h|hpp)$/i, name: 'c', ...C_LIKE, doc: /^\s*\/\*\*/, escapes: [
    [/@SuppressWarnings|#pragma\s+warning/, 'aviso desligado'],
    [/\/\/\s*nolint/, 'lint desligado (nolint)', true],
  ] },
];
const langOf = (p) => LANGS.find((l) => l.re.test(p));
// delimitadores de string de várias linhas: raw string do C# 11+ e template string do JS/TS
const MULTILINE = { cs: /"{3,}/g, ts: /(?<!\\)`/g };

const MARKER = /\b(TODO|FIXME|HACK|XXX)\b|\bworkaround\b|\bgambiarra\b|\btempor[áa]ri[oa]\b|\btemporary\b/i;
// palavra inteira, com letra acentuada contando como letra (\b do JS só vê ASCII)
const RESTRICTION = /(?<!\p{L})(n[ãa]o|nunca|sempre|devem?|obrigat[óo]ri[oa]s?|never|always|must|do not|don't|required)(?!\p{L})/iu;
const CODE_BODY = /;\s*$|^[{}]\s*$|^\s*(var|let|const|return|if|for|foreach|while|await|public|private|protected|internal|using|import|from|fn|def|class|new)\b.*[;({=]|^\s*[\w.]+\s*\(.*\)\s*;?\s*$|^\s*[\w.]+\s*=\s*.+;\s*$/;

// Separa código e comentário de uma linha. Strings viram espaços antes, para "//" numa URL não virar comentário
// e "!" num texto não virar null-forgiving.
function split(line, lang, inBlock) {
  if (inBlock) {
    const end = line.indexOf('*/');
    return end < 0 ? { code: '', comment: line.replace(/^\s*\*?/, ''), inBlock: true, block: true }
      : { code: line.slice(end + 2), comment: line.slice(0, end).replace(/^\s*\*?/, ''), inBlock: false, block: true };
  }
  const blank = line.replace(/@?"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`/g, (s) => ' '.repeat(s.length));
  let lc = -1;
  if (lang.line === '#') { const m = /(^|\s)#(?!!)/.exec(blank); if (m) lc = m.index + m[1].length; }
  else lc = blank.indexOf('//');
  const bc = lang.block ? blank.indexOf('/*') : -1;
  if (bc >= 0 && (lc < 0 || bc < lc)) {
    const end = blank.indexOf('*/', bc + 2);
    return end < 0 ? { code: blank.slice(0, bc), comment: line.slice(bc + 2), inBlock: true, block: true }
      : { code: blank.slice(0, bc) + blank.slice(end + 2), comment: line.slice(bc + 2, end), inBlock: false, block: true };
  }
  if (lc >= 0) return { code: blank.slice(0, lc), comment: line.slice(lc + lang.line.length), inBlock: false, block: false };
  return { code: blank, comment: null, inBlock: false, block: false };
}

// ---------- diff ----------
let mb;
const base = baseArg || conf.base;
try { mb = git('merge-base', 'HEAD', base).trim(); } catch {
  if (baseArg) die(3, `base inválida: ${base}`);
  // base do risk.conf ausente (repositório sem main local): compara com HEAD, só o que não foi commitado
  try { mb = git('rev-parse', '--verify', 'HEAD').trim(); } catch { die(3, `não foi possível resolver a base ${base} nem HEAD`); }
  console.error(`diff-smells: base ${base} não encontrada; comparando com HEAD`);
}
let diff;
try { diff = git('diff', '-U0', '--no-color', '--no-ext-diff', mb, '--'); } catch (e) { die(3, `git diff falhou: ${e.message}`); }
const added = new Map(); // arquivo -> [{line, text}]
const removed = new Set();
let file = null, lineNo = 0;
for (const l of diff.split('\n')) {
  if (l.startsWith('+++ ')) { file = l === '+++ /dev/null' ? null : l.slice(6); continue; }
  if (l.startsWith('--- ')) continue;
  const h = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(l);
  if (h) { lineNo = Number(h[1]); continue; }
  if (l.startsWith('-')) { removed.add(l.slice(1).trim()); continue; }
  if (l.startsWith('+') && file) { (added.get(file) || added.set(file, []).get(file)).push({ line: lineNo, text: l.slice(1) }); lineNo++; }
}
let untracked = [];
try { untracked = git('ls-files', '--others', '--exclude-standard', '-z').split('\0').filter(Boolean); } catch { /* sem não rastreados */ }
for (const f of untracked) {
  let content;
  try { content = readFileSync(join(root, f), 'utf8'); } catch { continue; }
  if (content.includes('\0')) continue;
  added.set(f, content.split(/\r?\n/).map((t, i) => ({ line: i + 1, text: t })));
}

// ---------- análise ----------
const items = [];
for (const [f, lines] of added) {
  if (isExcluded(f)) continue;
  const lang = langOf(f);
  if (!lang) continue;
  let inBlock = false, docBlock = false, inString = false, prev = -1;
  const ml = MULTILINE[lang.name];
  for (const { line, text: raw } of lines) {
    // trecho não contíguo: o estado de comentário e de string da linha anterior não vale
    if (line !== prev + 1) { inBlock = false; docBlock = false; inString = false; }
    prev = line;
    let t = raw;
    if (ml) {
      const marks = [...raw.matchAll(ml)];
      const was = inString;
      if (marks.length % 2 === 1) inString = !inString;
      if (was) continue; // linha dentro de string de várias linhas aberta numa linha adicionada anterior
      if (inString) t = raw.slice(0, marks[marks.length - 1].index); // a string abre aqui: só o que vem antes
    }
    const moved = removed.has(raw.trim()) && raw.trim().length > 0;
    const startsBlock = !inBlock, continuation = inBlock;
    const s = split(t, lang, inBlock);
    if (startsBlock && s.block && lang.doc && lang.doc.test(t)) docBlock = true;
    const isDoc = docBlock || (lang.doc && !s.block && lang.doc.test(t));
    inBlock = s.inBlock;
    if (!inBlock) docBlock = false;
    if (moved) continue;
    const add = (kind, detail) => items.push({ kind, file: f, line, detail, text: raw.trim().slice(0, 160) });
    // diretiva que vive em comentário (@ts-ignore, eslint-disable, noqa) é testada na linha inteira; o resto, só no código
    let directive = false;
    for (const [re, label, inComment] of lang.escapes) {
      if (re.test(inComment ? t : s.code)) { add('ESCAPE', label); directive = !!inComment; break; }
    }
    if (s.comment === null) continue;
    const body = s.comment.replace(/^[\s/*!#]+/, '').trim();
    if (!body || /^-+$|^=+$/.test(body)) continue;
    if (directive) continue;
    if (/^(SAFETY|SPDX-License-Identifier|Copyright)\b/i.test(body) || /^#!/.test(t.trim())) continue;
    if (MARKER.test(body)) add('MARCADOR', body.slice(0, 80));
    else if (CODE_BODY.test(body)) add('CODIGO_COMENTADO', '');
    else if (continuation) continue; // bloco de comentário conta uma vez, na linha em que abre
    else if (isDoc) add('DOC', '');
    else if (RESTRICTION.test(body)) add('RESTRICAO', RESTRICTION.exec(body)[1].toLowerCase());
    else add('COMENTARIO', '');
  }
}

const count = (k) => items.filter((i) => i.kind === k).length;
const order = ['ESCAPE', 'CODIGO_COMENTADO', 'MARCADOR', 'RESTRICAO', 'COMENTARIO', 'DOC'];
const totals = Object.fromEntries(order.map((k) => [k, count(k)]));
const over = [];
if (totals.ESCAPE > conf.smell_escape_limit) over.push(`ESCAPE ${totals.ESCAPE} > ${conf.smell_escape_limit}`);
if (totals.CODIGO_COMENTADO > 0) over.push(`CODIGO_COMENTADO ${totals.CODIGO_COMENTADO}`);
if (totals.MARCADOR > 0) over.push(`MARCADOR ${totals.MARCADOR}`);
// comentário de restrição continua sendo comentário: o limite vale para os dois juntos, como antes da separação
const comments = totals.COMENTARIO + totals.RESTRICAO;
if (comments > conf.smell_comment_limit) over.push(`COMENTARIO ${comments} > ${conf.smell_comment_limit}`);

if (text) {
  for (const k of order) for (const i of items.filter((x) => x.kind === k))
    console.log(`${k.padEnd(16)} ${i.file}:${i.line}${i.detail ? '  ' + i.detail : ''}  | ${i.text}`);
  console.log(`total: ${order.map((k) => `${k}=${totals[k]}`).join(' ')}  base=${mb.slice(0, 12)}`);
  console.log(over.length ? `acima do limite: ${over.join('; ')}` : 'dentro dos limites');
} else {
  console.log(JSON.stringify({ base: mb, limits: { escape: conf.smell_escape_limit, comment: conf.smell_comment_limit }, totals, over, items }, null, 2));
}
process.exit(gate && over.length ? 1 : 0);
