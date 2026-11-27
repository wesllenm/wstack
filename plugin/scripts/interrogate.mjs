#!/usr/bin/env node
// Interrogatório do diff por modelos de outro fornecedor (skill lead, reference/revisao.md, etapa 2): cada modelo
// configurado recebe o pacote de revisão com a instrução de quebrar o diff e devolve candidatos no formato da
// review-rubric. A saída segue o caminho das outras lentes: check-findings.mjs (ancoragem) e depois o review-verifier.
// Um modelo ataca; o verificador confirma ou refuta.
// Uso: node interrogate.mjs <pacote> <saída>
//   <pacote>: arquivo com o diff dos arquivos que o review-dispatch.mjs manda a revisor, o contrato e os pontos de foco
//   <saída>: candidatos de todos os modelos, com o id prefixado pelo nome do modelo e a linha final "status: achados"
//            (ou "sem achados"); a resposta bruta de cada modelo fica em <saída>.<nome>.bruto
// .claude/risk.conf do projeto:
//   interrogate_cmd = <nome> <comando>   um por modelo; o comando roda com bash -c na raiz do projeto, lê o pedido da
//                                        entrada padrão e escreve a resposta na saída padrão
//   interrogate_timeout = <segundos>     prazo por modelo (padrão 600)
// Ligar é decisão do projeto: o pacote sai da máquina para o fornecedor do modelo (docs/decisions.md do projeto).
// Só passam itens com categoria, severidade, local, trecho e cenário; prosa antes ou depois da lista é cortada.
// Saída quando nenhum modelo respondeu dentro do formato: "falhou: <modelo — motivo>; ...", nunca "sem achados" (um
// interrogatório que não aconteceu não pode passar por um que não achou nada).
// Código: 0 todos responderam; 10 nada configurado; 3 algum modelo falhou, esgotou o prazo ou respondeu fora do
// formato, e outro respondeu (a saída traz os que responderam); 4 nenhum modelo respondeu (a saída é "falhou: ...");
// 2 uso errado, pacote ilegível ou pasta de saída sem escrita.
import { execFileSync, spawn } from 'node:child_process';
import { accessSync, constants, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
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

// A pasta da saída precisa existir e aceitar escrita antes de gastar a chamada aos modelos.
try { accessSync(dirname(outPath), constants.W_OK); } catch (e) { die(2, `pasta da saída sem escrita: ${e.code ?? e.message}`); }
const write = (p, text) => { try { writeFileSync(p, text); } catch (e) { die(2, `não foi possível gravar ${p}: ${e.code ?? e.message}`); } };

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
  prova: <comando que reproduz a falha no projeto, como um teste existente com filtro>
  esperado: <a saída que mostra a falha>
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
    // decodifica na fronteira de caractere: um caractere UTF-8 de vários bytes pode chegar partido entre dois pedaços
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
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

// Campos que todo candidato precisa ter (review-rubric, Formato do candidato); o resto é opcional para o verificador.
const REQUIRED = ['categoria', 'severidade', 'local', 'trecho', 'cenário'];
// "sem achados", com ponto, exclamação, crases, aspas ou negrito em volta: modelo de outro fornecedor pontua.
const NONE = /^[\s*_`"']*sem achados[.!]?[\s*_`"']*$/i;

// Itens da lista: do primeiro "- id:" em diante, linhas de item ("- id:") e linhas recuadas (campos e continuação do
// trecho); linha em branco entre itens é tolerada; a primeira linha sem recuo que não abre item encerra a lista (prosa
// depois da lista fica de fora). Cada item precisa dos campos obrigatórios.
function parse(text) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => /^\s*-\s+id:/.test(l));
  if (start < 0) return null;
  const items = [];
  for (const l of lines.slice(start)) {
    if (/^\s*-\s+id:/.test(l)) items.push([l]);
    else if (/^\s{2,}\S/.test(l)) items.at(-1).push(l);
    else if (l.trim() !== '') break;
  }
  const valid = items.filter((it) => REQUIRED.every((k) => it.some((l) => new RegExp(`^\\s{1,3}${k}:`, 'iu').test(l))));
  return { valid, dropped: items.length - valid.length };
}

const results = await Promise.all(models.map(ask));
const blocks = [];
const failures = []; // "<modelo> — <motivo>"
let failed = 0;
for (const r of results) {
  write(`${outPath}.${r.name}.bruto`, r.out);
  let status = r.problem;
  if (!status) {
    const p = parse(r.out);
    if (p && p.valid.length) {
      blocks.push(p.valid.map((it) => it.join('\n').replace(/^(\s*-\s+id:\s*)/, `$1${r.name}-`)).join('\n'));
      status = `${p.valid.length} candidato(s)${p.dropped ? `, ${p.dropped} sem campo obrigatório descartado(s)` : ''}`;
    } else if (p) { status = `${p.dropped} candidato(s), todos sem campo obrigatório (${REQUIRED.join(', ')})`; failed++; }
    else if (NONE.test(r.out)) status = 'sem achados';
    else { status = 'resposta fora do formato da review-rubric'; failed++; }
  } else failed++;
  if (failed > failures.length) failures.push(`${r.name} — ${status}`);
  console.error(`interrogate: ${r.name} — ${status}`);
}
if (failed === results.length) {
  write(outPath, `falhou: ${failures.join('; ')}\n`);
  process.exit(4);
}
// a linha de status fecha a lista, como nas lentes: o check-findings.mjs trata resposta sem ela como lacuna
write(outPath, blocks.length ? `${blocks.join('\n')}\nstatus: achados\n` : 'sem achados\n');
process.exit(failed ? 3 : 0);
