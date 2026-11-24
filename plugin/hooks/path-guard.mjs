// Veredito do path-guard.sh (payload do PreToolUse em Bash na entrada padrão). Imprime ASK <motivo> ou nada.
// No modo automático e no acceptEdits, o Claude Code não aplica as regras ask de Edit aos comandos de terminal: provado
// com a 2.1.328 (prove-write-matrix.sh), cp, mv, sed -i, rm e tee gravaram até em .claude/hooks/push-guard.sh. Só o deny
// e o ask vindo de hook seguram em todo modo.
// Desenho de autonomia com trava mínima (docs/decisions.md, 2026-11-20): o hook é cinto de segurança, não fronteira (a
// fronteira é o PR, o isolamento e o deny), e pede aprovação só para o que desligaria as próprias travas ou exporia
// segredo. Tudo o mais é livre. O texto é lido sem interpretar aspas, com \ trocada por / (Windows).
// - trava: comando que cita os hooks, o settings.json, o risk.conf, os scripts e o setup da nuvem que os hooks rodam,
//   o .mcp.json, ~/.claude.json, o .git, o .gitignore ou os workflows do GitHub (test-path-guard.sh confere que cada
//   glob de Edit do ask e do deny do settings.json cai numa regra daqui), ou que roda numa pasta dessas;
// - segredo: .env, chaves, settings.local.json, configs com credencial da home, ou comando que mostra credencial
//   (gh auth token, --show-token, git credential): um comando livre mostraria ou publicaria o arquivo por cima do deny;
// - config que executa programa sem citar o caminho: git config (fora da leitura; core.hooksPath desliga os hooks do
//   git, core.fsmonitor executa), gh config/alias/extensão e gh --web (executa o browser: da config), npm config set.
// Livres: as formas fechadas do git-read-allow (git add/diff/log/show não mudam o arquivo) e dos módulos que o risk.conf
// declara (allow_module = dotnet carrega ./dotnet-allow.mjs; sem a declaração, as formas do dotnet caem na regra geral;
// módulo declarado que não carrega faz todo comando pedir), o script do
// projeto no começo do comando (bash .claude/scripts/<nome>, node ..., bash -n ...) quando a pasta do comando é a raiz do
// projeto ou de uma worktree registrada dele (os argumentos depois continuam conferidos), e a leitura simples (cat, ls,
// grep, head, tail, wc, shellcheck, node --check, sem operador do shell), que confere só segredo.
// Na nuvem (CLAUDE_CODE_REMOTE=true) a citação de caminho do harness não pede (docs/decisions.md, 2026-11-23, opção B):
// continuam pedindo o .git, o ~/.claude.json, os segredos, a config que executa programa (git config que grava etc.) e
// a pasta do comando dentro do .git.
// Riscos aceitos (docs/harness-capabilities.md, Riscos aceitos): caminho montado para esconder; comando que troca a árvore
// inteira sem citar a trava (git checkout <ref> -- ., extração de arquivo compactado na raiz).
import { realpathSync } from 'node:fs';
import { relative } from 'node:path';
import { isCommitHeredoc } from './closed-forms.mjs';
import { allowed as gitForm } from './git-read-allow.mjs';
import { foreignRepo, git } from './git-repo.mjs';
import { confValues } from './risk-conf.mjs';

// allow_module = <nome> no risk.conf: ./<nome>-allow.mjs exporta allowed(cmd, cwd), a forma fechada que fica livre. Nome fora
// de ^[a-z0-9-]+$, módulo ausente ou quebrado: moduleFailure, e todo comando pede (falha fechada, nunca exceção).
const NAME = /^[a-z0-9-]+$/;
const moduleForms = [];
let moduleFailure = '';
for (const name of confValues('allow_module')) {
  try {
    if (!NAME.test(name)) throw new Error('nome inválido');
    const m = await import(new URL(`./${name}-allow.mjs`, import.meta.url).href);
    if (typeof m.allowed !== 'function') throw new Error('não exporta allowed');
    moduleForms.push(m.allowed);
  } catch (e) {
    moduleFailure = moduleFailure || `allow_module = ${name} do risk.conf não carregou (${String(e.message).split('\n')[0]})`;
  }
}

const END = '(?![A-Za-z0-9_-])';
// O terceiro item marca o que continua pedindo na nuvem (CLAUDE_CODE_REMOTE=true): a trava por texto é contornável
// (cp /dev/null .cl""aude/hooks/x, tee, sed -i), então lá a citação de caminho do harness é livre e o que protege é o
// que sai da VM (push-guard e checkpoint.sh, protected-paths.mjs). Ficam o .git (config e hooks: core.hooksPath
// executaria código no push com a credencial da VM) e o ~/.claude.json (config do usuário, fora do repositório).
const GUARD = [
  // os marcadores .verify-ok e .session/checkpoint-ok-* fazem o Stop e o checkpoint pularem build e testes
  ['.claude/hooks, settings, risk.conf, scripts, cloud, marcadores', /\.claude\/(?:hooks|settings|risk\.conf|scripts|cloud|\.verify-ok|\.session\/checkpoint-ok)/i],
  ['pasta .claude', /\.claude\/?(?=$|[\s;&|)'"`])/i],
  ['~/.claude.json', /\.claude\.json/i, true],
  ['.mcp.json', /\.mcp\.json/i],
  ['.git', new RegExp(`\\.git${END}`, 'i'), true],
  ['.gitignore', new RegExp(`\\.gitignore${END}`, 'i')],
  ['.github/workflows', /\.github\/workflows/i],
];
const SECRET = [
  ['.env', new RegExp(`(?<![A-Za-z0-9_$])\\.env${END}`, 'i')],
  ['*.pem/*.pfx/*.p12', new RegExp(`\\.(?:pem|pfx|p12)${END}`, 'i')],
  ['settings.local.json', /settings\.local\.json/i],
  ['appsettings.*.local.json', /appsettings\.[^\s'"]*local\.json/i],
  ['.ssh', new RegExp(`\\.ssh${END}`, 'i')],
  ['.config/gh', new RegExp(`\\.config/gh${END}`, 'i')],
  ['.docker', new RegExp(`\\.docker${END}`, 'i')],
  ['.kube', new RegExp(`\\.kube${END}`, 'i')],
  ['.git-credentials', /\.git-credentials/i],
  ['.netrc', /\.netrc/i],
  ['.gitconfig/.config/git', new RegExp(`\\.gitconfig|\\.config/git${END}`, 'i')],
  ['.npmrc', /\.npmrc/i],
  ['.aws', new RegExp(`\\.aws${END}`, 'i')],
  ['.claude/.credentials', /\.claude\/\.credentials/i],
  ['.nuget/NuGet', /\.nuget\/NuGet/i],
];
const SCRIPT = /^(?:bash(?: -n)? |node )?\.claude\/(?:scripts|hooks|cloud)\/[A-Za-z0-9._-]+(?=\s|$)/;
// Programa na posição de comando: começo, depois de ; & | ( { crase $( aspas, quebra de linha, palavra-chave do bash
// (then, do, else, elif, !), atribuição e prefixo que roda o comando seguinte (env, xargs, nice, timeout 10...), com ou
// sem caminho antes do nome (/usr/bin/gh). "grep gh x" não conta.
const PREFIX = '[A-Za-z_][A-Za-z0-9_]*=\\S*|(?:env|nice|ionice|stdbuf)(?:\\s+-\\S+)*|xargs|sudo|exec|time|nohup|command|busybox|then|do|else|elif|!|timeout(?:\\s+-\\S+)*\\s+\\S+';
const AT = `(?:^|[;&|({\`\\n"']|\\$\\()\\s*(?:(?:${PREFIX})\\s+)*`;
const prog = (name, rest = '') => new RegExp(`(?:${AT}(?:[^\\s;&|'"]*/)?|/)${name}(?:\\.exe)?["']?(?=\\s|$)${rest}`, 'i');
const ARGS = '[^\\n;&|]*?';
const EOW = '(?=[\\s=;&|)`]|$)'; // fim da palavra: espaço, =, operador do shell ou fim
const IMPLICIT = [
  ['gh auth token/--show-token', prog('gh', `${ARGS}\\s(?:auth\\s+token|--show-token|auth\\s+status${ARGS}\\s-[A-Za-z]*t[A-Za-z]*)${EOW}`)],
  ['git credential', prog('git', `${ARGS}\\scredential${EOW}`)],
  ['git config', prog('git', `${ARGS}\\sconfig(?!\\s+(?:--get|--get-all|--get-regexp|--list|-l)(?:\\s|$))${EOW}`)],
  ['gh config/alias/extensão', prog('gh', `${ARGS}\\s(?:config\\s+set|alias\\s+(?:set|import)|ext(?:ension)?s?\\s+install)${EOW}`)],
  ['gh --web/browse', prog('gh', `${ARGS}\\s(?:--web|-[A-Za-z]*w[A-Za-z]*|browse)${EOW}`)],
  ['npm config set', prog('npm', `${ARGS}\\sconfig\\s+set${EOW}`)],
];
// Leitura simples (um programa que não grava nem executa, sem ; & | $ crase parênteses < > nem quebra de linha):
// confere só segredo. rg fica fora (--pre executa um programa).
const READONLY = /^(?:cat|ls|grep|head|tail|wc|shellcheck|node --check)(?: [^;&|`$()<>\n\r]*)?$/;
const MAX = 20000;

const real = (p) => { try { return realpathSync.native(p).replace(/\\/g, '/'); } catch { return p.replace(/\\/g, '/'); } };
const hit = (list, text) => list.find(([, re]) => re.test(text))?.[0];

// O script do harness chamado pelo caminho absoluto da raiz do projeto (a pasta do comando) vale o relativo: o texto
// ganha a forma relativa, e a posição e a pasta do comando continuam conferidas como nela. Outra raiz fica como está.
function relativeScript(text, here) {
  const project = process.env.CLAUDE_PROJECT_DIR;
  const roots = [here, project && real(project) === here ? project.replace(/\\/g, '/') : ''].filter(Boolean);
  const lead = /^(?:bash(?: -n)? |node )?/.exec(text)[0].length;
  for (const root of roots) {
    const prefix = `${root.replace(/\/$/, '')}/`;
    if (text.startsWith(`${prefix}.claude/`, lead)) return text.slice(0, lead) + text.slice(lead + prefix.length);
  }
  return text;
}

// Raiz do repositório da pasta do comando, ou '' fora de repositório
function toplevel(cwd) {
  try { return real(git(cwd, 'rev-parse', '--show-toplevel')); } catch { return ''; }
}

export function verdict(cmd, cwd) {
  if (typeof cmd !== 'string') return 'ASK payload sem comando';
  if (cmd.length > MAX) return `ASK comando maior que ${MAX} caracteres`;
  if (moduleFailure) return `ASK ${moduleFailure}`;
  let text = cmd.replace(/\\/g, '/');
  // segredo antes das formas livres: git show e git diff MOSTRAM o arquivo (o corpo do heredoc de commit não roda)
  const secret = isCommitHeredoc(cmd) ? undefined : hit(SECRET, text) ?? hit(IMPLICIT.slice(0, 2), text);
  if (secret) return `ASK o comando cita ou mostra um segredo (${secret}): o deny de Read não vale para o que o comando mostra ou publica`;
  if (gitForm(cmd) || moduleForms.some((allowed) => allowed(cmd, cwd))) return '';
  const top = toplevel(cwd);
  const here = real(cwd);
  // a pasta do comando, relativa à raiz do repositório dela (uma worktree em .claude/worktrees/ tem raiz própria)
  const rel = top ? relative(top, here).replace(/\\/g, '/') : here;
  const guards = process.env.CLAUDE_CODE_REMOTE === 'true' ? GUARD.filter(([, , cloud]) => cloud) : GUARD;
  const inCwd = hit(guards, rel) ?? hit(SECRET, rel);
  if (inCwd) return `ASK a pasta do comando é uma trava ou guarda segredo (${inCwd}): ${here}`;
  const relText = relativeScript(text, here);
  const script = SCRIPT.exec(relText);
  if (script && top && top === here && foreignRepo(here) === '') text = relText.slice(script[0].length);
  const implicit = hit(IMPLICIT, text);
  if (implicit) return `ASK ${implicit} muda config que executa programa ou mostra credencial sem citar o caminho`;
  if (READONLY.test(text)) return '';
  const guard = hit(guards, text);
  if (guard) return `ASK o comando cita uma trava do harness (${guard}): no modo automático o Claude Code não aplica o ask de Edit a comandos de terminal`;
  return '';
}

let d = '';
process.stdin.on('data', (c) => (d += c)).on('end', () => {
  let j;
  try { j = JSON.parse(d); } catch { process.stdout.write('ASK payload ilegível'); return; }
  process.stdout.write(verdict(j?.tool_input?.command, String(j?.cwd ?? process.cwd())));
});
