// Comandos de Bash do review-verifier (PreToolUse em Bash; o agente vem em agent_type da entrada do hook). O verifier
// roda a `prova:` que uma lente escreveu, e a lente leu o código do projeto, que pode ser hostil ("prova: curl ... | sh").
// As regras de "sem rede" e "sem efeito fora do repositório" da review-rubric (Limites da prova) viram trava aqui:
//   DENY  rede (curl, wget, nc, ssh, Invoke-WebRequest...), pipe para interpretador (| sh, | bash, | node...), eval,
//         base64 -d, bash -c / sh -c, /dev/tcp
//   livre as formas conhecidas de prova: executor de teste (dotnet test, npm test, npx vitest, cargo test, go test,
//         pytest...), node/bash de arquivo dentro do repositório, git de leitura, grep, rg e leitura simples
//   ASK   o resto, inclusive node -e e substituição de comando ($(...), crase, <(...))
// Outros agentes e a sessão principal: sem veredito (os outros hooks seguem valendo). Não é fronteira: um comando montado
// para esconder passa, como nas outras travas por texto; tira a execução arbitrária do caminho padrão.
// Saída: '' (sem veredito), "DENY <motivo>" ou "ASK <motivo>"; o verifier-guard.sh traduz para o Claude Code.
import { existsSync, statSync } from 'node:fs';
import { isAbsolute, join, relative, resolve } from 'node:path';

export const VERIFIER = /(^|:)review-verifier$/;

const NET = /(?<![\w-])(curl|wget|nc|ncat|netcat|socat|ssh|scp|sftp|rsync|telnet|ftp|tftp|Invoke-WebRequest|Invoke-RestMethod|iwr|irm|Start-BitsTransfer)(?![\w-])|\/dev\/(tcp|udp)\//i;
const SHELL_PIPE = /\|\s*(sudo\s+)?(sh|bash|zsh|dash|ksh|fish|pwsh|powershell|python3?|node|perl|ruby|iex|Invoke-Expression)(?![\w-])/i;
const ARBITRARY = /(?<![\w-])(eval|Invoke-Expression|iex)(?![\w-])|base64\s+(-d|--decode)|(?<![\w-])(ba|z|da|k)?sh\s+-c(?![\w-])|(?<![\w-])(source|\.)\s+<\(/i;

const TEST_RUNNER = [
  /^dotnet\s+(test|build)\b/, /^(npm|pnpm|yarn)\s+(test|run\s+test[\w:-]*)\b/, /^npx\s+(vitest|jest|playwright\s+test|mocha|tsc)\b/,
  /^cargo\s+test\b/, /^go\s+test\b/, /^(python3?\s+-m\s+)?pytest\b/, /^(mvn|\.\/mvnw)\s+test\b/, /^(gradle|\.\/gradlew)\s+test\b/,
];
const READ_ONLY = [
  /^git\s+(log|diff|show|grep|blame|status|ls-files|rev-parse|cat-file)\b/, /^(grep|rg|cat|head|tail|wc|ls|sort|uniq|jq)\b/,
  /^sed\s+-n\b(?!.*\s-i)/, /^find\b(?!.*\s-(exec|execdir|delete|ok|okdir|fprint\w*|fls))/,
];

// node/bash de um arquivo do repositório: caminho relativo, sem "..", existente dentro do cwd
function repoScript(seg, cwd) {
  const m = /^(node|bash)\s+(\S+)(\s|$)/.exec(seg);
  if (!m || m[2].startsWith('-')) return false;
  const p = m[2].replace(/^['"]|['"]$/g, '');
  if (isAbsolute(p) || p.startsWith('~') || p.split(/[\\/]/).includes('..')) return false;
  const full = resolve(cwd, p);
  const rel = relative(cwd, full);
  if (rel.startsWith('..') || isAbsolute(rel)) return false;
  try { return existsSync(full) && statSync(full).isFile(); } catch { return false; }
}

export function verdict(input) {
  let j;
  try { j = JSON.parse(input); } catch { return 'ASK entrada ilegível'; }
  if (!VERIFIER.test(String(j?.agent_type ?? ''))) return '';
  const cmd = j?.tool_input?.command;
  if (typeof cmd !== 'string' || !cmd.trim()) return 'ASK comando ausente';
  const cwd = typeof j.cwd === 'string' && j.cwd ? j.cwd : process.cwd();
  const net = NET.exec(cmd), pipe = SHELL_PIPE.exec(cmd), arb = ARBITRARY.exec(cmd);
  const hit = net?.[0] || pipe?.[0] || arb?.[0];
  if (hit) return `DENY comando de prova com rede ou execução arbitrária (${hit.trim()}): a prova não roda (review-rubric, Limites da prova)`;
  if (/\$\(|`|<\(/.test(cmd)) return 'ASK comando de prova com substituição de comando: fora das formas conhecidas';
  const segs = cmd.split(/&&|\|\||;|\||\n/).map((s) => s.trim().replace(/\s+2>&1$/, '')).filter(Boolean);
  for (const s of segs) {
    if (/>/.test(s)) return 'ASK comando de prova com redirecionamento: fora das formas conhecidas';
    const ok = TEST_RUNNER.some((re) => re.test(s)) || READ_ONLY.some((re) => re.test(s)) || repoScript(s, cwd);
    if (!ok) return `ASK comando de prova fora das formas conhecidas (${s.split(/\s+/).slice(0, 2).join(' ')}): executor de teste, node/bash de arquivo do repositório, git de leitura, grep, rg`;
  }
  return '';
}

let d = '';
process.stdin.on('data', (c) => (d += c)).on('end', () => { process.stdout.write(verdict(d)); });
