// Veredito do script-allow.sh (payload do PreToolUse em Bash na entrada padrão). Imprime ALLOW ou nada.
// Os scripts do harness ficam no plugin e as skills os chamam pelo caminho dele (docs/decisions.md, scripts no plugin,
// aprovados por hook): sem regra allow no projeto, este hook aprova as mesmas chamadas que o harness liberava, só em
// forma fechada. Nunca por prefixo: o comando inteiro casa com
//   [bash |node ]<pasta do plugin>/scripts/<script da lista> <argumentos>
// onde o interpretador é o do script, a pasta é a deste plugin (como o Claude Code a escreve nas skills, ou o caminho
// real) e cada argumento é uma palavra simples, um texto entre aspas simples ou um texto entre aspas duplas sem $, crase,
// barra invertida nem ! (nada que o bash expanda ou que encadeie outro comando). Também: os testes do plugin sem
// argumento, o setup da nuvem em --check e --plan e a conferência de sintaxe (bash -n) de um arquivo do plugin.
// A pasta do comando tem de ser a raiz do projeto ($CLAUDE_PROJECT_DIR, ou uma worktree registrada dele): em outra pasta
// o script trataria outro repositório. Fora disso o hook não diz nada e vale o pedido de permissão normal. Os outros
// hooks (path-guard, redirect-guard, push-guard) continuam conferindo o mesmo comando, e o pedido deles vale sobre esta
// aprovação.
// Plugin rodando de dentro do próprio projeto (o repositório do wstack, plugin carregado do clone): lá a ferramenta de
// escrita edita o plugin, então só aprova com a pasta inteira do plugin igual à da branch padrão em origin (o que passou
// por PR): nada alterado, apagado ou fora do git, nem marcado para o git não ver. Um script pode importar hooks e outros
// módulos, por isso a pasta inteira, não só o script chamado. Sem origin/<branch padrão>, não aprova.
import { existsSync, realpathSync } from 'node:fs';
import { foreignRepo, git } from './git-repo.mjs';
import { pluginInProject, pluginRoots } from './plugin-root.mjs';
import { defaultBranches } from './protected-paths.mjs';

// Scripts que o harness liberava, com os interpretadores aceitos ('' = execução direta). O que envia trabalho para a
// nuvem (enviar-nuvem.sh) pede aprovação de propósito e fica fora; nova-atividade, recall e permission-asks nunca foram
// liberados.
const SCRIPTS = {
  'classify-diff.sh': ['bash', ''],
  'bench-compare.sh': ['bash', ''],
  'quality-signals.sh': ['bash'],
  'calibrate-risk.sh': ['bash'],
  'bundle-size.sh': ['bash'],
  'sessions.sh': ['bash', ''],
  'worktree-env.sh': ['bash', ''],
  'checkpoint.sh': ['bash'],
  'prune-merged.sh': ['bash'],
  'summarize-runs.mjs': ['node'],
  'review-dispatch.mjs': ['node'],
  'check-findings.mjs': ['node'],
  // o envio ao fornecedor externo foi consentido ao pôr interrogate_cmd no risk.conf, que é trava (ask/deny)
  'interrogate.mjs': ['node'],
  // só imprime linha e padrão, nunca o texto: não serve para ler arquivo protegido por tabela
  'slop-check.mjs': ['node'],
  'diff-smells.mjs': ['node'],
  'map-staleness.mjs': ['node'],
  'pr-risk-gate.mjs': ['node'],
};

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const ROOT = `(${pluginRoots().map(escape).join('|')})`;
const ARG = `(?:[A-Za-z0-9_@%+=:,./-]+|'[^'\\n\\r]*'|"[^"$\`\\\\!\\n\\r]*")`;
const FREE = new RegExp(`^(?:(bash|node) )?${ROOT}/scripts/([A-Za-z0-9_-]+\\.(?:sh|mjs))((?: +${ARG})*) *$`);
const TEST = new RegExp(`^bash ${ROOT}/tests/(test-[a-z0-9-]+\\.sh)$`);
const SETUP = new RegExp(`^bash ${ROOT}/cloud/setup\\.sh --(?:check|plan)$`);
const SYNTAX = new RegExp(`^bash -n ${ROOT}/(scripts|hooks|cloud)/([A-Za-z0-9_-][A-Za-z0-9._-]*)$`);

function form(cmd) {
  if (typeof cmd !== 'string' || /[\n\r]/.test(cmd)) return false;
  let m = FREE.exec(cmd);
  if (m) {
    const [, interp = '', root, name] = m;
    return (SCRIPTS[name] ?? []).includes(interp) && existsSync(`${root}/scripts/${name}`);
  }
  if ((m = TEST.exec(cmd))) return existsSync(`${m[1]}/tests/${m[2]}`);
  if (SETUP.test(cmd)) return true;
  if ((m = SYNTAX.exec(cmd))) return existsSync(`${m[1]}/${m[2]}/${m[3]}`);
  return false;
}

const real = (p) => realpathSync.native(p).replace(/\\/g, '/');
function atProjectRoot(cwd) {
  if (!process.env.CLAUDE_PROJECT_DIR) return false;
  try {
    const dir = real(cwd);
    return real(git(dir, 'rev-parse', '--show-toplevel')) === dir && foreignRepo(dir) === '';
  } catch {
    return false;
  }
}

// Pasta do plugin no projeto igual à de origin/<branch padrão>; true quando o plugin não está no projeto
function reviewed() {
  const rel = pluginInProject();
  if (!rel) return true;
  try {
    const dir = real(process.env.CLAUDE_PROJECT_DIR);
    const base = `refs/remotes/origin/${defaultBranches()[0] ?? 'main'}`;
    git(dir, 'rev-parse', '--verify', '-q', `${base}^{commit}`);
    git(dir, 'diff', '--quiet', base, '--', rel); // código 1 (diferença) lança
    if (git(dir, 'ls-files', '--others', '--', rel) !== '') return false;
    // assume-unchanged (letra minúscula) e skip-worktree (S) escondem do diff a mudança na árvore
    return !git(dir, 'ls-files', '-v', '--', rel).split('\n').some((l) => /^(?:[a-z]|S) /.test(l));
  } catch {
    return false;
  }
}

export const verdict = (cmd, cwd) => (form(cmd) && atProjectRoot(cwd) && reviewed() ? 'ALLOW' : '');

let d = '';
process.stdin.on('data', (c) => (d += c)).on('end', () => {
  let j;
  try { j = JSON.parse(d); } catch { return; }
  process.stdout.write(verdict(j?.tool_input?.command, String(j?.cwd ?? process.cwd())));
});
