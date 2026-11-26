#!/usr/bin/env node
// Confere um texto em português (mensagem de commit, descrição de PR, documentação) contra os padrões da skill unslop:
// erro é padrão que sempre sai (abertura vazia, autorreferência "este commit", muleta de ênfase, gerundismo, "a nível
// de", "o mesmo" como pronome, emoji); aviso é palavra suspeita que só fica se disser algo concreto.
// Ignora código entre crases, menção entre aspas duplas, blocos de código cercados e as linhas de rodapé do commit
// (Co-Authored-By:, Refs: ...).
// Uso: node slop-check.mjs [--pr] <arquivo>
// --pr: o arquivo é o corpo de um pull request (skill commit, Pull request). Além dos padrões, confere as seções "## ":
//   só as conhecidas, nesta ordem e sem repetir: Por quê, O que mudou, Escopo, Trade-offs, Raio de impacto, Verificação;
//   Por quê e Verificação obrigatórias; seção sem conteúdo é erro; mais de 40 linhas com texto é erro. O rodapé de
//   atribuição (da linha "🤖 Generated with" em diante) fica fora da conferência.
// Saída: "<linha>: erro|aviso: <padrão> — <troca>", uma por ocorrência; o texto da linha não é impresso (o hook
// script-allow aprova este script sem pedido, e o conteúdo de um arquivo protegido não pode sair por ele).
// Código: 0 sem erro (avisos podem existir), 3 algum erro, 2 uso errado ou arquivo ilegível.
import { readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const pr = args[0] === '--pr';
const [file, extra] = pr ? args.slice(1) : args;
if (!file || extra || file.startsWith('--')) { console.error('uso: slop-check.mjs [--pr] <arquivo>'); process.exit(2); }
let text;
try { text = readFileSync(file, 'utf8'); } catch (e) { console.error(`slop-check: não foi possível ler: ${e.code ?? e.message}`); process.exit(2); }

// Fronteira de palavra que entende acento (o \b do JavaScript não entende).
const B = '(?<![\\p{L}\\p{N}_])', E = '(?![\\p{L}\\p{N}_])';
const w = (src) => new RegExp(`${B}(?:${src})${E}`, 'iu');

const ERRORS = [
  [/^\s*(?:claro|certo|com certeza|ótima pergunta|perfeito)\s*[!,.:]/iu, 'abertura vazia', 'começar pelo conteúdo'],
  [w('espero (?:ter ajudado|que (?:isso|isto) ajude)|qualquer dúvida|fico à disposição|estou à disposição'), 'fecho vazio', 'cortar'],
  [w('(?:n?este|n?esta|n?esse|n?essa) (?:commit|pr|pull request|mudança tem como objetivo)'), 'autorreferência', 'começar pelo motivo ou pelo efeito'],
  [w('(?:é|seria) (?:importante|fundamental|essencial) (?:ressaltar|notar|destacar|mencionar|lembrar|observar) que|vale (?:ressaltar|destacar|lembrar|mencionar|notar) que|cabe (?:ressaltar|destacar|mencionar) que'), 'muleta de ênfase', 'dizer a coisa'],
  [w('em resumo|em suma|por fim, mas não menos importante'), 'fecho de redação', 'cortar'],
  [w('a nível de'), '"a nível de"', '"em", ou "no nível de" quando há níveis'],
  [w('(?:vou|vamos|vai|vão|irá|irão|estarei|estaremos) estar [\\p{L}]+ndo'), 'gerundismo', 'verbo direto: "vou fazer"'],
  [w('(?:o|a|os|as) mesm[oa]s? (?:foi|foram|é|são|está|estão|será|serão|deve|devem|precisa|precisam|pode|podem)'), '"o mesmo" como pronome', 'ele, ela ou o nome da coisa'],
  [/\p{Extended_Pictographic}/u, 'emoji', 'cortar'],
];
const WARNINGS = [
  [w('robust[oa]s?|abrangentes?|eficientes?|de forma (?:eficaz|eficiente|robusta|transparente|fluida|significativa)'), 'adjetivo vago', 'o que concretamente aguenta, cobre ou economiza'],
  [w('crucia(?:l|is)|fundamenta(?:l|is)|essencia(?:l|is)'), 'ênfase vaga', 'o que quebra sem isso'],
  [w('otimiz\\p{L}*|significativamente|consideravelmente'), 'ganho sem número', 'o número: antes e depois'],
  [w('aprimor\\p{L}*|potencializ\\p{L}*|alavanc\\p{L}*|mergulh\\p{L}*'), 'verbo inflado', 'melhorar, usar, ou o verbo do que acontece'],
  [w('realiz(?:a|ar|ado|ada|ados|adas|ou|amos|aram) (?:a|o|as|os) '), '"realizar" + substantivo', 'o verbo: validar, processar'],
  [w('endereç\\p{L}*'), '"endereçar" (address)', 'tratar, resolver'],
  [w('perform(?:ar|a|ou|am|ando)'), '"performar"', 'ter desempenho, rodar, responder em'],
  [w('através d[eoa]s?'), '"através de"', 'por, por meio de, com'],
  [w('visando|com o intuito de|sendo que'), 'conector rebuscado', 'para; e, mas, porque'],
  [w('não (?:só|apenas|somente) [^.]{1,80}?, mas também'), '"não apenas..., mas também"', 'X e Y'],
  [w('basicamente|simplesmente|atualmente'), 'enchimento', 'cortar'],
  [w('jornada|ecossistema|seamless|game.changer'), 'palavra de marketing', 'o nome da coisa'],
];
const TRAILER = /^(?:Co-Authored-By|Claude-Session|Signed-off-by|Refs|Closes|Fixes|BREAKING CHANGE|Reviewed-by):/i;

let errors = 0, warnings = 0, fenced = false;
let lines = text.split(/\r?\n/);
if (pr) {
  // rodapé de atribuição do PR: fora dos padrões (tem emoji de propósito) e da contagem
  const foot = lines.findIndex((l) => /^\s*🤖 Generated with/.test(l));
  if (foot >= 0) lines = lines.slice(0, foot);
  const SECTIONS = ['Por quê', 'O que mudou', 'Escopo', 'Trade-offs', 'Raio de impacto', 'Verificação'];
  const err = (n, msg) => { console.log(`${n}: erro: ${msg}`); errors++; };
  let last = -1, inFence = false;
  const seen = new Set();
  const heads = [];
  lines.forEach((l, i) => {
    if (/^\s*(```|~~~)/.test(l)) inFence = !inFence;
    if (inFence) return;
    const m = /^##\s+(.+?)\s*$/.exec(l);
    if (!m || l.startsWith('###')) return;
    heads.push(i);
    const k = SECTIONS.indexOf(m[1]);
    if (k < 0) err(i + 1, `seção desconhecida no PR — use só ${SECTIONS.join(', ')}`);
    else if (seen.has(k)) err(i + 1, 'seção repetida no PR — juntar numa só');
    else if (k < last) err(i + 1, `seção fora de ordem no PR — a ordem é ${SECTIONS.join(', ')}`);
    if (k >= 0) { seen.add(k); last = Math.max(last, k); }
  });
  heads.forEach((h, j) => {
    const end = j + 1 < heads.length ? heads[j + 1] : lines.length;
    if (!lines.slice(h + 1, end).some((l) => l.trim())) err(h + 1, 'seção vazia no PR — tirar a seção');
  });
  for (const [k, name] of [[0, 'Por quê'], [5, 'Verificação']]) if (!seen.has(k)) err(1, `seção obrigatória ausente no PR: ## ${name}`);
  const filled = lines.filter((l) => l.trim()).length;
  if (filled > 40) err(1, `PR com ${filled} linhas de texto (máximo 40) — logs, tabelas e listas longas vão para o relatório`);
}
lines.forEach((raw, i) => {
  if (/^\s*(```|~~~)/.test(raw)) { fenced = !fenced; return; }
  if (fenced || TRAILER.test(raw.trim())) return;
  // código entre crases e menção entre aspas duplas ("este commit" citado como exemplo) não são uso
  const line = raw.replace(/`[^`]*`/g, ' ').replace(/"[^"\n]*"|“[^”\n]*”/g, ' ');
  for (const [re, name, fix] of ERRORS) if (re.test(line)) { console.log(`${i + 1}: erro: ${name} — ${fix}`); errors++; }
  for (const [re, name, fix] of WARNINGS) if (re.test(line)) { console.log(`${i + 1}: aviso: ${name} — ${fix}`); warnings++; }
});
console.error(`slop-check: ${errors} erro(s), ${warnings} aviso(s)`);
process.exit(errors ? 3 : 0);
