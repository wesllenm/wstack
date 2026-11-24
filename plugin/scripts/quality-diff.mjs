#!/usr/bin/env node
// Sinais de qualidade restritos ao diff: CRAP por função tocada e duplicação estrutural que envolve código do diff.
// Uso: node quality-diff.mjs --base <ref> [--crap-threshold 30] [--crap-info 10] [--include-tests]
//        [--cobertura <xml>]...                     .NET (coverlet): complexidade, intervalo e cobertura por método
//        [--istanbul <coverage-final.json>]... [--eslint <json>]...   JS/TS/Svelte: intervalo e cobertura + complexidade
//        [--lcov <lcov.info>]... [--rca <json|pasta>]...              Rust: cobertura + rust-code-analysis
//        [--jscpd <jscpd-report.json>]...           duplicação (qualquer stack)
// CRAP = CC² × (1 − cobertura)³ + CC. Saída: uma linha por achado. Código: 0 sem candidato, 1 com candidato,
// 2 uso errado, 3 falha de leitura.
import { readFileSync, existsSync, statSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';

const args = { base: 'main', crapThreshold: 30, crapInfo: 10, includeTests: false,
  cobertura: [], istanbul: [], eslint: [], lcov: [], rca: [], jscpd: [] };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i], v = () => { if (i + 1 >= argv.length) usage(`${a} sem valor`); return argv[++i]; };
  switch (a) {
    case '--base': args.base = v(); break;
    case '--crap-threshold': args.crapThreshold = Number(v()); break;
    case '--crap-info': args.crapInfo = Number(v()); break;
    case '--include-tests': args.includeTests = true; break;
    case '--cobertura': case '--istanbul': case '--eslint': case '--lcov': case '--rca': case '--jscpd':
      args[a.slice(2)].push(v()); break;
    default: usage(`argumento desconhecido: ${a}`);
  }
}
function usage(msg) { console.error(`quality-diff: ${msg}`); process.exit(2); }
function fail(msg) { console.error(`quality-diff: ${msg}`); process.exit(3); }
if (![args.crapThreshold, args.crapInfo].every(Number.isFinite)) usage('limite de CRAP não numérico');

const git = (...a) => execFileSync('git', ['-c', 'core.quotePath=false', ...a],
  { encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'pipe'] });
let root;
try { root = git('rev-parse', '--show-toplevel').trim(); } catch { fail('fora de um repositório git'); }
const rootKey = root.replace(/\\/g, '/').replace(/\/$/, '');

const TEST_RE = /(^|\/)(tests?|Tests?|__tests__|specs?)\/|[._-](test|spec)s?\.[A-Za-z0-9]+$|[a-z0-9]Tests?\.cs$|(^|\/)test_[^/]*\.py$|_test\.(go|rs|py)$/;

// Caminho de relatório -> caminho relativo à raiz do repositório, com "/".
function rel(p, reportDir) {
  let s = String(p).replace(/\\/g, '/');
  if (/^file:\/\//.test(s)) s = decodeURIComponent(s.replace(/^file:\/\//, ''));
  const abs = isAbsolute(s) || /^[A-Za-z]:\//.test(s);
  if (abs) {
    const low = s.toLowerCase(), r = rootKey.toLowerCase();
    if (low.startsWith(r + '/')) return s.slice(rootKey.length + 1);
    return s;
  }
  if (existsSync(join(root, s))) return s.replace(/^\.\//, '');
  if (reportDir) {
    const cand = resolve(reportDir, s);
    if (existsSync(cand)) return relative(root, cand).replace(/\\/g, '/');
  }
  return s.replace(/^\.\//, '');
}
const read = (f) => { try { return readFileSync(f, 'utf8'); } catch (e) { fail(`não foi possível ler ${f}: ${e.message}`); } };

// ---------- linhas tocadas pelo diff ----------
let mb;
try { mb = git('merge-base', 'HEAD', args.base).trim(); } catch {
  try { mb = git('rev-parse', '--verify', args.base).trim(); } catch { fail(`base inexistente: ${args.base}`); }
}
const changed = new Map();   // arquivo -> [[início, fim]] (linhas novas; Infinity = arquivo inteiro)
const addRange = (f, a, b) => { if (!changed.has(f)) changed.set(f, []); changed.get(f).push([a, b]); };
let diffText;
try { diffText = git('diff', '-U0', '--no-color', '--no-ext-diff', mb); } catch { fail('git diff falhou'); }
let cur = null;
for (const line of diffText.split('\n')) {
  if (line.startsWith('+++ ')) {
    const p = line.slice(4).replace(/\t$/, '');
    cur = p === '/dev/null' ? null : p.replace(/^"?b\//, '').replace(/"$/, '');
  } else if (cur && line.startsWith('@@')) {
    const m = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/.exec(line);
    if (!m) continue;
    const start = Number(m[1]), n = m[2] === undefined ? 1 : Number(m[2]);
    if (n > 0) addRange(cur, start, start + n - 1);
    else addRange(cur, Math.max(start, 1), Math.max(start, 1) + 1);   // só remoção: marca a vizinhança
  }
}
try {
  for (const f of git('ls-files', '--others', '--exclude-standard', '-z').split('\0')) if (f) addRange(f, 1, Infinity);
} catch { fail('git ls-files falhou'); }

const isTest = (f) => TEST_RE.test(f);
const touches = (f, a, b) => (changed.get(f) || []).some(([x, y]) => x <= b && a <= y);
const insideDiff = (f, a, b) => (changed.get(f) || []).some(([x, y]) => x <= a && b <= y);

// ---------- cobertura por linha e funções ----------
const coverage = new Map();   // arquivo -> Map(linha -> hits)
const markLine = (f, l, h) => {
  if (!coverage.has(f)) coverage.set(f, new Map());
  const m = coverage.get(f); m.set(l, Math.max(m.get(l) || 0, h));
};
const functions = [];         // {file, start, end, name, cc}

const attr = (tag, name) => { const m = new RegExp(`\\s${name}="([^"]*)"`).exec(tag); return m ? m[1] : undefined; };
const unxml = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
function dotnetName(cls, method) {
  cls = unxml(cls); method = unxml(method);
  let m;
  if ((m = /^(.*)\/<([^>]+)>d__\d+$/.exec(cls))) return `${m[1]}.${m[2]}`;               // async/iterator
  if ((m = /^<([^>]+)>g__([^|]+)\|/.exec(method))) return `${cls.replace(/\/.*$/, '')}.${m[1]}.${m[2]}`; // local function
  if ((m = /^<([^>]+)>b__/.exec(method))) return `${cls.replace(/\/.*$/, '')}.${m[1]} (lambda)`;
  return `${cls.replace(/\/<>c.*$/, '')}.${method}`;
}
function loadCobertura(f) {
  const xml = read(f), dir = dirname(resolve(f));
  const sources = [...xml.matchAll(/<source>([^<]*)<\/source>/g)].map((m) => unxml(m[1]).trim());
  const resolveFile = (name) => {
    name = unxml(name);
    if (isAbsolute(name) || /^[A-Za-z]:[\\/]/.test(name)) return rel(name, dir);
    for (const s of sources) { const c = join(s, name); if (existsSync(c)) return rel(c, dir); }
    return rel(name, dir);
  };
  const classRe = /<class\s[^>]*>[\s\S]*?<\/class>/g;
  let found = 0;
  for (const cm of xml.matchAll(classRe)) {
    const block = cm[0], head = /<class\s[^>]*>/.exec(block)[0];
    const file = resolveFile(attr(head, 'filename') || ''), cls = attr(head, 'name') || '';
    for (const mm of block.matchAll(/<method\s[^>]*>[\s\S]*?<\/method>/g)) {
      const mh = /<method\s[^>]*>/.exec(mm[0])[0];
      const lines = [...mm[0].matchAll(/<line\s[^>]*>/g)].map((l) => [Number(attr(l[0], 'number')), Number(attr(l[0], 'hits'))]);
      if (!lines.length) continue;
      for (const [n, h] of lines) markLine(file, n, h);
      const nums = lines.map(([n]) => n);
      functions.push({ file, start: Math.min(...nums), end: Math.max(...nums),
        name: dotnetName(cls, attr(mh, 'name') || '?'), cc: Number(attr(mh, 'complexity')) || 1 });
      found++;
    }
    // linhas fora de métodos (propriedades automáticas, inicializadores) também contam como cobertura do arquivo
    for (const l of block.replace(/<methods>[\s\S]*?<\/methods>/, '').matchAll(/<line\s[^>]*>/g))
      markLine(file, Number(attr(l[0], 'number')), Number(attr(l[0], 'hits')));
  }
  if (!found) console.error(`aviso: ${f} não tem métodos com linhas`);
  if (found && functions.every((fn) => fn.cc <= 1)) console.error(`aviso: ${f} sem complexidade por método; CRAP vira só cobertura`);
}
function loadLcov(f) {
  const dir = dirname(resolve(f)); let file = null;
  for (const line of read(f).split(/\r?\n/)) {
    if (line.startsWith('SF:')) file = rel(line.slice(3), dir);
    else if (line.startsWith('DA:') && file) { const [n, h] = line.slice(3).split(','); markLine(file, Number(n), Number(h)); }
    else if (line === 'end_of_record') file = null;
  }
}
const eslintCc = new Map();   // arquivo -> [{line, column, cc}]
function loadEslint(f) {
  let data; try { data = JSON.parse(read(f)); } catch { fail(`${f} não é JSON do ESLint (-f json)`); }
  const dir = dirname(resolve(f));
  for (const r of data) {
    const file = rel(r.filePath, dir);
    for (const m of r.messages || []) {
      if (m.ruleId !== 'complexity') continue;
      const c = /has a complexity of (\d+)/.exec(m.message || '');
      if (!c) continue;
      if (!eslintCc.has(file)) eslintCc.set(file, []);
      eslintCc.get(file).push({ line: m.line, column: m.column, cc: Number(c[1]) });
    }
  }
}
const istanbulFns = [];
function loadIstanbul(f) {
  let data; try { data = JSON.parse(read(f)); } catch { fail(`${f} não é coverage-final.json do Istanbul`); }
  const dir = dirname(resolve(f));
  for (const [key, cov] of Object.entries(data)) {
    const file = rel(cov.path || key, dir);
    for (const [id, loc] of Object.entries(cov.statementMap || {}))
      for (let l = loc.start.line; l <= (loc.end?.line ?? loc.start.line); l++) markLine(file, l, cov.s?.[id] ?? 0);
    for (const fn of Object.values(cov.fnMap || {})) {
      const loc = fn.loc || fn.decl;
      istanbulFns.push({ file, start: loc.start.line, end: loc.end.line, col: loc.start.column, name: fn.name || '(anônima)' });
    }
  }
}
function loadRca(p) {
  const files = existsSync(p) && statSync(p).isDirectory()
    ? readdirSync(p, { recursive: true }).filter((x) => String(x).endsWith('.json')).map((x) => join(p, String(x))) : [p];
  for (const f of files) {
    const text = read(f).trim(); let objs;
    try { const v = JSON.parse(text); objs = Array.isArray(v) ? v : [v]; }
    catch { try { objs = text.split(/\r?\n/).filter(Boolean).map((l) => JSON.parse(l)); } catch { fail(`${f} não é JSON do rust-code-analysis`); } }
    for (const o of objs) {
      const file = rel(o.name, dirname(resolve(f)));
      const walk = (s) => {
        if (s.kind === 'function') functions.push({ file, start: s.start_line, end: s.end_line, name: s.name || '(closure)',
          cc: Math.round(s.metrics?.cyclomatic?.sum ?? s.metrics?.cyclomatic ?? 1) || 1 });
        for (const c of s.spaces || []) walk(c);
      };
      walk(o);
    }
  }
}

args.cobertura.forEach(loadCobertura); args.lcov.forEach(loadLcov);
args.istanbul.forEach(loadIstanbul); args.eslint.forEach(loadEslint); args.rca.forEach(loadRca);

// JS/TS: o ESLint informa a complexidade pela linha do cabeçalho; o Istanbul, o intervalo. Junta por arquivo e linha.
let unmatched = 0;
for (const [file, list] of eslintCc) {
  for (const e of list) {
    const cands = istanbulFns.filter((fn) => fn.file === file && fn.start === e.line);
    if (!cands.length) { if (changed.has(file)) unmatched++; continue; }
    const best = cands.reduce((a, b) => (Math.abs(b.col + 1 - e.column) < Math.abs(a.col + 1 - e.column) ? b : a));
    functions.push({ file, start: best.start, end: best.end, name: best.name, cc: e.cc });
  }
}
if (unmatched) console.error(`aviso: ${unmatched} função(ões) do diff com complexidade no ESLint sem intervalo no Istanbul (arquivo fora da cobertura?)`);

// Mescla duplicatas do mesmo nome no mesmo arquivo (stub async + MoveNext, várias lambdas do mesmo método).
const merged = new Map();
for (const fn of functions) {
  const k = `${fn.file}\0${fn.name}`, m = merged.get(k);
  if (!m) merged.set(k, { ...fn });
  else { m.start = Math.min(m.start, fn.start); m.end = Math.max(m.end, fn.end); m.cc = Math.max(m.cc, fn.cc); }
}

const out = []; let candidates = 0;
for (const fn of merged.values()) {
  if (!touches(fn.file, fn.start, fn.end)) continue;
  if (!args.includeTests && isTest(fn.file)) continue;
  const lines = coverage.get(fn.file);
  let total = 0, hit = 0;
  if (lines) for (const [l, h] of lines) if (l >= fn.start && l <= fn.end) { total++; if (h > 0) hit++; }
  const cov = total ? hit / total : 0;
  const crap = fn.cc * fn.cc * (1 - cov) ** 3 + fn.cc;
  if (crap < args.crapInfo) continue;
  const label = crap >= args.crapThreshold ? 'CRAP' : 'ATENÇÃO';
  if (label === 'CRAP') candidates++;
  const notes = [insideDiff(fn.file, fn.start, fn.end) ? 'nova' : 'alterada'];
  if (!lines) notes.push('arquivo fora do relatório de cobertura');
  else if (!total) notes.push('sem linhas instrumentadas');
  out.push({ crap, text: `${label.padEnd(8)}| ${crap.toFixed(1).padStart(6)} | cc ${String(fn.cc).padStart(3)} cov ${String(Math.round(cov * 100)).padStart(3)}% | ${fn.file}:${fn.start}-${fn.end} | ${fn.name} | ${notes.join(', ')}` });
}
out.sort((a, b) => b.crap - a.crap).forEach((o) => console.log(o.text));

// ---------- duplicação ----------
const pairs = new Set();
for (const f of args.jscpd) {
  let data; try { data = JSON.parse(read(f)); } catch { fail(`${f} não é relatório JSON do jscpd`); }
  const dir = dirname(resolve(f));
  for (const d of data.duplicates || []) {
    const side = (s) => ({ file: rel(s.name, dir), start: s.startLoc?.line ?? s.start, end: s.endLoc?.line ?? s.end });
    const a = side(d.firstFile), b = side(d.secondFile);
    if (!args.includeTests && (isTest(a.file) || isTest(b.file))) continue;
    const ta = touches(a.file, a.start, a.end), tb = touches(b.file, b.start, b.end);
    if (!ta && !tb) continue;
    const [x, y] = ta ? [a, b] : [b, a];
    const kind = ta && tb ? 'DIFF×DIFF' : 'DIFF×EXISTENTE';
    const key = [x, y].map((s) => `${s.file}:${s.start}-${s.end}`).sort().join(' ');
    if (pairs.has(key)) continue;
    pairs.add(key); candidates++;
    console.log(`DUPLICADO| ${kind} | ${x.file}:${x.start}-${x.end} ≈ ${y.file}:${y.start}-${y.end} | ${d.lines ?? y.end - y.start + 1} linhas${d.tokens ? `, ${d.tokens} tokens` : ''} | ${d.format || ''}`);
  }
}

if (!out.length && !pairs.size) console.log('sem sinais de qualidade no diff');
process.exit(candidates ? 1 : 0);
