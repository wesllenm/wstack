// Formas fechadas usadas pelo git-read-allow (que as libera) e pelo redirect-guard (que não pede aprovação para elas).
import { existsSync, lstatSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve, sep } from 'node:path';

// O commit da skill commit: git commit [-q] -F - <<'EOF', corpo, e a única linha EOF sendo a última. Com o
// delimitador entre aspas o bash não expande nada no corpo; uma linha EOF no meio encerraria o heredoc e o resto
// viraria comando.
const HEADER = /^git commit(?: -q)? -F - <<'EOF'$/;
export function isCommitHeredoc(cmd) {
  const lines = cmd.replace(/\n$/, '').split('\n');
  return lines.length > 1 && HEADER.test(lines[0]) && lines.indexOf('EOF') === lines.length - 1;
}

// Caminho absoluto literal dentro da pasta temporária e fora do projeto, conferido no caminho REAL: sem .. no texto
// (o kernel resolve o .. depois do symlink), a pasta que existe é seguida por realpath, e o alvo que já existe não pode
// ser symlink nem ter outro nome (hardlink): um /tmp/x apontando para um hook do projeto gravaria nele. No Git Bash, /tmp
// é a pasta temporária do Windows (o resolve do Node daria C:\tmp).
export function inTempDir(p) {
  if (!/^\/[A-Za-z0-9._/+=:@-]+$/.test(p) || /(^|\/)\.\.(\/|$)/.test(p)) return false;
  const win = process.platform === 'win32';
  const text = win && /^\/tmp(\/|$)/.test(p) ? resolve(tmpdir(), `.${p.slice(4)}`) : resolve(p);
  let full;
  try {
    const st = lstatSync(text, { throwIfNoEntry: false });
    if (st && (!st.isFile() || st.nlink > 1)) return false; // lstat: symlink não é arquivo regular
    let dir = dirname(text);
    while (!existsSync(dir)) dir = dirname(dir);
    full = join(realpathSync.native(dir), relative(dir, text));
  } catch { return false; }
  const real = (d) => { try { return realpathSync.native(d); } catch { return resolve(d); } };
  const project = process.env.CLAUDE_PROJECT_DIR && real(process.env.CLAUDE_PROJECT_DIR);
  if (project && (full === project || full.startsWith(`${project}${sep}`))) return false;
  return [tmpdir(), process.env.TMPDIR, '/tmp'].filter(Boolean).some((t) => full.startsWith(`${real(t)}${sep}`));
}
