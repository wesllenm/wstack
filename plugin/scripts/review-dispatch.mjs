#!/usr/bin/env node
// Decide o que vai para cada revisor LLM, de forma determinística (§6.13):
//   1. separa o que não deve ir para revisão por LLM (removido, binário, gerado, lockfile, excluído no risk.conf);
//   2. resolve, por arquivo, a referência da stack e a regra por caminho (review_rule no risk.conf);
//   3. agrupa os arquivos: um grupo só até review_group_threshold arquivos; acima disso, grupos por pasta,
//      interface com implementação e teste com o arquivo testado, até review_group_max arquivos e
//      review_group_max_lines linhas por grupo.
// Uso: node review-dispatch.mjs [--base <ref> | --commit <sha>] [--text]
// Saída: JSON (padrão) ou resumo em texto. Código: 0 ok, 2 uso errado, 3 falha ao ler o diff ou a configuração.
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, posix } from 'node:path';

function die(code, msg) { console.error(`review-dispatch: ${msg}`); process.exit(code); }
const argv = process.argv.slice(2);
let baseArg = null, commit = null, text = false;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i], v = () => { if (i + 1 >= argv.length) die(2, `${a} sem valor`); return argv[++i]; };
  if (a === '--base') baseArg = v();
  else if (a === '--commit') commit = v();
  else if (a === '--text') text = true;
  else if (a === '--json') text = false;
  else die(2, `argumento desconhecido: ${a}`);
}
if (baseArg && commit) die(2, '--base e --commit são exclusivos');
// Referência nunca começa com "-" (injeção de opção no git, como --output=<arquivo>).
for (const [name, val] of [['--base', baseArg], ['--commit', commit]])
  if (val !== null && (val.startsWith('-') || /[\0\r\n]/.test(val))) die(2, `${name} inválido`);

const git = (...a) => execFileSync('git', ['-c', 'core.quotePath=false', ...a],
  { encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'pipe'] });
let root;
try { root = git('rev-parse', '--show-toplevel').trim(); } catch { die(3, 'fora de um repositório git'); }
process.chdir(root);

// ---------- configuração (.claude/risk.conf) ----------
const conf = { base: 'main', review_group_threshold: 5, review_group_max: 10, review_group_max_lines: 400, review_max_file_lines: 1500 };
const pathRules = [], userExclude = [], userInclude = [];
const confPath = join(root, '.claude', 'risk.conf');
if (existsSync(confPath)) {
  for (const raw of readFileSync(confPath, 'utf8').split(/\r?\n/)) {
    const line = raw.replace(/^\s+|\s+$/g, '');
    if (!line || line.startsWith('#')) continue;
    const m = /^([a-z_]+)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    const [, key, value] = m;
    if (key === 'review_rule') {
      const r = /^(.+?)\s*->\s*(.+)$/.exec(value);
      if (!r) die(3, `review_rule sem "->": ${line}`);
      pathRules.push({ glob: r[1].trim(), file: r[2].trim() });
    } else if (key === 'review_exclude') userExclude.push(value.trim());
    else if (key === 'review_include') userInclude.push(value.trim());
    else if (key in conf) conf[key] = key === 'base' ? value.trim() : Number(value);
  }
}
for (const k of ['review_group_threshold', 'review_group_max', 'review_group_max_lines', 'review_max_file_lines'])
  if (!Number.isFinite(conf[k]) || conf[k] < 1) die(3, `${k} inválido no risk.conf`);
for (const r of pathRules) if (!existsSync(join(root, r.file))) die(3, `review_rule aponta para arquivo inexistente: ${r.file}`);

// ---------- glob ----------
function globRe(glob, ignoreCase) {
  let re = '', i = 0;
  while (i < glob.length) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      if (glob[i + 2] === '/') { re += '(?:.*/)?'; i += 3; } else { re += '.*'; i += 2; }
    } else if (c === '*') { re += '[^/]*'; i++; }
    else if (c === '?') { re += '[^/]'; i++; }
    else if (c === '{') {
      const end = glob.indexOf('}', i);
      if (end < 0) { re += '\\{'; i++; continue; }
      re += '(?:' + glob.slice(i + 1, end).split(',').map((p) => p.replace(/[.+^$()|[\]\\]/g, '\\$&').replace(/\*/g, '[^/]*')).join('|') + ')';
      i = end + 1;
    } else { re += c.replace(/[.+^$()|[\]\\]/g, '\\$&'); i++; }
  }
  return new RegExp('^' + re + '$', ignoreCase ? 'i' : '');
}
// A lista padrão compara com caixa exata: a pasta escrita à mão `Build/` não é a saída `build/`.
// Os globs do risk.conf (review_exclude, review_include, review_rule) ignoram a caixa.
const matcher = (glob, ignoreCase = true) => {
  const re = globRe(glob, ignoreCase);
  return glob.includes('/') ? (p) => re.test(p) : (p) => re.test(posix.basename(p));
};

const DEFAULT_EXCLUDE = [
  // saídas de build e dependências
  '**/bin/**', '**/obj/**', '**/node_modules/**', '**/dist/**', '**/build/**', '**/target/**', '**/.svelte-kit/**',
  '**/.next/**', '**/coverage/**', '**/TestResults/**', '**/wwwroot/lib/**',
  // código gerado
  '*.Designer.cs', '*.g.cs', '*.g.i.cs', '*.generated.*', '*ModelSnapshot.cs', '**/Generated/**', '*.min.js', '*.min.css', '*.map',
  // snapshots de teste aprovados (Verify, Jest, Vitest)
  '**/__snapshots__/**', '*.snap', '*.verified.*', '*.received.*',
];
const LOCKFILES = ['package-lock.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lockb', 'bun.lock', 'Cargo.lock', 'packages.lock.json'];
const isExcludedDefault = ((ms) => (p) => ms.some((m) => m(p)))(DEFAULT_EXCLUDE.map((g) => matcher(g, false)));
const isUserExcluded = ((ms) => (p) => ms.some((m) => m(p)))(userExclude.map(matcher));
const isUserIncluded = ((ms) => (p) => ms.some((m) => m(p)))(userInclude.map(matcher));
const ruleMatchers = pathRules.map((r) => ({ ...r, m: matcher(r.glob) }));

// referência de stack por extensão; só vale se o bootstrap gerou o arquivo para a stack do projeto
const REF_DIR = '.claude/skills/review-rubric/reference';
const STACK_BY_EXT = [
  [/\.razor(\.cs)?$/i, ['blazor', 'dotnet']], [/\.(cs|cshtml|csproj|props|targets)$/i, ['dotnet']],
  [/\.(tsx|jsx|svelte|vue)$/i, ['web-frontend', 'node']], [/\.(ts|js|mjs|cjs|mts|cts)$/i, ['node']],
  [/\.rs$/i, ['rust']], [/\.(sh|bash)$/i, ['bash']],
];
function stackRefs(p) {
  const hit = STACK_BY_EXT.find(([re]) => re.test(p));
  return hit ? hit[1].map((s) => `${REF_DIR}/${s}.md`).filter((f) => existsSync(join(root, f))) : [];
}

// ---------- arquivos alterados ----------
let range, mb = null;
try {
  if (commit) { git('rev-parse', '--verify', '--end-of-options', `${commit}^{commit}`); range = [`${commit}^`, commit]; }
  else {
    const base = baseArg || conf.base;
    if (base.startsWith('-')) throw new Error('base inválida');
    try { mb = git('merge-base', 'HEAD', base).trim(); } catch { mb = git('rev-parse', '--verify', '--end-of-options', base).trim(); }
    range = [mb];
  }
} catch { die(3, `referência inexistente: ${commit || baseArg || conf.base}`); }

const BINARY_EXT = /\.(png|jpe?g|gif|ico|bmp|webp|avif|pdf|zip|gz|tgz|7z|rar|tar|dll|exe|so|dylib|pdb|nupkg|woff2?|ttf|otf|eot|mp[34]|mov|wasm|bin|db|sqlite)$/i;
const files = new Map();   // caminho -> {path, added, deleted, status, binary}
try {
  const status = git('diff', '--name-status', '--no-renames', '-z', ...range).split('\0').filter(Boolean);
  for (let i = 0; i + 1 < status.length; i += 2) files.set(status[i + 1], { path: status[i + 1], status: status[i][0], added: 0, deleted: 0, binary: false });
  const num = git('diff', '--numstat', '-a', '--no-renames', '-z', ...range).split('\0').filter(Boolean);
  for (const row of num) {
    const [a, d, p] = row.split('\t');
    const f = files.get(p);
    if (!f) continue;
    if (a === '-') f.binary = true; else { f.added = Number(a); f.deleted = Number(d); }
    // -a já ignora o atributo -diff; o que vale como binário é a extensão (o conteúdo não é decidido por conteúdo versionado)
    if (BINARY_EXT.test(p)) f.binary = true; else if (f.binary) { f.binary = false; f.added = f.added || 1; }
  }
  if (!commit) {
    for (const p of git('ls-files', '--others', '--exclude-standard', '-z').split('\0').filter(Boolean)) {
      let content; try { content = readFileSync(join(root, p)); } catch { continue; }
      const binary = BINARY_EXT.test(p);
      files.set(p, { path: p, status: 'A', added: binary ? 0 : content.toString('utf8').split('\n').length, deleted: 0, binary });
    }
  }
} catch (e) { die(3, `falha ao ler o diff: ${e.message.split('\n')[0]}`); }

// ---------- exclusão ----------
const included = [], excluded = [];
for (const f of [...files.values()].sort((a, b) => a.path.localeCompare(b.path))) {
  const p = f.path, name = posix.basename(p);
  let reason = null;
  if (f.status === 'D') reason = 'arquivo removido: entra só como contexto';
  else if (f.binary) reason = 'binário';
  else if (isUserExcluded(p)) reason = 'review_exclude no risk.conf';
  else if (LOCKFILES.includes(name) && !isUserIncluded(p)) reason = 'lockfile: coberto pelo scanner de dependências (§6.4)';
  else if (isExcludedDefault(p) && !isUserIncluded(p)) reason = 'gerado ou saída de build (lista padrão; review_include resgata)';
  // exclusão automática de arquivo de código sob src/, tests/ ou tools/ nunca é silenciosa: o lead decide (review_include resgata)
  if (reason) { excluded.push({ path: p, reason, attention: /^(src|tests|tools)\//.test(p) && reason.startsWith('gerado') && f.status !== 'D' }); continue; }
  const rules = [...new Set(ruleMatchers.filter((r) => r.m(p)).map((r) => r.file))];
  included.push({
    path: p, added: f.added, deleted: f.deleted, lines: f.added + f.deleted,
    stack_refs: stackRefs(p), path_rules: rules,
    oversized: f.added + f.deleted > conf.review_max_file_lines,
  });
}

// ---------- agrupamento ----------
const TEST_RE = /(^|\/)(tests?|Tests?|__tests__|specs?)\/|[._-](test|spec)s?\.[A-Za-z0-9]+$|[a-z0-9]Tests?\.cs$|(^|\/)test_[^/]*\.py$|_test\.(go|rs|py)$/;
const stem = (p) => posix.basename(p).replace(/\.(razor\.cs|[^.]+)$/i, '').replace(/\.(test|spec|tests)$/i, '');
const testSubject = (s) => s.replace(/(_?tests?|\.tests?)$/i, '').replace(/^(test_)/i, '');
const interfaceSubject = (s) => (/^I[A-Z]/.test(s) ? s.slice(1) : s);
const parent = new Map(included.map((f) => [f.path, f.path]));
const find = (x) => { while (parent.get(x) !== x) { parent.set(x, parent.get(parent.get(x))); x = parent.get(x); } return x; };
const union = (a, b) => { const ra = find(a), rb = find(b); if (ra !== rb) parent.set(ra < rb ? rb : ra, ra < rb ? ra : rb); };

let groups;
if (included.length <= conf.review_group_threshold) groups = included.length ? [included] : [];
else {
  const byDir = new Map(), byKey = new Map();
  const unionDir = (f) => { const d = posix.dirname(f.path); if (byDir.has(d)) union(byDir.get(d), f.path); else byDir.set(d, f.path); };
  // nomes genéricos (+page, index, Program, README...) existem em toda pasta e não ligam arquivo nenhum a outro
  const GENERIC = new Set(['+page', '+layout', '+server', 'index', 'program', 'readme', 'skill', 'dockerfile', 'main', 'mod', 'lib', 'app', 'setup']);
  const keyOf = (f) => { const k = interfaceSubject(testSubject(stem(f.path))).toLowerCase(); return GENERIC.has(k) ? '' : k; };
  // código de produção: mesma pasta, e interface com implementação (IPedidoService com PedidoService)
  for (const f of included.filter((x) => !TEST_RE.test(x.path))) {
    unionDir(f);
    const key = keyOf(f);
    if (key.length >= 3) { if (byKey.has(key)) union(byKey.get(key), f.path); else byKey.set(key, f.path); }
  }
  // teste vai para o grupo do arquivo testado (PedidoServiceTests, pedido.test.ts); sem o testado no diff, fica com
  // os testes da mesma pasta. Unir testes por pasta antes disso fundiria features diferentes que compartilham a pasta de testes.
  for (const f of included.filter((x) => TEST_RE.test(x.path))) {
    const key = keyOf(f);
    if (key.length >= 3 && byKey.has(key)) union(byKey.get(key), f.path); else unionDir(f);
  }
  const comps = new Map();
  for (const f of included) { const r = find(f.path); if (!comps.has(r)) comps.set(r, []); comps.get(r).push(f); }
  // corta componentes grandes demais, mantendo arquivos da mesma pasta juntos
  const chunks = [];
  for (const comp of [...comps.values()].sort((a, b) => a[0].path.localeCompare(b[0].path))) {
    comp.sort((a, b) => posix.dirname(a.path).localeCompare(posix.dirname(b.path)) || a.path.localeCompare(b.path));
    let cur = [], lines = 0;
    for (const f of comp) {
      if (cur.length && (cur.length >= conf.review_group_max || lines + f.lines > conf.review_group_max_lines)) { chunks.push(cur); cur = []; lines = 0; }
      cur.push(f); lines += f.lines;
    }
    if (cur.length) chunks.push(cur);
  }
  // junta grupos de um arquivo só que compartilham a pasta avó, para não abrir um revisor por arquivo solto
  const grand = (p) => posix.dirname(posix.dirname(p));
  const singles = new Map();
  groups = [];
  for (const c of chunks) {
    if (c.length > 1) { groups.push(c); continue; }
    const g = grand(c[0].path);
    if (!singles.has(g)) singles.set(g, []);
    singles.get(g).push(c[0]);
  }
  for (const list of singles.values()) {
    let cur = [], lines = 0;
    for (const f of list) {
      if (cur.length && (cur.length >= conf.review_group_max || lines + f.lines > conf.review_group_max_lines)) { groups.push(cur); cur = []; lines = 0; }
      cur.push(f); lines += f.lines;
    }
    if (cur.length) groups.push(cur);
  }
  groups.sort((a, b) => a[0].path.localeCompare(b[0].path));
}

const allChanged = [...files.keys()].sort();
const out = {
  range: commit ? `${commit}^..${commit}` : `${mb}..(árvore de trabalho)`,
  mode: groups.length > 1 ? 'grouped' : 'single',
  files_changed: allChanged.length, files_reviewed: included.length,
  groups: groups.map((g, i) => {
    const paths = new Set(g.map((f) => f.path));
    return { id: `g${i + 1}`, lines: g.reduce((s, f) => s + f.lines, 0), files: g, other_changed: allChanged.filter((p) => !paths.has(p)) };
  }),
  excluded,
};

if (!text) { console.log(JSON.stringify(out, null, 2)); process.exit(0); }
console.log(`${out.files_reviewed} de ${out.files_changed} arquivo(s) para revisão por LLM, em ${out.groups.length} grupo(s) (${out.mode})`);
for (const g of out.groups) {
  console.log(`\n${g.id} — ${g.files.length} arquivo(s), ${g.lines} linha(s)`);
  for (const f of g.files) {
    const refs = [...f.stack_refs.map((r) => posix.basename(r)), ...f.path_rules.map((r) => `regra: ${r}`)];
    console.log(`  ${f.path} (+${f.added}/-${f.deleted})${refs.length ? `  [${refs.join(', ')}]` : ''}${f.oversized ? '  GRANDE: revisar por partes' : ''}`);
  }
}
if (excluded.length) { console.log('\nfora da revisão por LLM:'); for (const e of excluded) console.log(`  ${e.path} — ${e.reason}${e.attention ? '  ATENÇÃO: código de src/tests/tools excluído pela lista padrão; confirmar' : ''}`); }
