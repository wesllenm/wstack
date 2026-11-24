// Regra de escrita comum ao write-guard (ferramentas de edição) e ao push-guard (o que um comando Bash grava): recusa
// caminho que passe por uma pasta ou arquivo .git (também no NTFS e atrás de symlink), as pastas git do projeto, que
// numa worktree ficam fora da pasta dele, e a config global e a do sistema do git. A config, os hooks e o .git arquivo
// de um repositório decidem o que o git executa (credential.helper, filter, diff.external, core.fsmonitor, hooks) e para
// onde o push vai. .gitignore, .gitattributes e .github/ continuam livres.
import { lstatSync, readlinkSync } from 'node:fs';
import { dirname, isAbsolute, join, parse, resolve } from 'node:path';
import { git, protectedGitDirs } from './git-repo.mjs';

const win = process.platform === 'win32';
const norm = (p) => p.replace(/\\/g, '/');
// Componente que o sistema trata como .git, também no NTFS (a regra is_ntfs_dotgit do git): sem distinguir maiúsculas,
// sem o fluxo alternativo depois de ':', sem pontos e espaços no fim, e o nome curto 8.3 (GIT~1). Vale em todo sistema,
// para o teste rodar no Linux.
const isDotGit = (c) => {
  const n = c.toLowerCase().split(':')[0].replace(/[. ]+$/, '');
  return n === '.git' || /^git~\d+$/.test(n);
};
const hasGit = (p) => p.split('/').some(isDotGit);
const home = norm(process.env.HOME || process.env.USERPROFILE || '');
const xdg = norm(process.env.XDG_CONFIG_HOME || (home && `${home}/.config`));
// Config global e do sistema: o nome .gitconfig em qualquer pasta, <XDG>/git/ e /etc/gitconfig.
const globalConfig = (p) => p.split('/').some((c) => c.toLowerCase() === '.gitconfig') || (xdg && inside(p, `${xdg}/git`)) || p === '/etc/gitconfig';
// Arquivos que o git lê como config fora do repositório (global, do sistema, os de include.path, e no Windows a
// %PROGRAMDATA%/Git/config) e os programas que essa config manda executar (gpg.program, credential.helper, core.pager,
// core.sshCommand, core.fsmonitor, diff/merge/filter drivers...): perguntados ao próprio git, não adivinhados.
const PROGRAM = /^(gpg(\.[a-z0-9]+)?\.program|credential\.(.*\.)?helper|core\.(pager|editor|sshcommand|fsmonitor|askpass|hookspath)|sequence\.editor|diff\.external|(diff|merge|filter)\..*\.(command|driver|clean|smudge|process|textconv)|uploadpack\.packobjectshook|sendemail\.smtpserver)$/i;
let configTargets;
function gitConfigTargets(cwd) {
  if (configTargets) return configTargets;
  const files = new Set(['/etc/gitconfig']);
  for (const v of [process.env.GIT_CONFIG_GLOBAL, process.env.GIT_CONFIG_SYSTEM, process.env.PROGRAMDATA && `${process.env.PROGRAMDATA}/Git/config`]) {
    if (v) files.add(norm(v));
  }
  try {
    // a origem da config local vem relativa à pasta em que o git rodou (file:.git/config), não ao cwd do hook
    const at = resolve(process.env.CLAUDE_PROJECT_DIR || cwd);
    const out = git(at, 'config', '--show-origin', '--show-scope', '--list', '-z');
    // -z com --show-scope --show-origin: escopo, origem e "chave\nvalor", separados por NUL
    const parts = out.split('\0');
    for (let i = 0; i + 2 < parts.length; i += 3) {
      const [scope, origin, kv] = [parts[i], parts[i + 1], parts[i + 2]];
      const file = origin.startsWith('file:') ? resolve(at, origin.slice(5)) : '';
      if (scope !== 'local' && scope !== 'worktree' && file) files.add(norm(file));
      const nl = kv.indexOf('\n');
      const key = nl < 0 ? kv : kv.slice(0, nl), value = nl < 0 ? '' : kv.slice(nl + 1);
      // o git resolve include.path relativo a partir da pasta do arquivo que o contém, não do cwd
      const base = file ? dirname(file) : at;
      if (/^include(if\..*)?\.path$/i.test(key) && value) files.add(norm(resolve(base, value.replace(/^~\//, `${home}/`))));
      if (PROGRAM.test(key)) {
        const prog = value.replace(/^!/, '').trim().split(/\s+/)[0] ?? '';
        if (/^(\/|[A-Za-z]:[\\/]|~\/)/.test(prog)) files.add(norm(resolve(prog.replace(/^~\//, `${home}/`))));
      }
    }
  } catch { /* sem git legível: ficam os caminhos fixos */ }
  configTargets = [...files];
  return configTargets;
}

export const inside = (p, dir) => {
  const [a, b] = win ? [p.toLowerCase(), dir.toLowerCase()] : [p, dir];
  return a === b || a.startsWith(`${b.replace(/\/$/, '')}/`);
};

// O caminho como o sistema o resolve, componente a componente: cada symlink é seguido (também o pendente, cujo alvo
// ainda não existe e seria criado pelo Write) e o .. sobe a partir da pasta real, não do texto (lnk/.. é o pai do
// alvo do link). Devolve o caminho físico.
export function physical(start) {
  let parts = start.split(/[\\/]+/);
  let cur = parse(start).root || '/';
  parts = parts.slice(1);
  for (let hops = 0; parts.length; ) {
    const c = parts.shift();
    if (c === '' || c === '.') continue;
    if (c === '..') { cur = dirname(cur); continue; }
    const next = join(cur, c);
    let st = null;
    try { st = lstatSync(next); } catch { /* não existe: o resto não tem link a seguir */ }
    if (st?.isSymbolicLink()) {
      if (++hops > 40) throw new Error('symlinks demais');
      const t = readlinkSync(next);
      const base = isAbsolute(t) ? parse(t).root : cur;
      parts = [...t.split(/[\\/]+/).filter((x, i) => !(i === 0 && isAbsolute(t))), ...parts];
      cur = base;
      continue;
    }
    cur = next;
  }
  return norm(cur);
}

// OK ou "DENY <motivo>" para gravar em file (relativo a cwd).
export function writeVerdict(file, cwd) {
  const p = norm(isAbsolute(file) ? file : `${cwd}/${file}`); // sem join: ele normaliza o .. pelo texto
  let r;
  try { r = physical(p); } catch (e) { return `DENY caminho que o hook não resolve: ${e.message}`; }
  for (const candidate of [p, r]) {
    if (hasGit(candidate)) return `DENY gravação em pasta ou arquivo .git: ${file}`;
    if (globalConfig(candidate)) return `DENY gravação na config global do git: ${file}`;
    if (gitConfigTargets(cwd).some((f) => inside(candidate, f))) return `DENY gravação em arquivo que a config do git lê ou executa: ${file}`;
  }
  for (const dir of protectedGitDirs()) {
    if (inside(r, dir)) return `DENY gravação na pasta git do projeto: ${file}`;
  }
  return 'OK';
}
