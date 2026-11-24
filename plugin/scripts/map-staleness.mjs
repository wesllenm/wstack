#!/usr/bin/env node
// Avisa no início da sessão quando o mapa de features de uma skill verify-<app> ficou para trás do código (§12.24).
// Para cada .claude/skills/verify-*/features/, procura commits depois da última mudança no mapa que tocaram a
// superfície do usuário (feature_surface no risk.conf: rotas, endpoints, telas, comandos). Hook SessionStart:
// a saída vai para o contexto; nunca falha a sessão. Sem nenhuma skill verify-*, não diz nada.
// Uso: node map-staleness.mjs [--verbose]   (--verbose também diz quando o mapa está em dia)
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, posix } from 'node:path';

const verbose = process.argv.includes('--verbose');
const git = (...a) => execFileSync('git', ['-c', 'core.quotePath=false', ...a],
  { encoding: 'utf8', maxBuffer: 1 << 26, stdio: ['ignore', 'pipe', 'ignore'] });
try {
  process.chdir(process.env.CLAUDE_PROJECT_DIR || '.');
  process.chdir(git('rev-parse', '--show-toplevel').trim());
} catch { process.exit(0); }

const surface = [];
const maxCommits = 500;
if (existsSync('.claude/risk.conf')) {
  for (const raw of readFileSync('.claude/risk.conf', 'utf8').split(/\r?\n/)) {
    const m = /^\s*([a-z_]+)\s*=\s*(.*?)\s*$/.exec(raw);
    if (!m || raw.trim().startsWith('#')) continue;
    if (m[1] === 'feature_surface') surface.push(m[2]);
  }
}

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
// Sem feature_surface, qualquer código fora de testes, docs e .claude conta: aviso mais largo, dito na mensagem.
const CODE = /\.(cs|razor|cshtml|ts|tsx|js|jsx|mjs|svelte|vue|rs|py|go|java|kt)$/i;
const NOT_SURFACE = [/(^|\/)(tests?|__tests__|spec)\//i, /\.(test|spec)\.[a-z]+$/i, /Tests?\.cs$/, /^docs\//, /^\.claude\//];
const inSurface = surface.length
  ? ((ms) => (p) => ms.some((m) => m(p)))(surface.map(matcher))
  : (p) => CODE.test(p) && !NOT_SURFACE.some((r) => r.test(p));

const skillsDir = '.claude/skills';
let skills = [];
try { skills = readdirSync(skillsDir).filter((d) => d.startsWith('verify-') && existsSync(join(skillsDir, d, 'features'))); } catch { process.exit(0); }

const out = [];
for (const skill of skills) {
  const dir = `${skillsDir}/${skill}/features`;
  let last;
  try { last = git('log', '-1', '--format=%H%x09%cs', '--', dir).trim(); } catch { continue; }
  if (!last) { out.push(`Mapa de features de ${skill} ainda não commitado; prove a skill e commite o mapa (§12.24).`); continue; }
  const [sha, date] = last.split('\t');
  let log;
  try { log = git('log', `--max-count=${maxCommits}`, '--format=@%H', '--name-only', `${sha}..HEAD`); } catch { continue; }
  const files = new Set(); let commits = 0, hit = false;
  for (const l of log.split('\n')) {
    if (l.startsWith('@')) { if (hit) commits++; hit = false; continue; }
    if (l && inSurface(l)) { files.add(l); hit = true; }
  }
  if (hit) commits++;
  if (!files.size) { if (verbose) out.push(`Mapa de features de ${skill} em dia (última atualização ${date}).`); continue; }
  const list = [...files].slice(0, 5).join(', ') + (files.size > 5 ? ` e mais ${files.size - 5}` : '');
  out.push(`Mapa de features de ${skill} pode estar desatualizado: ${commits} commit(s) desde ${date} tocaram a superfície`
    + `${surface.length ? '' : ' (feature_surface não configurado no risk.conf; contando todo código fora de testes)'}: ${list}. `
    + `Antes de confiar no mapa numa condução, rodar a Manutenção da ${skill} (§12.24) para as features desses arquivos.`);
}
if (out.length) console.log(out.join('\n'));
process.exit(0);
