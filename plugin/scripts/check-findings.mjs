#!/usr/bin/env node
// Ancora cada candidato de revisão no código antes do review-verifier.
// Cada candidato traz `local: <arquivo:linha>` e `trecho:` com a linha (ou as linhas consecutivas) exatas do código
// naquele local. Uma janela deslizante procura o trecho no arquivo, ignorando diferenças de espaço:
//   ancorado    trecho encontrado a até --tolerance linhas do local citado
//   realocado   trecho encontrado em outro ponto do arquivo; o local é corrigido
//   descartado  arquivo inexistente, candidato sem trecho, ou trecho que não existe no arquivo (achado alucinado)
// Também marca local fora das linhas alteradas pelo diff com `preexistente: não`, contradição que o verificador decide.
// Prova por execução: candidato bloqueante ou importante de categoria de comportamento (todas menos reuse, simplicity
// e scope), e o candidato sem severidade ou com severidade fora da lista, precisa de `prova: <comando>` e de
// `esperado: <saída esperada da falha>`. Sem elas, o candidato fica com a severidade que trouxe (o script não a muda) e
// ganha `situação: a confirmar`: o verificador não o confirma sem executar uma prova.
// Status da lente: cada arquivo é a resposta de uma lente (ou de um grupo do despacho) e termina com uma linha
// `status: sem achados`, `status: achados` ou `status: falhou: <motivo>` (o arquivo inteiro `sem achados` ou
// `falhou: <motivo>`, saída do interrogate.mjs, também vale). Sem status, com status que contradiz o conteúdo, ou com
// falhou, a lente é lacuna: nunca conta como "sem achados", e os candidatos que ela trouxe seguem para o verificador.
// Uso: node check-findings.mjs [<lente.txt>...] [--rev <ref>] [--base <ref>] [--tolerance 3] [--json]
//   sem arquivo, lê uma lente da entrada padrão; --rev lê o código de um commit em vez da árvore de trabalho.
// Saída: os candidatos mantidos, no formato da review-rubric, com o local corrigido e as linhas `ancoragem:` e
// `situação:`; depois deles, uma linha `lacuna: <lente> — <motivo>` por lente que falhou ("sem achados" só sai sem
// candidato e sem lacuna). O resumo vai para stderr.
// Código: 0 ok, 2 uso errado, 3 arquivo ilegível, 4 alguma lente é lacuna (a saída continua válida).
import { readFileSync, existsSync, lstatSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, basename } from 'node:path';
import { parseDiff } from './diff-parse.mjs';

function die(code, msg) { console.error(`check-findings: ${msg}`); process.exit(code); }
const opt = { files: [], rev: null, base: null, tol: 3, json: false };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i], v = () => { if (i + 1 >= argv.length) die(2, `${a} sem valor`); return argv[++i]; };
  if (a === '--rev') opt.rev = v();
  else if (a === '--base') opt.base = v();
  else if (a === '--tolerance') { opt.tol = Number(v()); if (!Number.isInteger(opt.tol) || opt.tol < 0) die(2, '--tolerance inválida'); }
  else if (a === '--json') opt.json = true;
  else if (a.startsWith('--')) die(2, `opção desconhecida: ${a}`);
  else opt.files.push(a);
}

// Referência vinda de argumento ou do risk.conf nunca começa com "-" (injeção de opção no git, como --output=<arquivo>).
for (const [name, val] of [['--rev', opt.rev], ['--base', opt.base]])
  if (val !== null && (val.startsWith('-') || /[\0\r\n]/.test(val))) die(2, `${name} inválido`);

const sources = opt.files.length ? opt.files : [null];
const inputs = sources.map((f) => {
  try { return { name: f === null ? 'entrada padrão' : basename(f), text: readFileSync(f ?? 0, 'utf8') }; }
  catch (e) { return die(3, `não foi possível ler ${f ?? 'a entrada padrão'}: ${e.code ?? e.message}`); }
});

// ---------- leitura dos candidatos e do status de cada lente ----------
// Itens começam em "- id:"; campos em "  chave: valor"; o trecho pode continuar em linhas com recuo maior.
const RESERVED = new Set(['ancoragem', 'situação', 'situacao']); // chaves do script: o candidato não as forja
const NONE = /^(?:status:\s*)?sem achados\.?$/i;
const items = [];
const lacunas = []; // { lente, motivo }
for (const { name, text } of inputs) {
  const lines = text.split(/\r?\n/);
  // linhas `aprendizado:` (fato para docs/gotchas/) podem vir depois do status
  while (lines.length && (!lines[lines.length - 1].trim() || /^aprendizado:/i.test(lines[lines.length - 1].trim()))) lines.pop();
  const whole = lines.join('\n').trim();
  const last = (lines[lines.length - 1] ?? '').trim();
  const st = /^status:\s*(sem achados|achados|falhou)\s*(?::\s*(.*))?$/i.exec(last);
  let status, motivo = '';
  if (NONE.test(whole)) status = 'sem achados';
  else if (/^falhou:/i.test(whole)) { status = 'falhou'; motivo = whole.split('\n')[0].replace(/^falhou:\s*/i, ''); }
  else if (st) { status = st[1].toLowerCase(); motivo = st[2] ?? ''; lines.pop(); }
  else status = null;
  let cur = null, lastKey = null, found = 0;
  for (const raw of lines) {
    const start = /^\s*-\s+id:\s*(.*)$/.exec(raw);
    if (start) { cur = { fields: [['id', start[1].trim()]], trecho: [], lens: name }; items.push(cur); found++; lastKey = 'id'; continue; }
    if (!cur) continue;
    const kv = /^\s{1,3}([\p{L} ]+):\s?(.*)$/iu.exec(raw);
    if (kv && !/^\s{4,}/.test(raw)) {
      const key = kv[1].trim().toLowerCase();
      lastKey = key;
      if (key === 'trecho') { if (kv[2].trim() && kv[2].trim() !== '|') cur.trecho.push(kv[2]); }
      else if (!RESERVED.has(key)) cur.fields.push([key, kv[2]]);
      continue;
    }
    if (lastKey === 'trecho' && /^\s{4,}\S/.test(raw)) cur.trecho.push(raw.replace(/^\s{4}/, ''));
  }
  const clean = (s) => s.replace(/[\x00-\x1f\x7f]/g, ' ').trim().slice(0, 200);
  if (status === null) lacunas.push({ lente: name, motivo: 'sem a linha de status no fim (resposta truncada, fora do formato ou sem resposta)' });
  else if (status === 'falhou') lacunas.push({ lente: name, motivo: `falhou: ${clean(motivo) || 'sem motivo'}` });
  else if (status === 'achados' && !found) lacunas.push({ lente: name, motivo: 'status achados sem candidato no formato da review-rubric' });
  else if (status === 'sem achados' && found) lacunas.push({ lente: name, motivo: 'status sem achados com candidatos na resposta' });
}

// ---------- código e diff ----------
let root = process.cwd();
const git = (...a) => execFileSync('git', ['-c', 'core.quotePath=false', ...a], { encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'pipe'] });
let inGit = true;
try { root = git('rev-parse', '--show-toplevel').trim(); } catch { inGit = false; }
// Resolve --rev para o SHA do commit (e recusa o que não é commit) antes de qualquer uso.
if (opt.rev) {
  try { opt.rev = git('rev-parse', '--verify', '--end-of-options', `${opt.rev}^{commit}`).trim(); }
  catch { die(2, '--rev não é um commit'); }
}
const MAX_FILE_BYTES = 5 * 1024 * 1024, MAX_TRECHO_LINES = 50;
// Só caminho relativo ao repositório, sem "..", "\", ":", segmento vazio nem "-" inicial (o local vem do candidato, que pode ter lido texto hostil).
const safePath = (p) => !!p && !p.startsWith('/') && !/[\\:\0]/.test(p) && p.split('/').every((s) => s && s !== '.' && s !== '..');
const cache = new Map();
function fileLines(path) {
  if (cache.has(path)) return cache.get(path);
  let text = null;
  if (!safePath(path)) text = null;
  else if (opt.rev) {
    try { text = git('show', '--end-of-options', `${opt.rev}:${path}`); } catch { text = null; }
    if (text !== null && Buffer.byteLength(text) > MAX_FILE_BYTES) text = null;
  } else {
    // pasta, link simbólico, arquivo grande ou ilegível viram "arquivo não existe", nunca abortam o lote
    try {
      const full = join(root, path), st = lstatSync(full);
      if (st.isFile() && !st.isSymbolicLink() && st.size <= MAX_FILE_BYTES) text = readFileSync(full, 'utf8');
    } catch { text = null; }
  }
  const lines = text === null ? null : text.split(/\r?\n/);
  cache.set(path, lines);
  return lines;
}
const changed = new Map();
const removedBy = new Map(); // arquivo -> linhas removidas pelo diff, com a posição na versão nova
let diffOk = false;
if (inGit) {
  try {
    let base = opt.base;
    if (!base) {
      const conf = join(root, '.claude', 'risk.conf');
      const m = existsSync(conf) && /^\s*base\s*=\s*(\S+)/m.exec(readFileSync(conf, 'utf8'));
      base = m ? m[1] : 'main';
    }
    if (base.startsWith('-')) throw new Error('base inválida');
    const range = opt.rev ? [`${opt.rev}^`, opt.rev] : [(() => { try { return git('merge-base', 'HEAD', base).trim(); } catch { return git('rev-parse', '--verify', '--end-of-options', base).trim(); } })()];
    // trecho que só remove linhas também é diff: a linha antes e a depois do corte entram em `changed`, e as linhas
    // removidas ficam em `removedBy` para ancorar o achado sobre o que saiu ("removeu a checagem de nulo")
    for (const [p, d] of parseDiff(git('diff', '-U0', '--no-color', '--no-ext-diff', '--src-prefix=a/', '--dst-prefix=b/', ...range))) {
      if (d.ranges.length) changed.set(p, [...(changed.get(p) ?? []), ...d.ranges]);
      if (d.removed.length) removedBy.set(p, d.removed);
    }
    if (!opt.rev) for (const p of git('ls-files', '--others', '--exclude-standard', '-z').split('\0')) if (p) changed.set(p, [[1, Infinity]]);
    diffOk = true;
  } catch { diffOk = false; }
}
const inDiff = (p, a, b) => (changed.get(p) || []).some(([x, y]) => x <= b && a <= y);

// ---------- ancoragem ----------
const norm = (s) => s.replace(/\s+/g, ' ').trim();
// Casa o trecho contra as linhas NÃO vazias do arquivo (o trecho também perde as vazias), devolvendo o número real
// da primeira linha de cada ocorrência.
function findAll(lines, needle) {
  const idx = [];
  lines.forEach((l, i) => { if (norm(l)) idx.push(i); });
  const hits = [];
  for (let k = 0; k + needle.length <= idx.length; k++) {
    let ok = true;
    for (let j = 0; j < needle.length && ok; j++) ok = norm(lines[idx[k + j]]) === needle[j];
    if (ok) hits.push(idx[k] + 1);
  }
  return hits;
}
const results = [];
for (const it of items) {
  const get = (k) => it.fields.find(([key]) => key === k)?.[1]?.trim();
  const id = get('id'), local = get('local') ?? '';
  const m = /^(.+?):(\d+)(?:-(\d+))?$/.exec(local);
  const r = { id, local, status: null, detail: '', lens: it.lens };
  results.push(r);
  if (!m) { r.status = 'descartado'; r.detail = 'local sem o formato arquivo:linha'; continue; }
  const [, path, l1] = m, line = Number(l1);
  const needle = it.trecho.map(norm).filter(Boolean);
  if (!needle.length) { r.status = 'descartado'; r.detail = 'candidato sem trecho'; continue; }
  if (needle.length > MAX_TRECHO_LINES) { r.status = 'descartado'; r.detail = `trecho acima de ${MAX_TRECHO_LINES} linhas`; continue; }
  const lines = safePath(path) ? fileLines(path) : null;
  const hits = lines ? findAll(lines, needle) : [];
  // o trecho pode ser código que o diff removeu (o achado é sobre o que saiu): ancora na posição do corte
  const removed = safePath(path) ? (removedBy.get(path) ?? []) : [];
  const removedHits = hits.length ? [] : findAll(removed.map((x) => x.text), needle).map((k) => removed[k - 1].at);
  if (!lines && !removedHits.length) { r.status = 'descartado'; r.detail = `arquivo não existe${opt.rev ? ` em ${opt.rev}` : ''}: ${path}`; continue; }
  if (!hits.length && !removedHits.length) { r.status = 'descartado'; r.detail = `trecho não encontrado em ${path}`; continue; }
  let best, end, newLocal;
  if (hits.length) {
    best = hits.reduce((a, b) => (Math.abs(b - line) < Math.abs(a - line) ? b : a));
    end = best + needle.length - 1;
    newLocal = needle.length > 1 ? `${path}:${best}-${end}` : `${path}:${best}`;
    if (Math.abs(best - line) <= opt.tol) { r.status = 'ancorado'; r.detail = hits.length > 1 ? `${hits.length} ocorrências; usada a mais próxima` : ''; }
    else { r.status = 'realocado'; r.detail = `de ${local} para ${newLocal}`; }
    r.in_diff = diffOk ? inDiff(path, best, end) : null;
  } else {
    best = removedHits.reduce((a, b) => (Math.abs(b - line) < Math.abs(a - line) ? b : a));
    end = best;
    newLocal = `${path}:${best}`;
    r.status = 'removido';
    r.detail = `trecho removido pelo diff; o local é o ponto do corte${newLocal !== local ? ` (era ${local})` : ''}`;
    r.in_diff = true;
  }
  r.local = newLocal;
  if (r.in_diff === false && /^n[ãa]o$/i.test(get('preexistente') ?? '')) r.warning = 'local fora das linhas alteradas com preexistente: não';
  // prova por execução: exigida em bloqueante e importante, salvo reuse, simplicity e scope (a evidência ali é o
  // outro trecho de código, não uma execução). Severidade ausente ou fora da lista conta como bloqueante (falha
  // fechada: grafia errada não dispensa a prova). A saída esperada vem no campo `esperado:` (ou, na forma curta, depois
  // de " → " em `prova:`; "->" não separa, porque aparece dentro de comando). Sem prova ou sem saída esperada, o
  // candidato fica com a severidade dele e ganha `situação: a confirmar`; o script não muda a severidade.
  const rawSev = (get('severidade') ?? '').trim().toLowerCase(), cat = (get('categoria') ?? '').trim().toLowerCase();
  const sevOk = /^(bloqueante|importante|nit)$/.test(rawSev);
  const prova = (get('prova') ?? '').trim(), esperado = (get('esperado') ?? '').trim();
  // com esperado: preenchido, a prova inteira é o comando (ele pode conter " → "); a forma curta só vale sem esperado:
  const arrow = esperado ? -1 : prova.lastIndexOf(' → ');
  const cmd = arrow >= 0 ? prova.slice(0, arrow).trim() : prova;
  const expected = esperado || (arrow >= 0 ? prova.slice(arrow + 3).trim() : '');
  const needs = (!sevOk || rawSev !== 'nit') && !/^(reuse|simplicity|scope)$/.test(cat);
  const complete = !!cmd && !!expected;
  r.proof_command = cmd || null;
  r.proof = !needs ? 'dispensada' : complete ? 'presente' : prova ? 'incompleta' : 'ausente';
  const why = [];
  if (!sevOk) why.push(`severidade ${rawSev ? `fora da lista ("${rawSev.slice(0, 40)}")` : 'ausente'}, tratada como bloqueante`);
  if (needs && !prova) why.push('sem prova:');
  else if (needs && !cmd) why.push('prova: sem o comando');
  else if (needs && !expected) why.push('prova: sem a saída esperada (campo esperado:)');
  if (needs && !complete) r.situacao = `a confirmar (${why.join('; ')}; o verificador não confirma sem executar uma prova)`;
  else if (!sevOk) r.situacao = `severidade ${rawSev ? 'fora da lista' : 'ausente'}: o verificador dá a severidade final (bloqueante | importante | nit)`;
  r.lens = it.lens;
  it.newLocal = newLocal;
  it.result = r;
}

const kept = items.filter((it) => it.result && it.result.status !== 'descartado');
const counts = { ancorado: 0, realocado: 0, removido: 0, descartado: 0 };
for (const r of results) counts[r.status]++;
const pending = results.filter((r) => r.situacao?.startsWith('a confirmar') && r.status !== 'descartado').length;
const summary = `check-findings: ${items.length} candidato(s): ${counts.ancorado} ancorado(s), ${counts.realocado} realocado(s), ${counts.removido} em linha removida, ${counts.descartado} descartado(s), ${pending} a confirmar sem prova${lacunas.length ? `; ${lacunas.length} lacuna(s): ${lacunas.map((l) => l.lente).join(', ')}` : ''}${diffOk ? '' : '; diff indisponível, sem checagem de linhas alteradas'}`;
// lente que trouxe candidatos e teve todos descartados: o resultado (nenhum achado) está certo, mas a lente só produziu
// lixo, e isso é sinal para a calibração; nunca some num "sem achados" calado
const byLens = new Map();
for (const r of results) { const e = byLens.get(r.lens) ?? { total: 0, dropped: 0, why: new Map() }; e.total++; if (r.status === 'descartado') { e.dropped++; const k = r.detail.replace(/ em .*$|: .*$/, ''); e.why.set(k, (e.why.get(k) ?? 0) + 1); } byLens.set(r.lens, e); }
const allDropped = [...byLens].filter(([, e]) => e.total && e.dropped === e.total)
  .map(([lente, e]) => ({ lente, descartados: e.dropped, motivos: [...e.why].map(([k, n]) => `${n} ${k}`).join(', ') }));
const code = lacunas.length ? 4 : 0;

if (opt.json) { console.log(JSON.stringify({ total: items.length, counts, a_confirmar: pending, lacunas, lentes_so_descartes: allDropped, diff_checked: diffOk, results }, null, 2)); console.error(summary); process.exit(code); }

const out = [];
for (const it of kept) {
  const r = it.result;
  it.fields.forEach(([k, v], idx) => out.push(idx === 0 ? `- id: ${v}` : `  ${k}: ${k === 'local' ? it.newLocal : v}`));
  out.push('  trecho: |');
  for (const t of it.trecho) out.push(`    ${t}`);
  out.push(`  ancoragem: ${r.status}${r.detail ? ` (${r.detail})` : ''}${r.warning ? `; atenção: ${r.warning}` : ''}`);
  if (r.situacao) out.push(`  situação: ${r.situacao}`);
}
for (const l of lacunas) out.push(`lacuna: ${l.lente} — ${l.motivo}`);
for (const d of allDropped) out.push(`descartes: ${d.lente} — ${d.descartados} de ${d.descartados} candidato(s) descartado(s) (${d.motivos}); a lente não trouxe nenhum achado ancorado: registrar na calibração`);
// "sem achados" só quando nenhuma lente falhou nem trouxe só descartes: lacuna nunca conta como aprovação
console.log(out.length ? out.join('\n') : 'sem achados');
for (const r of results.filter((x) => x.status === 'descartado')) console.error(`  descartado ${r.id}: ${r.detail}`);
console.error(summary);
process.exit(code);
