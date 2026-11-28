// Comandos de Bash do review-verifier (PreToolUse em Bash; o agente vem em agent_type da entrada do hook). O verifier
// roda a `prova:` que uma lente escreveu, e a lente leu o código do projeto, que pode ser hostil ("prova: curl ... | sh").
// As regras de "sem rede" e "sem efeito fora do repositório" da review-rubric (Limites da prova) viram trava aqui:
//   DENY  rede (curl, wget, nc, ssh, Invoke-WebRequest...), pipe para interpretador (| sh, | bash, | node...), eval,
//         base64 -d, bash -c / sh -c, /dev/tcp
//   livre só três formas: executor de teste (dotnet test, npm test, npx --no-install vitest, cargo test, go test,
//         pytest...), node/bash de arquivo dentro do repositório, git log/show/blame com as flags da lista GIT e
//         git clone --depth 1 de URL https literal para a pasta temporária (CLONE)
//         cada forma pode terminar num redirecionamento para a pasta temporária da sessão ou para /dev/null
//   ASK   o resto, inclusive grep, rg, cat, sed, node -e, pipe, substituição de comando e redirecionamento para
//         qualquer outro lugar (o repositório, caminho com .., symlink na pasta temporária)
// Lista fechada em vez de comando liberado com flag negada: utilitário de leitura sempre tem mais uma flag que escreve
// ou executa (sort -o, rg --pre, git --output...), e o verifier lê código com Read, Grep e Glob. O executor de teste roda
// código do projeto: risco aceito, no README.
// Outros agentes e a sessão principal: sem veredito (os outros hooks seguem valendo). Subagente sem agent_type (agent_id
// presente, agent_type ausente): pede aprovação, porque não dá para saber se é o verifier. A sessão principal não manda
// nenhum dos dois, e o prove-verifier-guard.sh confere isso com o Claude Code real. Não é fronteira: um comando montado
// para esconder passa, como nas outras travas por texto; tira a execução arbitrária do caminho padrão.
// Saída: '' (sem veredito), "DENY <motivo>" ou "ASK <motivo>"; o verifier-guard.sh traduz para o Claude Code.
import { realpathSync, statSync } from 'node:fs';
import { isAbsolute, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { inTempDir } from './closed-forms.mjs';

export const VERIFIER = /(^|:)review-verifier$/;

const NET = /(?<![\w-])(curl|wget|nc|ncat|netcat|socat|ssh|scp|sftp|rsync|telnet|ftp|tftp|Invoke-WebRequest|Invoke-RestMethod|iwr|irm|Start-BitsTransfer)(?![\w-])|\/dev\/(tcp|udp)\//i;
const SHELL_PIPE = /\|\s*(sudo\s+)?(sh|bash|zsh|dash|ksh|fish|pwsh|powershell|python3?|node|perl|ruby|iex|Invoke-Expression)(?![\w-])/i;
const ARBITRARY = /(?<![\w-])(eval|Invoke-Expression|iex)(?![\w-])|base64\s+(-d|--decode)|(?<![\w-])(ba|z|da|k)?sh\s+-c(?![\w-])|(?<![\w-])(source|\.)\s+<\(/i;

const TEST_RUNNER = [
  /^dotnet\s+(test|build)\b/, /^(npm|pnpm|yarn)\s+(test|run\s+test[\w:-]*)\b/,
  /^npx\s+(--no-install|--no)\s+(vitest|jest|playwright\s+test|mocha|tsc)\b/,
  /^cargo\s+test\b/, /^go\s+test\b/, /^(python3?\s+-m\s+)?pytest\b/, /^(mvn|\.\/mvnw)\s+test\b/, /^(gradle|\.\/gradlew)\s+test\b/,
];

// git de leitura: subcomando e flags listados um a um; o que não está aqui pede aprovação. need: flags obrigatórias
// (diff externo e textconv rodam comando configurado). Argumento sem "-" é revisão ou caminho; depois de "--", caminho.
const FORMAT = '--(format|pretty)=[%\\w.:,()\\[\\]-]+';
const GIT = {
  log: { need: ['--no-ext-diff', '--no-textconv'],
    ok: new RegExp(`^(--oneline|-n|-\\d+|--max-count=\\d+|-p|--patch|--stat|--name-only|--name-status|--follow|--no-merges|--no-ext-diff|--no-textconv|--no-color|${FORMAT})$`) },
  show: { need: ['--no-ext-diff', '--no-textconv'],
    ok: new RegExp(`^(--oneline|-s|--no-patch|--stat|--name-only|--name-status|--no-ext-diff|--no-textconv|--no-color|${FORMAT})$`) },
  blame: { need: ['--no-textconv'], ok: /^(-L|-L\d+(,[+-]?\d+)?|-w|-s|--no-textconv)$/ },
};
function gitRead(seg) {
  if (/['"\\]/.test(seg)) return false;
  const [git, sub, ...args] = seg.split(/\s+/);
  const rule = git === 'git' && Object.hasOwn(GIT, sub) ? GIT[sub] : null;
  if (!rule) return false;
  const end = args.indexOf('--');
  const flags = (end < 0 ? args : args.slice(0, end)).filter((a) => a.startsWith('-'));
  return flags.every((f) => rule.ok.test(f)) && rule.need.every((f) => flags.includes(f));
}

// git clone raso de uma URL https literal para a pasta temporária (inTempDir), para ler a fonte de uma dependência com
// Read e Grep: git clone --depth 1 [--single-branch] [--branch <nome>] https://<host>/<caminho> <pasta temporária>.
// O clone não executa código do repositório clonado (hooks não vêm no clone); a URL é texto fixo, sem expansão.
const CLONE = /^git +clone +--depth +1(?: +--single-branch)?(?: +(?:--branch|-b) +[A-Za-z0-9._\/-]+)? +(https:\/\/[A-Za-z0-9.-]+(?::443)?\/[A-Za-z0-9._~\/-]+) +(\/[A-Za-z0-9._\/+=:@-]+)$/;
function shallowClone(seg) {
  const m = CLONE.exec(seg);
  return !!m && !m[1].includes('..') && inTempDir(m[2]);
}

// node/bash de um arquivo do repositório: caminho relativo, sem "..", existente dentro do cwd depois de seguir symlink
function repoScript(seg, cwd) {
  const m = /^(node|bash)\s+(\S+)(\s|$)/.exec(seg);
  if (!m || m[2].startsWith('-')) return false;
  const p = m[2].replace(/^['"]|['"]$/g, '');
  if (isAbsolute(p) || p.startsWith('~') || p.split(/[\\/]/).includes('..')) return false;
  try {
    const root = realpathSync(cwd), full = realpathSync(resolve(cwd, p));
    const rel = relative(root, full);
    return !rel.startsWith('..') && !isAbsolute(rel) && statSync(full).isFile();
  } catch { return false; }
}

export function verdict(input) {
  let j;
  try { j = JSON.parse(input); } catch { return 'ASK entrada ilegível'; }
  const type = j?.agent_type;
  if (typeof type !== 'string' || !type) {
    return j?.agent_id ? 'ASK subagente sem agent_type: não dá para saber se é o review-verifier' : '';
  }
  if (!VERIFIER.test(type)) return '';
  const cmd = j?.tool_input?.command;
  if (typeof cmd !== 'string' || !cmd.trim()) return 'ASK comando ausente';
  const cwd = typeof j.cwd === 'string' && j.cwd ? j.cwd : process.cwd();
  const net = NET.exec(cmd), pipe = SHELL_PIPE.exec(cmd), arb = ARBITRARY.exec(cmd);
  const hit = net?.[0] || pipe?.[0] || arb?.[0];
  if (hit) return `DENY comando de prova com rede ou execução arbitrária (${hit.trim()}): a prova não roda (review-rubric, Limites da prova)`;
  if (/\$\(|`|<\(/.test(cmd)) return 'ASK comando de prova com substituição de comando: fora das formas conhecidas';
  const segs = cmd.split(/&&|\|\||;|\||\n|(?<![<>])&(?!>)/).map((s) => s.trim().replace(/\s+2>&1$/, '')).filter(Boolean);
  for (const raw of segs) {
    // no fim, um redirecionamento só para a pasta temporária da sessão (inTempDir: caminho real, fora do projeto, sem
    // symlink) ou para /dev/null, com 2>&1 opcional; qualquer outro > pede aprovação
    const red = /\s+(?:\d?>>?|&>)\s*(\/[A-Za-z0-9._/+=:@-]+)(?:\s+2>&1)?$/.exec(raw);
    const s = red && (red[1] === '/dev/null' || inTempDir(red[1])) ? raw.slice(0, red.index).trim() : raw;
    if (/>/.test(s)) return 'ASK comando de prova com redirecionamento fora da pasta temporária: fora das formas conhecidas';
    const ok = TEST_RUNNER.some((re) => re.test(s)) || gitRead(s) || repoScript(s, cwd) || shallowClone(s);
    if (!ok) return `ASK comando de prova fora das formas conhecidas (${s.split(/\s+/).slice(0, 2).join(' ')}): executor de teste, node/bash de arquivo do repositório, git log/show/blame com as flags liberadas; leia código com Read, Grep e Glob`;
  }
  return '';
}

// lê a entrada só quando roda como hook; importado (prove-verifier-guard.sh usa o VERIFIER), não toca a stdin
let main = false;
try { main = !!process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href; } catch { main = false; }
if (main) {
  let d = '';
  process.stdin.on('data', (c) => (d += c)).on('end', () => { process.stdout.write(verdict(d)); });
}
