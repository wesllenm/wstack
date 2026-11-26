// Veredito do path-guard.sh (payload do PreToolUse em Bash na entrada padrão). Imprime ASK <motivo> ou nada.
// No modo automático e no acceptEdits, o Claude Code não aplica as regras ask de Edit aos comandos de terminal
// (tests/prove-write-matrix.sh mede isso com o Claude Code real: cp, mv, sed -i, rm e tee gravam em caminho do ask).
// Este hook cobre esse buraco pelo texto do comando.
// Trava mínima (docs/decisions.md, trava mínima nos comandos): o hook é cinto de segurança, não fronteira (a fronteira é
// o PR, o isolamento e o deny), e pede aprovação só para o que desligaria as próprias travas ou exporia segredo. Tudo o
// mais é livre. O texto é lido sem interpretar aspas, com \ trocada por / (Windows).
// - trava: comando que cita os arquivos do plugin (~/.claude/plugins, onde estão estes hooks e os scripts que eles e as
//   skills rodam), o settings.json (que fixa a versão do plugin), o risk.conf, os hooks, scripts e setup da nuvem que um
//   projeto ainda tenha em .claude/, o .mcp.json, ~/.claude.json, o .git, o .gitignore ou os workflows do GitHub
//   (test-path-guard.sh confere que cada glob de Edit do ask e do deny do settings.json modelo cai numa regra daqui), ou
//   que roda numa pasta dessas;
// - segredo: .env, chaves, settings.local.json, configs com credencial da home, ou comando que mostra credencial
//   (gh auth token, --show-token, git credential): um comando livre mostraria ou publicaria o arquivo por cima do deny;
// - config que executa programa sem citar o caminho: git config (fora da leitura; core.hooksPath desliga os hooks do
//   git, core.fsmonitor executa), gh config/alias/extensão e gh --web (executa o browser: da config), npm config set.
// Livres: as formas fechadas do git-read-allow (git add/diff/log/show não mudam o arquivo) e dos módulos que o risk.conf
// declara (allow_module = dotnet carrega ./dotnet-allow.mjs; sem a declaração, as formas do dotnet caem na regra geral;
// módulo declarado que não carrega faz todo comando pedir), o script do plugin no começo do comando, pelo caminho real
// desta pasta de plugin (bash <plugin>/scripts/<nome>, node ..., bash -n ...), quando a pasta do comando é a raiz do
// projeto ou de uma worktree registrada dele (os argumentos depois continuam conferidos), e a leitura simples (cat, ls,
// grep, head, tail, wc, shellcheck, node --check, sem operador do shell), que confere só segredo.
// Na nuvem (CLAUDE_CODE_REMOTE=true) a citação de caminho do harness não pede (docs/decisions.md, trava por texto na
// nuvem): continuam pedindo o .git, o ~/.claude.json, os segredos, a config que executa programa (git config que grava
// etc.) e a pasta do comando dentro do .git.
// Riscos aceitos (docs/harness-capabilities.md, Riscos aceitos): caminho montado para esconder; comando que troca a árvore
// inteira sem citar a trava (git checkout <ref> -- ., extração de arquivo compactado na raiz).
import { realpathSync } from 'node:fs';
import { relative } from 'node:path';
import { isCommitHeredoc } from './closed-forms.mjs';
import { allowed as gitForm } from './git-read-allow.mjs';
import { foreignRepo, git } from './git-repo.mjs';
import { pluginRoots } from './plugin-root.mjs';
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
// A pasta do plugin, como o Claude Code a escreve no texto das skills e pelo caminho real (plugin-root.mjs): trava pelo
// caminho, também fora de ~/.claude/plugins (CLAUDE_CONFIG_DIR em outra pasta, ~/.claude atrás de um link).
const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const ROOTS_RE = `(?:${pluginRoots().map(escape).join('|')})`;
const GUARD = [
  ['pasta do plugin wstack', new RegExp(`${ROOTS_RE}(?=$|[/\\s;&|)'"\`])`)],
  // os marcadores .verify-ok e .session/checkpoint-ok-* fazem o Stop e o checkpoint pularem build e testes, e a exceção
  // verify-blocked.md libera o Stop: só com aprovação do desenvolvedor
  ['.claude/plugins, hooks, settings, risk.conf, scripts, cloud, marcadores', /\.claude\/(?:plugins|hooks|settings|risk\.conf|scripts|cloud|\.verify-ok|verify-blocked|\.session\/checkpoint-ok)/i],
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
// Recusas que valem também na nuvem, onde a trava de texto pede pouco (ninguém responde ao pedido): o marcador de
// verificação pendente, que segura o push (pelo nome, por glob na pasta, ou rm/mv/find nela), e, só na nuvem, a exceção
// de verificação, que fora dela pede aprovação pelo GUARD. Deny, não ask: na nuvem um pedido sem resposta trava a sessão.
const LOCKED = [
  ['marcador de verificação pendente (.claude/.session)', /\.claude\/\.session\/(?:unverified|[*?[])|\.claude\/\.session\b[\s\S]*\bunverified|\b(?:rm|mv|cp|find|rsync|truncate|unlink|shred|ln)\b[^\n;&|]*\.claude\/\.session/i, false],
  ['exceção de verificação (.claude/verify-blocked.md)', /\.claude\/verify-blocked/i, true],
];
const SESSION_CWD = /^\.claude\/\.session(?:\/|$)/i;
const SESSION_CWD_TEXT = /\bunverified|\b(?:rm|mv|cp|find|rsync|truncate|unlink|shred|ln)\b/i;

// O script do plugin no começo do comando, pela pasta do plugin (ROOTS_RE, acima)
const SCRIPT =new RegExp(`^(?:bash(?: -n)? |node )?${ROOTS_RE}/(?:scripts|hooks|cloud)/[A-Za-z0-9._-]+(?=\\s|$)`);
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
  const remote = process.env.CLAUDE_CODE_REMOTE === 'true';
  const guards = remote ? GUARD.filter(([, , cloud]) => cloud) : GUARD;
  if (SESSION_CWD.test(rel) && SESSION_CWD_TEXT.test(text)) return `DENY comando na pasta .claude/.session mexendo no estado dos hooks: só os hooks gravam ali`;
  const inCwd = hit(guards, rel) ?? hit(SECRET, rel);
  if (inCwd) return `ASK a pasta do comando é uma trava ou guarda segredo (${inCwd}): ${here}`;
  // o script do plugin no começo, rodando na raiz do projeto: o nome dele não conta como citação de trava (os
  // argumentos e o que vier depois continuam conferidos); em outra pasta, ele trataria outro repositório
  const script = SCRIPT.exec(text);
  if (script && top && top === here && foreignRepo(here) === '') text = text.slice(script[0].length);
  const implicit = hit(IMPLICIT, text);
  if (implicit) return `ASK ${implicit} muda config que executa programa ou mostra credencial sem citar o caminho`;
  if (READONLY.test(text)) return '';
  const locked = LOCKED.find(([, re, cloudOnly]) => (!cloudOnly || remote) && re.test(text));
  if (locked) return `DENY o comando mexe em ${locked[0]}: só os hooks (ou o desenvolvedor, fora do agente) gravam ali`;
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
