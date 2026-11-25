#!/usr/bin/env node
// Interrogatório do diff por modelos de outro fornecedor (skill lead, reference/revisao.md, etapa 2): cada modelo
// configurado recebe o pacote de revisão com a instrução de quebrar o diff e devolve candidatos no formato da
// review-rubric. A saída segue o caminho das outras lentes: check-findings.mjs (ancoragem) e depois o review-verifier.
// Um modelo ataca; o verificador confirma ou refuta.
// Uso: node interrogate.mjs <pacote> <saída>
//   <pacote>: arquivo com o diff dos arquivos que o review-dispatch.mjs manda a revisor, o contrato e os pontos de foco
//   <saída>: candidatos de todos os modelos, com o id prefixado pelo nome do modelo (ou "sem achados"); a resposta
//            bruta de cada modelo fica em <saída>.<nome>.bruto
// .claude/risk.conf do projeto:
//   interrogate_cmd = <nome> <comando>   um por modelo; o comando roda com bash -c na raiz do projeto, lê o pedido da
//                                        entrada padrão e escreve a resposta na saída padrão
//   interrogate_timeout = <segundos>     prazo por modelo (padrão 600)
// Ligar é decisão do projeto: o pacote sai da máquina para o fornecedor do modelo (docs/decisions.md do projeto).
// Código: 0 todos responderam; 10 nada configurado; 3 algum modelo falhou, esgotou o prazo ou respondeu fora do
// formato (a saída traz os que responderam); 2 uso errado.
import { execFileSync, spawn } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { confValues } from '../hooks/risk-conf.mjs';

const die = (code, msg) => { console.error(`interrogate: ${msg}`); process.exit(code); };
const [pkgPath, outPath, extra] = process.argv.slice(2);
if (!pkgPath || !outPath || extra) die(2, 'uso: interrogate.mjs <pacote> <saída>');

const models = [];
for (const line of confValues('interrogate_cmd')) {
  const m = /^([a-z0-9][a-z0-9-]{0,31})\s+(\S.*)$/.exec(line);
  if (!m) die(2, `interrogate_cmd inválido no risk.conf: "<nome> <comando>", nome em [a-z0-9-] (${line})`);
  if (models.some((x) => x.name === m[1])) die(2, `interrogate_cmd: nome repetido (${m[1]})`);
  models.push({ name: m[1], cmd: m[2] });
}
if (!models.length) { console.error('interrogate: nenhum interrogate_cmd no risk.conf (não configurado)'); process.exit(10); }
const tv = confValues('interrogate_timeout').at(-1);
const timeoutS = tv === undefined ? 600 : Number(tv);
if (!Number.isInteger(timeoutS) || timeoutS < 1) die(2, `interrogate_timeout inválido: ${tv}`);

let pkg;
try { pkg = readFileSync(pkgPath, 'utf8'); } catch (e) { die(2, `não foi possível ler o pacote: ${e.code ?? e.message}`); }
if (!pkg.trim()) die(2, 'pacote vazio');

let root = process.env.CLAUDE_PROJECT_DIR;
if (!root) {
  try { root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
  catch { die(2, 'fora de repositório git'); }
}

const PROMPT = `Você é um revisor adversarial. Seu papel é quebrar a mudança abaixo: achar a entrada, o estado ou a
sequência que a faz produzir resultado errado, perder dado, vazar dado, travar ou violar o contrato descrito.

Regras:
- Só reporte o que tem um cenário concreto: entrada ou estado → resultado errado. Opinião, estilo, nome e
  formatação não são achado.
- Pense em: limites e valores vazios, nulos, repetidos e enormes; concorrência e reentrada; falha no meio de
  uma operação; retry e duplicação; autorização e dado de outro usuário ou tenant; compatibilidade com quem
  já usa o contrato; o que o teste novo deixa de provar.
- "trecho" é a linha exata do código em "local", copiada do diff sem alterar (sem o "+" do começo). Achado
  com trecho que não existe no arquivo é descartado automaticamente.
- No máximo 10 achados, os mais graves primeiro. Sem achado com cenário concreto, responda exatamente: sem achados
- Responda só a lista, sem texto antes ou depois, neste formato:

- id: interrogate-<n>
  categoria: correctness | error-handling | domain | tests | security | performance | contract
  severidade: bloqueante | importante | nit
  confiança: <0-100>
  local: <arquivo:linha>
  trecho: |
    <linha exata do código em local>
  evidência: <arquivo:linha> — <o que o código faz, trecho curto>
  cenário: <entrada ou estado> → <resultado errado>
  correção mínima: <mudança>
  preexistente: sim | não

A mudança (diff, contrato e pontos de foco):

`;

function ask({ name, cmd }) {
  return new Promise((resolve) => {
    // grupo de processos próprio: no prazo, mata o comando e os filhos dele (um filho vivo seguraria a saída aberta)
    const child = spawn('bash', ['-c', cmd], { cwd: root, stdio: ['pipe', 'pipe', 'pipe'], detached: true });
    let out = '', err = '', timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
    }, timeoutS * 1000);
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.stdin.on('error', () => {});
    child.on('error', (e) => { clearTimeout(timer); resolve({ name, out, problem: `não executou (${e.code ?? e.message})` }); });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (timedOut) return resolve({ name, out, problem: `esgotou o prazo de ${timeoutS}s` });
      if (code !== 0) return resolve({ name, out, problem: `saiu com código ${code}: ${err.trim().split('\n').at(-1) ?? ''}` });
      resolve({ name, out, problem: null });
    });
    child.stdin.end(PROMPT + pkg);
  });
}

const results = await Promise.all(models.map(ask));
const blocks = [];
let failed = 0;
for (const r of results) {
  writeFileSync(`${outPath}.${r.name}.bruto`, r.out);
  let status = r.problem;
  if (!status) {
    const start = r.out.search(/^\s*-\s+id:/m);
    if (start >= 0) {
      const items = r.out.slice(start).replace(/^(\s*-\s+id:\s*)/gm, `$1${r.name}-`).trimEnd();
      blocks.push(items);
      status = `${(items.match(/^\s*-\s+id:/gm) ?? []).length} candidato(s)`;
    } else if (/^\s*sem achados\s*$/i.test(r.out)) status = 'sem achados';
    else { status = 'resposta fora do formato da review-rubric'; failed++; }
  } else failed++;
  console.error(`interrogate: ${r.name} — ${status}`);
}
writeFileSync(outPath, blocks.length ? `${blocks.join('\n')}\n` : 'sem achados\n');
process.exit(failed ? 3 : 0);
