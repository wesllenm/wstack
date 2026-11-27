// Repositórios que mudam junto com o projeto na mesma tarefa: chave companion do .claude/risk.conf, uma linha por
// repositório, caminho relativo à raiz do projeto (o caso comum é o irmão: companion = ../ServerControl).
// Cada companheiro tem o próprio .claude/risk.conf, que vale para ele: classify-diff.sh --companions classifica cada um
// com a base dele, o verify-on-stop roda os verify_* de cada um, o checkpoint-tests usa o risk.conf do repositório do
// commit. Um caminho só vale se for a raiz de um repositório git, diferente da raiz do projeto, com .claude/risk.conf;
// o resto é ignorado, e o SessionStart avisa.
// Uso: node companions.mjs             imprime o caminho real de cada companheiro válido, um por linha
//      node companions.mjs --raw       "<caminho do risk.conf><TAB><caminho real>" por companheiro válido
//      node companions.mjs --session   avisos de companheiro ignorado e a lista dos válidos
import { existsSync, realpathSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { confValues, projectDir } from './risk-conf.mjs';
import { GIT_ENV } from './git-repo.mjs';

const PATH = /^[A-Za-z0-9._/-]+$/;
const real = (p) => { try { return realpathSync(p); } catch { return ''; } };
const toplevel = (p) => {
  try { return real(execFileSync('git', ['-C', p, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', env: { ...process.env, ...GIT_ENV }, stdio: ['ignore', 'pipe', 'ignore'] }).trim()); }
  catch { return ''; }
};

// { valid: [{ raw, path }], warnings: [texto] }
export function companions(root = projectDir()) {
  const valid = [], warnings = [];
  const self = real(root);
  if (!self) return { valid, warnings };
  for (const raw of confValues('companion')) {
    const v = raw.replace(/\/+$/, '');
    if (!PATH.test(v) || v.startsWith('/') || v.startsWith('-')) { warnings.push(`companion = ${raw} ignorado: caminho relativo à raiz do projeto, só letras, números, ., _, / e -.`); continue; }
    const p = real(resolve(self, v));
    if (!p) { warnings.push(`companion = ${raw} ignorado: a pasta não existe.`); continue; }
    if (p === self) { warnings.push(`companion = ${raw} ignorado: é o próprio projeto.`); continue; }
    if (toplevel(p) !== p) { warnings.push(`companion = ${raw} ignorado: não é a raiz de um repositório git.`); continue; }
    if (!existsSync(join(p, '.claude', 'risk.conf'))) { warnings.push(`companion = ${raw} ignorado: o repositório não tem .claude/risk.conf (rode o /wstack:bootstrap nele).`); continue; }
    if (!valid.some((c) => c.path === p)) valid.push({ raw: v, path: p });
  }
  return { valid, warnings };
}

const me = (() => { try { return realpathSync(fileURLToPath(import.meta.url)); } catch { return ''; } })();
const argv1 = (() => { try { return process.argv[1] ? realpathSync(process.argv[1]) : ''; } catch { return ''; } })();
if (me && me === argv1) {
  const { valid, warnings } = companions();
  if (process.argv[2] === '--session') {
    const lines = warnings.map((w) => `AVISO: ${w}`);
    if (valid.length) lines.push(`Repositórios companheiros (risk.conf, companion): ${valid.map((c) => c.raw).join(', ')}. Cada um com o próprio risk.conf; o risco da tarefa é o do classify-diff.sh --companions, um commit por repositório, e o Stop verifica todos.`);
    if (lines.length) process.stdout.write(lines.join('\n') + '\n');
  } else {
    const raw = process.argv[2] === '--raw';
    process.stdout.write(valid.map((c) => (raw ? `${c.raw}\t${c.path}` : c.path)).join('\n') + (valid.length ? '\n' : ''));
  }
}
