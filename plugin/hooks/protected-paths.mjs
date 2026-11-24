// Caminhos protegidos que o que SAI da máquina não pode alterar sem aprovação do desenvolvedor, e a conferência do que um
// push ou um checkpoint publicaria (docs/decisions.md, 2026-11-23, opção B). Na VM da nuvem os hooks de escrita não leem o
// texto do comando (trava por texto é contornável); a barreira é aqui: um workflow em .github/ numa ref publicada
// dispara o GitHub Actions com segredos, e um hook, script ou settings alterado vale na próxima sessão.
// Usado pelo push-guard.mjs (import) e pelo checkpoint.sh (linha de comando).
// De onde vem cada valor: o núcleo (harness, .github, arquivos que o git executa, .mcp.json) está fixo aqui; os caminhos que
// cada projeto acrescenta (protected = <glob>, ex.: ci/*, .devcontainer/*) e a branch padrão (default_branch, a base do
// merge-base; sem ela, main) vêm do .claude/risk.conf do projeto dos hooks (risk-conf.mjs). A configuração só ACRESCENTA ao núcleo.
// Linha de comando: node protected-paths.mjs <ref> [<pasta>]
//   código 0  nada protegido muda entre o merge-base com origin/<branch padrão> e a ref; imprime OK
//   código 1  muda; imprime um arquivo por linha
//   código 3  não foi possível conferir (sem origin/<branch padrão>, sem merge-base, git falhou): falha fechada; imprime o motivo
//   código 2  uso errado
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { git } from './git-repo.mjs';
import { confError, confValues } from './risk-conf.mjs';

// Caminho relativo à raiz do repositório. .gitattributes e .gitmodules valem em qualquer pasta: o git lê o .gitattributes de
// cada pasta (filter= executa programa) e o .gitmodules de uma subpasta é inócuo, mas custa nada pedir. O .gitignore também:
// tirar o .env dele deixaria o git add -A publicar o segredo sem nada pedir.
const CORE = [
  /^\.claude\/(?:hooks|scripts|agents|skills|cloud)\//i,
  /^\.claude\/(?:settings\.json|settings\.local\.json|risk\.conf)$/i,
  /^\.github\//i,
  /(?:^|\/)\.git(?:attributes|modules|ignore)$/i,
  /^\.mcp\.json$/i,
];

// Glob do risk.conf relativo à raiz, sem diferenciar caixa: só "*" (qualquer sequência, inclusive "/") e "?" (um caractere)
// são curingas; qualquer outro caractere, inclusive "[", "]" e os de regex, é literal. O curinga casa também quebra de
// linha: nome de arquivo pode ter LF ou CR, e o "." do regex não os casaria.
const literal = (c) => c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
const globRe = (glob) => new RegExp(`^${[...glob].map((c) => (c === '*' ? '[\\s\\S]*' : c === '?' ? '[\\s\\S]' : literal(c))).join('')}$`, 'i');
const PROTECTED = [...CORE, ...confValues('protected').filter(Boolean).map(globRe)];
export const isProtected = (path) => PROTECTED.some((re) => re.test(path));

// Primeira default_branch declarada no alfabeto fechado (sem barra); ausente ou inválida, main. O push-guard.mjs usa o
// mesmo alfabeto para recusar o push para cada uma.
export const defaultBranches = () => confValues('default_branch').filter((v) => /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(v));
const baseBranch = () => defaultBranches()[0] ?? 'main';

// Commit da ref, '' se ela não existe (o git push dela também falharia: nada é publicado), erro se o git falhou.
export function commitOf(dir, ref) {
  try {
    return git(dir, 'rev-parse', '--verify', '-q', '--end-of-options', `${ref}^{commit}`);
  } catch (e) {
    if (e.status === 1) return '';
    throw e;
  }
}

// Commit da ref de nome COMPLETO (refs/...), '' se ela não existe. Sem a busca por nome curto do rev-parse (pseudo-ref
// .git/<nome>, 40 hex como objeto), que o git push não faz: ele casa a origem do refspec só entre as refs locais.
export function exactRefCommit(dir, name) {
  const hit = git(dir, 'for-each-ref', '--format=%(refname)%09%(objectname)', '--', name)
    .split('\n').map((l) => l.split('\t')).find(([n]) => n === name);
  return hit ? commitOf(dir, hit[1]) : '';
}

// { files, failed }: os arquivos protegidos alterados entre o merge-base de origin/<branch padrão> com o commit e o commit,
// ou o motivo de não ter conseguido conferir (failed não vazio vale como alterado: falha fechada).
export function protectedChanged(dir, commit) {
  if (confError()) return { files: [], failed: `não foi possível ler o .claude/risk.conf do projeto (${confError()}): sem ele faltam os caminhos protegidos do projeto` };
  const origin = `origin/${baseBranch()}`;
  try {
    git(dir, 'rev-parse', '--verify', '-q', `refs/remotes/${origin}^{commit}`);
  } catch {
    return { files: [], failed: `não há ${origin} para comparar (${origin} ausente): não dá para saber o que o push publica` };
  }
  let base;
  try {
    base = git(dir, 'merge-base', `refs/remotes/${origin}`, commit);
  } catch (e) {
    return { files: [], failed: e.status === 1 ? `sem merge-base com ${origin} (histórico sem ancestral comum)` : `não foi possível calcular o merge-base com ${origin}: ${e.message.split('\n')[0]}` };
  }
  try {
    const out = git(dir, 'diff-tree', '-r', '--no-renames', '--name-only', '-z', base, commit);
    return { files: out.split('\0').filter((f) => f && isProtected(f)), failed: '' };
  } catch (e) {
    return { files: [], failed: `não foi possível listar o que muda desde o merge-base: ${e.message.split('\n')[0]}` };
  }
}

export const list = (files) => files.slice(0, 10).join(', ') + (files.length > 10 ? ` e mais ${files.length - 10}` : '');

const sameFile = (a, b) => { try { return realpathSync(a) === realpathSync(b); } catch { return false; } };
if (process.argv[1] && sameFile(fileURLToPath(import.meta.url), process.argv[1])) {
  const [ref, dir = '.'] = process.argv.slice(2);
  if (!ref || ref.startsWith('-') || process.argv.length > 4) { process.stderr.write('uso: protected-paths.mjs <ref> [<pasta>]\n'); process.exit(2); }
  let result;
  try {
    const commit = commitOf(dir, ref);
    result = commit ? protectedChanged(dir, commit) : { files: [], failed: `a ref ${ref} não existe` };
  } catch (e) {
    result = { files: [], failed: `git falhou: ${e.message.split('\n')[0]}` };
  }
  if (result.failed) { process.stdout.write(`${result.failed}\n`); process.exit(3); }
  if (result.files.length) { process.stdout.write(`${result.files.join('\n')}\n`); process.exit(1); }
  process.stdout.write('OK\n'); // quem chama exige este texto: saída vazia (programa que não rodou) nunca vale como limpo
}
