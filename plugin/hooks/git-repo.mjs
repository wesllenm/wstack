// Repositório do projeto, para os hooks que guardam o git (push-guard) e a escrita em pastas git (write-guard).
// O projeto é $CLAUDE_PROJECT_DIR. A referência só vale se o git a resolve para o checkout principal (a pasta git é
// <projeto>/.git) ou para uma worktree registrada (a pasta git é <comum>/worktrees/<n> e o elo de volta que o git grava
// em <comum>/worktrees/<n>/gitdir aponta para <projeto>/.git): um .git arquivo reescrito não muda a referência.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';

// Prazo total das chamadas ao git: o hook morto pelo timeout do settings.json (10 s) é erro não bloqueante e o allow
// liberaria o comando. Cada chamada usa o que sobra do prazo; esgotado, a chamada falha e o veredito é ASK.
const DEADLINE = Date.now() + 5000; // folga até os 10 s para a partida do bash e de dois node (Windows com antivírus)
export const left = () => Math.max(1, DEADLINE - Date.now());

// LC_ALL=C: a mensagem de "fora de repositório" é lida em foreignRepo e muda com o idioma do sistema.
export const git = (d, ...a) => execFileSync('git', ['-C', d, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: left(), env: { ...process.env, LC_ALL: 'C' } }).trim();

// Uma linha só, caminho absoluto: o git anterior ao 2.31 ecoa o --path-format desconhecido e devolve caminho relativo.
function abs(d, what) {
  const p = git(d, 'rev-parse', '--path-format=absolute', what);
  if (p.includes('\n') || !/^(\/|[A-Za-z]:\/)/.test(p)) throw new Error(`rev-parse ${what}: ${p}`);
  return p;
}

const same = (a, b) => (process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b);
const real = (p) => realpathSync.native(p).replace(/\\/g, '/');

let cached;
// { common, gitDir } do projeto, ou lança erro com o motivo.
export function projectRepo() {
  if (cached) return cached;
  const project = process.env.CLAUDE_PROJECT_DIR;
  if (!project) throw new Error('CLAUDE_PROJECT_DIR ausente');
  const common = abs(project, '--git-common-dir');
  const gitDir = abs(project, '--git-dir');
  const dotGit = join(real(project), '.git').replace(/\\/g, '/');
  if (same(gitDir, common)) {
    // checkout principal: a pasta git é o .git do projeto (pasta), sob o deny de Edit(./.git/**) e o write-guard
    if (!existsSync(dotGit) || !statSync(dotGit).isDirectory() || !same(real(dotGit), gitDir)) throw new Error('a pasta git do projeto não é o .git dele');
  } else {
    if (!isWorktreeDir(gitDir, common)) throw new Error('a pasta git do projeto não é a de uma worktree registrada');
    const back = readFileSync(join(gitDir, 'gitdir'), 'utf8').trim();
    const target = isAbsolute(back) ? back : resolve(gitDir, back);
    if (!existsSync(target) || !same(real(target), dotGit)) throw new Error('o elo de volta da worktree não aponta para o projeto');
  }
  cached = { common, gitDir };
  return cached;
}

function isWorktreeDir(gitDir, common) {
  const base = `${common}/worktrees/`;
  return gitDir.length > base.length && same(gitDir.slice(0, base.length), base) && !gitDir.slice(base.length).includes('/');
}

// '' se o git, rodando em dir, usa o repositório do projeto (checkout principal ou worktree registrada) ou nenhum
// repositório; senão o motivo. Sem CLAUDE_PROJECT_DIR não há referência: ''.
export function foreignRepo(dir) {
  if (!process.env.CLAUDE_PROJECT_DIR) return '';
  let gitDir;
  try {
    gitDir = abs(dir, '--git-dir');
  } catch (e) {
    const err = String(e?.stderr ?? '');
    if (e?.status === 128 && /not a git repository/i.test(err)) return ''; // fora de qualquer repositório: só a config global
    return 'não foi possível ler o repositório do comando';
  }
  try {
    const p = projectRepo();
    const common = abs(dir, '--git-common-dir');
    if (!same(common, p.common)) return 'o repositório do comando não é o do projeto (repositório aninhado ou outro)';
    if (!same(gitDir, common) && !isWorktreeDir(gitDir, common)) return 'a pasta git do comando não é a do projeto nem a de uma worktree registrada';
    return '';
  } catch (e) {
    return `repositório do projeto ilegível: ${e.message}`;
  }
}

// Pastas git que a ferramenta de escrita não pode tocar: as que o git usa para o projeto (a comum e a da sessão, que
// numa worktree ficam fora da pasta do projeto), validada a referência ou não. Vazio se não der para ler.
export function protectedGitDirs() {
  const project = process.env.CLAUDE_PROJECT_DIR;
  const dirs = [];
  for (const what of ['--git-common-dir', '--git-dir']) {
    try { dirs.push(abs(project, what)); } catch { /* sem repositório legível: fica só a regra do componente .git */ }
  }
  return [...new Set(dirs)];
}
