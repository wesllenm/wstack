// Comandos de Bash do review-verifier (PreToolUse em Bash; o agente vem em agent_type da entrada do hook). O verifier
// roda a `prova:` que uma lente escreveu, e a lente leu o código do projeto, que pode ser hostil ("prova: curl ... | sh").
// As regras de "sem rede" e "sem efeito fora do repositório" da review-rubric (Limites da prova) viram trava aqui:
//   DENY  rede (curl, wget, nc, ssh, Invoke-WebRequest...), pipe para interpretador (| sh, | bash, | node...), eval,
//         base64 -d, bash -c / sh -c, /dev/tcp
//   livre as formas conhecidas de prova: executor de teste (dotnet test, npm test, npx vitest, cargo test, go test,
//         pytest...), node/bash de arquivo dentro do repositório, git de leitura, grep, rg e leitura simples
//   ASK   o resto, inclusive node -e e substituição de comando ($(...), crase, <(...))
//   DENY  também as opções de leitura que escrevem ou executam: sort -o/--output/--compress-program, rg --pre, sed -i
// Outros agentes e a sessão principal: sem veredito (os outros hooks seguem valendo). Subagente sem agent_type (agent_id
// presente, agent_type ausente): pede aprovação, porque não dá para saber se é o verifier. A sessão principal não manda
// nenhum dos dois, e o prove-verifier-guard.sh confere isso com o Claude Code real. Não é fronteira: um comando montado
// para esconder passa, como nas outras travas por texto; tira a execução arbitrária do caminho padrão.
// Saída: '' (sem veredito), "DENY <motivo>" ou "ASK <motivo>"; o verifier-guard.sh traduz para o Claude Code.
import { realpathSync, statSync } from 'node:fs';
import { isAbsolute, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const VERIFIER = /(^|:)review-verifier$/;

const NET = /(?<![\w-])(curl|wget|nc|ncat|netcat|socat|ssh|scp|sftp|rsync|telnet|ftp|tftp|Invoke-WebRequest|Invoke-RestMethod|iwr|irm|Start-BitsTransfer)(?![\w-])|\/dev\/(tcp|udp)\//i;
const SHELL_PIPE = /\|\s*(sudo\s+)?(sh|bash|zsh|dash|ksh|fish|pwsh|powershell|python3?|node|perl|ruby|iex|Invoke-Expression)(?![\w-])/i;
const ARBITRARY = /(?<![\w-])(eval|Invoke-Expression|iex)(?![\w-])|base64\s+(-d|--decode)|(?<![\w-])(ba|z|da|k)?sh\s+-c(?![\w-])|(?<![\w-])(source|\.)\s+<\(/i;

// opções de comandos de leitura que escrevem fora do repositório ou executam um programa (GNU aceita abreviar a opção longa)
const WRITE_EXEC = [
  [/^sort\b.*\s(-[a-zA-Z]*o|--(o|co)[\w-]*)/, 'sort -o, --output ou --compress-program'],
  [/^rg\b.*\s--pre(=|\s|$)/, 'rg --pre'],
  [/^sed\b.*\s(-[a-zA-Z]*i|--i[\w-]*)/, 'sed -i ou --in-place'],
];
const TEST_RUNNER = [
  /^dotnet\s+(test|build)\b/, /^(npm|pnpm|yarn)\s+(test|run\s+test[\w:-]*)\b/,
  /^npx\s+(--no-install|--no)\s+(vitest|jest|playwright\s+test|mocha|tsc)\b/,
  /^cargo\s+test\b/, /^go\s+test\b/, /^(python3?\s+-m\s+)?pytest\b/, /^(mvn|\.\/mvnw)\s+test\b/, /^(gradle|\.\/gradlew)\s+test\b/,
];
// git diff, show e log só com --no-ext-diff e --no-textconv, e blame com --no-textconv: diff externo e textconv rodam
// comando configurado. sed -n só com endereço de linha e p (sem w, W, e nem -e/-f depois do script).
const READ_ONLY = [
  /^git\s+(diff|show|log)\b(?=.*\s--no-ext-diff\b)(?=.*\s--no-textconv\b)/, /^git\s+blame\b(?=.*\s--no-textconv\b)/,
  /^git\s+(grep|status|ls-files|rev-parse|cat-file)\b/, /^(grep|rg|cat|head|tail|wc|ls|sort|uniq|jq)\b/,
  /^sed\s+-n\s+(['"]?)[\d,$;p]+\1(\s+[^-\s]\S*)*$/, /^find\b(?!.*\s-(exec|execdir|delete|ok|okdir|fprint\w*|fls))/,
];

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
  for (const s of segs) {
    const we = WRITE_EXEC.find(([re]) => re.test(s));
    if (we) return `DENY comando de prova que escreve ou executa (${we[1]}): a prova não roda (review-rubric, Limites da prova)`;
    if (/>/.test(s)) return 'ASK comando de prova com redirecionamento: fora das formas conhecidas';
    const ok = TEST_RUNNER.some((re) => re.test(s)) || READ_ONLY.some((re) => re.test(s)) || repoScript(s, cwd);
    if (!ok) return `ASK comando de prova fora das formas conhecidas (${s.split(/\s+/).slice(0, 2).join(' ')}): executor de teste, node/bash de arquivo do repositório, git de leitura, grep, rg`;
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
