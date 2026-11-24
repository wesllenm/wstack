// Veredito do git-read-allow.sh (payload do PreToolUse em Bash na entrada padrão). Imprime ALLOW ou nada.
// git log, git diff e git show saíram do allow do settings.json: por prefixo, a regra aceitava --output=<arquivo>, que
// grava a saída em qualquer arquivo (a mensagem de um commit vira .git/config e o git status seguinte executa o
// fsmonitor dela). Este hook devolve allow só para o comando INTEIRO num formato fechado; qualquer outra forma não
// recebe nada daqui e cai no pedido de permissão normal. Um buraco no formato vira pedido, nunca gravação liberada.
// - começa por "git log", "git diff" ou "git show", sem nada antes (variável, cd, opção do git antes do subcomando);
// - cada palavra só tem caracteres em que o bash não expande nada: letras, dígitos e . _ / : @ ^ % = , + -, com ~ só
//   depois de letra, dígito, . _ ou ^ (HEAD~1); sem aspas, $, crase, chaves, glob, parênteses, barra invertida, < >;
// - nenhuma palavra começa por --ou (--output e as abreviações que o git aceita);
// - separadas só por espaço; no fim, no máximo 2>/dev/null ou 2>&1 e um "| tail -N" ou "| head -N";
// - nada de ler fora do repositório: sem --no-index, sem palavra que comece por / ou por letra de drive (C:/, c:x no
//   Git Bash) e sem .. como caminho (o git diff
//   com um caminho de fora entra sozinho no modo no-index e mostraria um arquivo que o deny de Read protege).
// git stash list aceita as opções do git log (--output inclusive) e entra no mesmo formato. Fora da leitura, só duas
// formas exatas: git switch -c <nome> (sem ponto de partida, que trocaria a árvore, os hooks inclusive, pela de outro
// commit) e git branch --list (sem argumento: --no-list -D apagaria a branch por cima do deny).
// git add e git commit também saíram do allow: git add -f põe no índice um arquivo que o .gitignore esconde (o .env)
// e git show :.env o mostraria; git commit -F .env, ou -F - < .env, põe o arquivo na mensagem. Por isso:
// - git add no mesmo formato fechado, sem forçar (--f..., -f também dentro de grupo de opções curtas como -nf) e sem
//   --pathspec-from-file (o erro do git ecoaria o conteúdo do arquivo como pathspec);
// - git commit só em duas formas exatas: o heredoc da skill commit (git commit [-q] -F - <<'EOF', com o delimitador
//   entre aspas, que o bash não expande, e a única linha EOF sendo a última: uma linha EOF no meio encerraria o
//   heredoc e o resto viraria comando) ou git commit [-q] -F <arquivo literal na pasta temporária>.
// Quatro rodadas de revisão furaram a procura do perigoso no meio de comandos livres (PR #11): aqui só a forma exata sai.
import { basename } from 'node:path';
import { inTempDir, isCommitHeredoc } from './closed-forms.mjs';

const WORD = '(?:[A-Za-z0-9._/:@^%=,+-]|(?<=[A-Za-z0-9._^])~)+';
const TAIL = '(?: +2>(?:/dev/null|&1))?(?: +\\| +(?:tail|head) +(?:-n +)?-?[0-9]+)?';
const READ = new RegExp(`^git (?:log|diff|show|stash list)((?: +${WORD})*)${TAIL}$`);
const ADD = new RegExp(`^git add((?: +${WORD})*)${TAIL}$`);
const EXACT = new RegExp(`^(?:git switch -c [A-Za-z0-9][A-Za-z0-9._/-]*|git branch --list)${TAIL}$`);
const COMMIT_FILE = /^git commit(?: -q)? -F (\/[A-Za-z0-9._/-]+)$/;
const OUTSIDE = (w) => w === '--no-index' || w.startsWith('--ou') || /^(-[A-Za-z])?\/|=\/|(^|=|^-[A-Za-z])[A-Za-z]:|(^|[=/]|^-[A-Za-z])\.\.(\/|$)/.test(w);
const FORCE = (w) => w.startsWith('--f') || w.startsWith('--pathspec') || /^-[A-Za-z]*f/.test(w);

function commitOk(cmd) {
  const m = COMMIT_FILE.exec(cmd);
  return m ? inTempDir(m[1]) : isCommitHeredoc(cmd);
}

// Exportada para o path-guard, que não pede aprovação para estas formas (git add e git diff de um caminho protegido
// não o mudam).
export function allowed(cmd) {
  if (typeof cmd !== 'string') return false;
  const r = READ.exec(cmd);
  if (r) return !r[1].split(/ +/).some(OUTSIDE);
  const a = ADD.exec(cmd);
  if (a) return !a[1].split(/ +/).some((w) => OUTSIDE(w) || FORCE(w));
  if (cmd.startsWith('git commit ')) return commitOk(cmd);
  return EXACT.test(cmd);
}

// Só lê a entrada quando roda como o hook, não quando o path-guard importa allowed
if (basename(process.argv[1] ?? '') === 'git-read-allow.mjs') {
  let d = '';
  process.stdin.on('data', (c) => (d += c)).on('end', () => {
    let cmd;
    try { cmd = JSON.parse(d)?.tool_input?.command; } catch { return; }
    if (allowed(cmd)) process.stdout.write('ALLOW');
  });
}
