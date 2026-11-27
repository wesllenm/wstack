#!/usr/bin/env node
// Revisão humana proporcional ao risco no PR, rodada pela Action merge-por-risco.yml a partir da base.
// O lead rotula o PR com o nível do classify-diff (risco:trivial, risco:simples, risco:complexa, risco:critica);
// este script decide, sem confiar só no rótulo:
//   - auto-merge (merge quando os checks ficarem verdes) só para risco:trivial que mude apenas documentação;
//   - aprovações exigidas: 0 nesse caso, REVISORES_CRITICA em risco:critica, REVISORES_PADRAO no resto;
//   - aprovação conta a última revisão de cada pessoa, sem o autor.
// Uso: node pr-risk-gate.mjs --files <arquivos.txt> --pr <pr.json> --reviews <revisoes.jsonl>
//   arquivos.txt: um caminho por linha; pr.json: {"author","labels":[...]}; revisoes.jsonl: {"user","state","submitted_at"} por linha
//   ambiente: REVISORES_PADRAO (1), REVISORES_CRITICA (2), DOCS_GLOBS (separados por vírgula)
// Saída: JSON com o veredito. Código: 0 aprovações suficientes, 1 faltam aprovações, 2 entrada inválida.
import { readFileSync } from 'node:fs';
import { posix } from 'node:path';
import { docPaths } from '../hooks/doc-paths.mjs';

function die(msg) { console.error(`pr-risk-gate: ${msg}`); process.exit(2); }
const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) {
  if (!['--files', '--pr', '--reviews'].includes(argv[i]) || i + 1 >= argv.length) die(`argumento inválido: ${argv[i] ?? ''}`);
  args[argv[i].slice(2)] = argv[i + 1];
}
if (!args.files || !args.pr || !args.reviews) die('uso: --files <arquivos.txt> --pr <pr.json> --reviews <revisoes.jsonl>');

const read = (p) => { try { return readFileSync(p, 'utf8'); } catch (e) { die(`não foi possível ler ${p}: ${e.code ?? e.message}`); } };
const files = read(args.files).split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
let pr;
try { pr = JSON.parse(read(args.pr)); } catch { die('pr.json inválido'); }
const reviews = [];
for (const line of read(args.reviews).split(/\r?\n/)) {
  if (!line.trim()) continue;
  try { reviews.push(JSON.parse(line)); } catch { die('revisoes.jsonl com linha inválida'); }
}
const int = (name, def) => {
  const v = process.env[name];
  if (v === undefined || v === '') return def;
  if (!/^\d+$/.test(v)) die(`${name} precisa ser inteiro não negativo`);
  return Number(v);
};
const padrao = int('REVISORES_PADRAO', 1), critica = int('REVISORES_CRITICA', 2);

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
const docs = (process.env.DOCS_GLOBS || 'docs/**,*.md,*.txt,*.png,*.jpg,*.svg').split(',').map((s) => s.trim()).filter(Boolean).map(matcher);
// instruções e configuração de agente nunca são "só documentação": mudam o comportamento do workflow
// Também nunca são documentação: o que os agentes carregam como instrução em toda sessão (o núcleo dos gotchas,
// docs/gotchas.md ou o doc_gotchas do risk.conf da base, é importado pelo CLAUDE.md), a constitution verificada por
// teste, os ADRs e o corpus de avaliação.
const NEVER_DOCS = ['CLAUDE.md', 'AGENTS.md', 'REVIEW.md', '.claude/**', '.github/**', ...new Set(['docs/gotchas.md', docPaths().gotchas]),
  'docs/constitution*', 'docs/adr/**', 'evals/**', 'ci/**', 'schemas/**', 'profiles/**'].map(matcher);
const isDoc = (f) => !NEVER_DOCS.some((m) => m(f)) && docs.some((m) => m(f));

const labels = (pr.labels ?? []).map(String);
const levels = labels.map((l) => /^risco:(trivial|simples|complexa|critica)$/i.exec(l)?.[1]?.toLowerCase()).filter(Boolean);
const order = ['trivial', 'simples', 'complexa', 'critica'];
const labeled = levels.length ? levels.sort((a, b) => order.indexOf(b) - order.indexOf(a))[0] : 'nao-classificado';
// O rótulo vem de quem abriu o PR (o próprio agente, pela API de rótulos do `gh api`), então não é a única fonte: PR sem rótulo
// vale critica (falha fechada, como o classify-diff.sh), e arquivo que muda o comportamento dos agentes ou do
// workflow (NEVER_DOCS) sobe o nível para critica qualquer que seja o rótulo.
const touchesNeverDocs = files.some((f) => NEVER_DOCS.some((m) => m(f)));
const nivel = labeled === 'nao-classificado' || touchesNeverDocs ? 'critica' : labeled;
const docsOnly = files.length > 0 && files.every(isDoc);
const autoMerge = nivel === 'trivial' && docsOnly;

const latest = new Map();
for (const r of reviews) {
  if (!r?.user || r.user === pr.author) continue;
  const st = String(r.state ?? '').toUpperCase();
  if (st === 'COMMENTED' || st === 'PENDING') continue; // comentário não muda a posição da pessoa
  const prev = latest.get(r.user);
  if (!prev || String(r.submitted_at ?? '') >= String(prev.submitted_at ?? '')) latest.set(r.user, { ...r, state: st });
}
const approvers = [...latest.values()].filter((r) => r.state === 'APPROVED').map((r) => r.user).sort();
const changes = [...latest.values()].filter((r) => r.state === 'CHANGES_REQUESTED').map((r) => r.user).sort();
const required = autoMerge ? 0 : nivel === 'critica' ? critica : padrao;

const reasons = [];
if (labeled === 'nao-classificado') reasons.push('PR sem rótulo risco:<nível>; tratado como critica');
if (touchesNeverDocs && labeled !== 'critica') reasons.push('o PR toca arquivo que muda o comportamento dos agentes ou do workflow; tratado como critica');
if (levels.length > 1) reasons.push(`mais de um rótulo de risco; vale o maior (${labeled})`);
if (nivel === 'trivial' && !docsOnly) reasons.push('risco:trivial com arquivo que não é documentação: sem auto-merge');
if (changes.length) reasons.push(`mudanças pedidas por: ${changes.join(', ')}`);
const ok = approvers.length >= required && changes.length === 0;
if (!ok && approvers.length < required) reasons.push(`faltam ${required - approvers.length} aprovação(ões)`);

console.log(JSON.stringify({ nivel, docs_only: docsOnly, auto_merge: autoMerge && changes.length === 0,
  required_approvals: required, approvals: approvers, ok, reasons }, null, 2));
process.exit(ok ? 0 : 1);
