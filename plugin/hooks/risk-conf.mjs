// Leitor do .claude/risk.conf do projeto, para o que cada projeto declara e os hooks de git e de comando usam:
// activity_branch, default_branch, protected, allow_module. Os hooks ficam no plugin, então o arquivo nunca vem da pasta
// deles: o projeto é $CLAUDE_PROJECT_DIR (que o Claude Code passa aos hooks) e, sem ela, a raiz git da pasta atual (os
// scripts que o agente roda pelo Bash não recebem a variável, e rodam no repositório que tratam).
// Formato do arquivo (o mesmo do review-dispatch.mjs): "chave = valor" por linha, "#" no começo da linha comenta, CRLF tolerado.
// Arquivo ausente ou ilegível, ou projeto indeterminado, devolve lista vazia e deixa o motivo em confError(): lista vazia
// restringe activity_branch, default_branch e allow_module, mas afrouxaria protected, então o protected-paths.mjs trata o
// erro como falha fechada.
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GIT_ENV, left } from './git-repo.mjs';
import { validValues } from './conf-exception.mjs';

export function projectDir() {
  if (process.env.CLAUDE_PROJECT_DIR) return process.env.CLAUDE_PROJECT_DIR;
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

let parsed;
let error = '';
function read() {
  if (parsed) return parsed;
  parsed = new Map();
  const project = projectDir();
  if (!project) { error = 'projeto indeterminado (sem CLAUDE_PROJECT_DIR e fora de repositório git)'; return parsed; }
  let text = '';
  try { text = readFileSync(join(project, '.claude', 'risk.conf'), 'utf8'); } catch (e) { error = e.code ?? e.message; return parsed; }
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const m = /^([a-z_]+)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    parsed.set(m[1], [...(parsed.get(m[1]) ?? []), m[2].trim()]);
  }
  return parsed;
}

// Valores da chave, na ordem do arquivo; [] se ela não aparece ou o arquivo não pôde ser lido.
export const confValues = (key) => read().get(key) ?? [];
// módulos de forma fechada que o projeto declarou (allow_module) com validade e motivo: a regra única que o path-guard
// (não pede nas formas) e o dotnet-allow (devolve allow) leem, para os dois não divergirem
export const allowModules = () => validValues(confValues('allow_module'));
// Motivo de o .claude/risk.conf não ter sido lido (ex.: ENOENT, EISDIR); '' se foi lido.
export const confError = () => (read(), error);

// git do projeto no prazo comum dos hooks (git-repo.mjs) e sem objetos de troca; lança erro se falhar ou esgotar o prazo
const OPTS = { encoding: 'utf8', env: GIT_ENV, maxBuffer: 256 * 1024 * 1024 };
const gitIn = (dir, ...a) => execFileSync('git', ['-C', dir, ...a], { ...OPTS, stdio: ['ignore', 'pipe', 'ignore'], timeout: left() }).trim();

// Projeto que não adotou o wstack (sem /wstack:bootstrap): .claude/risk.conf ausente na árvore E em todo commit que o
// repositório aponta (HEAD e o reflog dele, branches locais, refs remotas e tags), lidos sem objetos de troca. Nele os hooks de workflow ficam inertes e as travas de
// segurança seguem só com o núcleo fixo (docs/decisions.md, plugin inerte sem risk.conf). Só o HEAD não basta: um
// checkout de commit anterior ao bootstrap o tira da árvore e do HEAD sem citar a trava. Dúvida (git sem resposta, ref
// que não resolve) conta como adotado: afrouxar exige certeza.
let absent;
export function confAbsent() {
  if (absent !== undefined) return absent;
  read();
  absent = error === 'ENOENT' && !inAnyRef(projectDir());
  return absent;
}
// true se o arquivo está em algum commit apontado pelo repositório, ou se não deu para saber
function inAnyRef(project) {
  try {
    // o for-each-ref pula ref quebrada com um aviso no stderr: qualquer aviso é dúvida
    const refs = spawnSync('git', ['-C', project, 'for-each-ref', '--format=%(objectname)', 'refs/heads', 'refs/remotes', 'refs/tags'],
      { ...OPTS, timeout: left() });
    if (refs.status !== 0 || refs.stderr.trim()) return true;
    const set = new Set(refs.stdout.split('\n').filter(Boolean));
    try { set.add(gitIn(project, 'rev-parse', '--verify', '-q', 'HEAD')); } catch (e) { if (e.status !== 1) return true; }
    // HEAD que não resolve (status 1): repositório sem commit, branch órfã, ou ref quebrada (que o for-each-ref já acusaria).
    // Entram também os commits de todos os reflogs, mesmo sem HEAD (branch órfã): apagar branch e ref de rastreio
    // (git branch -d, -d -r) não cita a trava, e o commit do bootstrap continua no reflog. Sem reflog, sai vazio.
    for (const h of gitIn(project, 'rev-list', '--no-walk', '--ignore-missing', '--reflog', 'HEAD').split('\n')) if (h) set.add(h);
    set.delete('');
    const tips = [...set];
    if (!tips.length) return false;
    const out = execFileSync('git', ['-C', project, 'cat-file', '--batch-check'], {
      ...OPTS, input: tips.map((t) => `${t}:.claude/risk.conf\n`).join(''), stdio: ['pipe', 'pipe', 'ignore'], timeout: left(),
    });
    const lines = out.split('\n').filter(Boolean);
    return lines.length !== tips.length || lines.some((l) => !l.endsWith(' missing'));
  } catch {
    return true;
  }
}

// Linha de comando dos hooks de shell (uma regra só): node risk-conf.mjs --absent sai 10 no projeto sem o wstack, 0 no
// adotado ou na dúvida (10, não 1: o 1 é o do node que falha ao carregar, e falha não pode ligar o modo inerte).
const self = (() => { try { return realpathSync(fileURLToPath(import.meta.url)); } catch { return ''; } })();
const argv1 = (() => { try { return process.argv[1] ? realpathSync(process.argv[1]) : ''; } catch { return ''; } })();
if (self && self === argv1 && process.argv[2] === '--absent') process.exit(confAbsent() ? 10 : 0);

// Branch padrão do remoto (refs/remotes/origin/HEAD), para o projeto sem risk.conf, onde não há default_branch; '' sem ela.
export function remoteDefault() {
  try { return gitIn(projectDir(), 'symbolic-ref', '--short', '-q', 'refs/remotes/origin/HEAD').replace(/^origin\//, ''); } catch { return ''; }
}
