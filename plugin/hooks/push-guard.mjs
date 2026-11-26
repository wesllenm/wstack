// Veredito do push-guard.sh para cada comando Bash (payload do PreToolUse na entrada padrão). Imprime uma linha:
//   OK                 não é push, ou é push na forma exata permitida (o allow do settings.json decide o resto)
//   ASK <motivo>       push que só o desenvolvedor aprova: o hook força o pedido de permissão mesmo se o allow casar
//   DENY <motivo>      push que nem com aprovação passa por aqui (main, force puro, apagar, injeção de config)
// O comando é dividido em subcomandos respeitando aspas (texto entre aspas, como uma mensagem de commit, nunca é
// lido como push). Só um subcomando que COMEÇA por git [-C dir] push é avaliado. Forma que o hook não consegue
// ler com segurança (aspas, $, crase, chaves, heredoc, comentário, barra no fim de linha num comando com push) vira
// ASK, nunca OK. Limite: push indireto (bash -c, eval, script) não é visto aqui e cai no pedido de permissão normal.
// Push na forma permitida que publica mudança em caminho protegido (protected-paths.mjs) também é ASK, com a lista; sem
// origin/<branch padrão> ou sem merge-base, ASK (falha fechada).
// De onde vem cada valor (.claude/risk.conf do projeto dos hooks, risk-conf.mjs): os prefixos de branch de atividade
// (activity_branch = <prefixo>/, um por linha) e as branches padrão recusadas (default_branch); main e master são sempre
// recusadas, e o ccr-<id>-<id> da nuvem da Anthropic e o wip/ do checkpoint são embutidos. Valor fora do alfabeto fechado é
// ignorado e nunca entra numa regex; sem nenhum prefixo válido, só o ccr- e o wip/ passam sem pedir.
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { foreignRepo, git, left, projectRepo } from './git-repo.mjs';
import { commitOf, defaultBranches, exactRefCommit, list, protectedChanged } from './protected-paths.mjs';
import { confAbsent, confValues } from './risk-conf.mjs';

let d = '';
process.stdin.on('data', (c) => (d += c)).on('end', () => {
  let j;
  try { j = JSON.parse(d); } catch { out('ASK payload ilegível'); return; }
  out(verdict(String(j?.tool_input?.command ?? ''), String(j?.cwd ?? process.cwd())));
});
function out(v) { process.stdout.write(v); }
// Branches de atividade (os prefixos do risk.conf), mais a que a sessão da nuvem impõe (ccr-<id>-<id>, só minúsculas e dígitos,
// sem barra nem ponto). O prefixo começa por letra ou dígito: um "-" inicial seria lido pelo git como opção. Espaço de nome
// do git (refs, heads, tags, remotes) não vale como prefixo: o destino seria lido como ref de outro tipo (refs/tags/v1).
const PREFIX = /^([A-Za-z0-9][A-Za-z0-9._-]*)\/$/;
const GIT_NAMESPACE = /^(?:refs|heads|tags|remotes)$/i;
const prefixes = confValues('activity_branch').map((v) => PREFIX.exec(v)).filter((m) => m && !GIT_NAMESPACE.test(m[1])).map((m) => m[1].replace(/\./g, '\\.'));
// Projeto sem risk.conf (não adotou o wstack, confAbsent): toda branch que não é a padrão conta como de atividade. O hook
// só deixa de forçar o pedido; o resto (padrão recusada, force, o que o push publica em caminho protegido) continua. Nome
// que começa por espaço de nome do git (refs/, heads/, tags/, remotes/, em qualquer caixa) não é branch: tag, nota e ref de
// rastreio continuam pedindo, como o GIT_NAMESPACE faz com os prefixos declarados.
// Calculado só quando o comando tem push: o confAbsent roda git, e o hook roda em todo comando Bash.
let rules;
function R() {
  if (rules) return rules;
  const ACTIVITY = confAbsent()
    ? '(?![Rr][Ee][Ff][Ss]/|[Hh][Ee][Aa][Dd][Ss]/|[Tt][Aa][Gg][Ss]/|[Rr][Ee][Mm][Oo][Tt][Ee][Ss]/)[A-Za-z0-9][A-Za-z0-9._/-]*'
    : [...(prefixes.length ? [`(?:${prefixes.join('|')})/[A-Za-z0-9._/-]+`] : []), 'ccr-[a-z0-9]+-[a-z0-9]+'].join('|');
  const DST = `(?:refs/heads/)?(?:${ACTIVITY})`;
  const SPEC = `(?:(?:${P}:)?${DST}|${P}:refs/heads/wip/[A-Za-z0-9._-]+)`;
  rules = {
    ACT: new RegExp(`^(?:${ACTIVITY})$`),
    NEVER: new Set(['main', 'master', ...defaultBranches()]), // recusadas para push, nem com aprovação
    STRICT: new RegExp(`^git(?: +-C +(${DIR}))? +push(?: +${FLAG})* +origin((?: +${SPEC})+)(?: +${REDIR})*(?: *\\| *tail +-n? *[0-9]+)?$`),
  };
  return rules;
}
const WIP = /^refs\/heads\/wip\/[A-Za-z0-9._-]+$/;
const SAFE = /^[A-Za-z0-9._\/:-]+$/; // nenhum caractere que o shell expanda
const OKFLAGS = new Set(['-u', '--set-upstream', '-q', '--quiet', '-v', '--verbose', '--porcelain', '--dry-run', '-n']);
const ASKFLAGS = /^--force-with-lease(=.*)?$|^--force-if-includes$/;

// Única forma que sai OK: o comando INTEIRO neste formato fechado (sem cadeia, sem expansão, redirecionamento só para
// caminho literal, no máximo um "| tail -N" no fim). O tokenizador abaixo só serve para RECUSAR o que é óbvio; um
// comando com git push que não seja exatamente este formato vira ASK. Assim um buraco no tokenizador degrada para
// pedido de permissão, nunca para push liberado (três buracos da gramática do bash apareceram na revisão).
// Só espaço literal (o \\s do JS aceita quebra de linha, que o bash trata como outro comando); nenhum token do
// refspec começa por "-" (-fo:x seria lido pelo git como -f -o); redirecionamento só para /dev/null ou /tmp/.
const P = '[A-Za-z0-9._][A-Za-z0-9._/-]*';
const FLAG = '(?:-u|--set-upstream|-q|--quiet|-v|--verbose|--porcelain|--dry-run|-n)';
const SINK = '(?:/dev/null|/tmp/[A-Za-z0-9._/-]+)';
const REDIR = `(?:[12]?>&[12]|&>>? *${SINK}|[12]?>>? *${SINK})`;
const DIR = '[A-Za-z0-9._/][A-Za-z0-9._/-]*';

function verdict(cmd, cwd) {
  // o bash junta barra + quebra de linha antes de ler o comando: "pu\<LF>sh" é push, e "git \<LF>push" escaparia do
  // formato fechado e da busca de git ... push, que não atravessam a quebra
  const joined = cmd.replace(/\\\r?\n/g, '');
  if (!/\bpush\b/.test(joined)) return 'OK';
  const v = scan(cmd, cwd);
  if (v.startsWith('DENY')) return v;
  // Turno encerrado pela exceção de verificação (o Stop grava .claude/.session/unverified-<sessão>; só um Stop da mesma
  // sessão em que o build e os testes rodaram e passaram o apaga): nada sem verificação sai num push que vira PR. Fica o checkpoint wip/, que não vira PR. Recusa,
  // não pergunta: na nuvem ninguém responde, e a aprovação da exceção não é aprovação do push.
  const pending = unverified(cwd);
  if (pending) {
    const strict = /^[ ]*[^\r\n\t\v\f]*[ ]*$/.test(cmd) ? R().STRICT.exec(cmd.trim()) : null;
    const onlyWip = strict && strict[2].trim().split(/ +/).every((x) => /:refs\/heads\/wip\/[A-Za-z0-9._-]+$/.test(x));
    if (!onlyWip) return `DENY verificação pendente: o push espera um encerramento da mesma sessão com build e testes verdes sobre a árvore limpa (turno encerrado pela exceção de verificação: ${pending}`;
  }
  if (joined !== cmd) return 'ASK barra no fim de linha num comando com push';
  const m = /^[ ]*[^\r\n\t\v\f]*[ ]*$/.test(cmd) ? R().STRICT.exec(cmd.trim()) : null;
  if (m) {
    const specs = m[2].trim().split(/ +/);
    if (specs.some((x) => x.includes('..'))) return 'DENY destino com ..';
    if (m[0].includes('..')) return 'ASK caminho com .. no comando';
    const again = checkPush(['origin', ...specs], []);
    if (again !== 'OK') return again;
    const dir = resolve(cwd, m[1] ?? '.'); // o git roda no cwd do payload: um -C relativo vale a partir dele
    const c = redirected(dir) || destination(dir);
    return c ? `ASK a configuração do git desvia o push: ${c}` : published(dir, specs);
  }
  // fora do formato fechado: git ... push fora de aspas é sempre ASK (texto entre aspas é dado)
  const bare = cmd.replace(/'[^']*'|"(?:[^"\\]|\\.)*"/g, ' ');
  if (/(^|[^A-Za-z0-9_.\/-])git\b[^\n]*\bpush\b/.test(bare)) return v.startsWith('ASK') ? v : 'ASK git push fora do formato liberado (use: git push -u origin <branch de atividade>, sozinho no comando)';
  return 'OK';
}

// Exceção de verificação usada e ainda não seguida de verificação verde: o motivo (primeira linha do marcador), ou ''.
// Os marcadores ficam na raiz do projeto ($CLAUDE_PROJECT_DIR, ou a raiz git do cwd), um por sessão.
function unverified(cwd) {
  let root = process.env.CLAUDE_PROJECT_DIR;
  if (!root) { try { root = git(cwd, 'rev-parse', '--show-toplevel'); } catch { return ''; } }
  // um marcador por sessão (unverified-<sessão>): qualquer um segura o push, de qualquer sessão
  const dir = join(root, '.claude', '.session');
  let names;
  try { names = existsSync(dir) ? readdirSync(dir).filter((n) => /^unverified(?:-|$)/.test(n)) : []; } catch { return 'pasta .claude/.session ilegível'; }
  if (!names.length) return '';
  const reasons = names.map((n) => {
    try { return readFileSync(join(dir, n), 'utf8').split('\n')[0].slice(0, 200).trim() || n; } catch { return `${n} ilegível`; }
  }).join('; ');
  // o comando de destravar vai na mensagem: marcador preso (commit da exceção reescrito por amend ou rebase, sessão
  // encerrada, formato antigo) só o desenvolvedor tira, e o path-guard recusa o comando ao agente
  const files = names.map((n) => `.claude/.session/${n}`).join(' ');
  return `${reasons}). Para liberar sem nova verificação, o desenvolvedor roda fora do agente, na raiz do projeto: rm -f ${files}`;
}

// O que o push publica, da origem de cada refspec (antes do ":", ou o próprio nome) até o merge-base com
// origin/<branch padrão>: mudança em caminho protegido (hooks, scripts, settings, workflows, ci...) só com aprovação, porque
// publicada ela vale na próxima sessão e um workflow roda no GitHub Actions com segredos. Sem essa base não dá para saber: ASK.
// O rev-parse e o git push leem a origem de jeitos diferentes (o rev-parse olha antes o pseudo-ref .git/<nome>, como FETCH_HEAD,
// e trata 40 hex como objeto; o push casa o nome só entre as refs locais), então vale o que qualquer um dos dois resolver, e
// origem ambígua pergunta (um nome que o hook e o git podem ler de outro jeito nunca sai OK).
const PSEUDO_REF = /^(?:[a-z]+_)*HEAD$|^AUTO_MERGE$/i; // HEAD, FETCH_HEAD, ORIG_HEAD, MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD, BISECT_HEAD
const HEX_NAME = /^[0-9a-f]{7,40}$/i;

function published(dir, specs) {
  const files = new Set();
  const seen = new Map(); // commit -> resultado de protectedChanged
  let ambiguous = '';
  let kind = '';
  for (const spec of specs) {
    const src = spec.includes(':') ? spec.slice(0, spec.indexOf(':')) : spec;
    const dst = spec.includes(':') ? spec.slice(spec.indexOf(':') + 1) : spec;
    let o;
    try { o = origins(dir, src); } catch (e) { return `ASK não foi possível resolver ${src} para conferir o que o push publica: ${e.message.split('\n')[0]}`; }
    ambiguous = ambiguous || o.ambiguous;
    // destino curto herda o tipo da origem: origem tag cria refs/tags/<destino> no remoto, não uma branch. O tipo é o nome
    // completo que o rev-parse resolve, como o git faz ao completar o destino: segue symref (HEAD ou branch apontando para
    // tag) e vale para tag de árvore ou blob, que não têm commit. Vazio (sha cru, ref inexistente): o git recusa o destino
    // curto sozinho. Sem --end-of-options (o git 2.43 o ecoa na saída): a origem passou pelo formato fechado, nunca é opção.
    // Motivo de menor prioridade: caminho protegido e ambiguidade, mais específicos, vêm antes.
    if (!dst.startsWith('refs/') && !kind) {
      let full = '';
      try { full = git(dir, 'rev-parse', '--symbolic-full-name', src); } catch { full = ''; }
      // vazio com a origem existente (nome ambíguo para o rev-parse, ou prazo esgotado no catch): tipo desconhecido, pede
      if (!full && o.commits.size) kind = `não foi possível saber o tipo da origem ${src} (nome ambíguo ou git sem resposta): use refs/heads/${dst} como destino`;
      else if (full && !full.startsWith('refs/heads/')) {
        const tag = full.startsWith('refs/tags/');
        kind = `a origem ${src} é ${tag ? 'a tag' : 'a ref'} ${full}: com destino curto o git criaria ${tag ? 'uma tag' : 'uma ref fora de refs/heads/'} no remoto (use refs/heads/${dst} como destino)`;
      }
    }
    for (const commit of o.commits) { // commits vazio: o git recusa o push de uma ref que não existe, nada é publicado
      if (!seen.has(commit)) seen.set(commit, protectedChanged(dir, commit));
      const r = seen.get(commit);
      if (r.failed) return `ASK não foi possível conferir o que o push publica: ${r.failed}`;
      for (const f of r.files) files.add(f);
    }
  }
  if (files.size) return `ASK o push publica mudança em caminho protegido: ${list([...files])}`;
  if (ambiguous) return `ASK ${ambiguous}`;
  return kind ? `ASK ${kind}` : 'OK';
}

// Os commits que a origem do refspec pode publicar, e o motivo se o nome é ambíguo. Candidatas do git push: refs/<nome>,
// refs/tags/<nome>, refs/heads/<nome>, refs/remotes/<nome>, refs/remotes/<nome>/HEAD (e o próprio nome, se já é refs/...).
function origins(dir, src) {
  const names = [`refs/${src}`, `refs/tags/${src}`, `refs/heads/${src}`, `refs/remotes/${src}`, `refs/remotes/${src}/HEAD`];
  if (src.startsWith('refs/')) names.unshift(src);
  const found = [];
  for (const name of names) {
    const commit = exactRefCommit(dir, name);
    if (commit) found.push({ name, commit });
  }
  const read = commitOf(dir, src); // a leitura do rev-parse: nome curto, pseudo-ref ou objeto
  const commits = new Set(found.map((f) => f.commit));
  if (read) commits.add(read);
  const special = PSEUDO_REF.test(src) || HEX_NAME.test(src);
  let ambiguous = '';
  if (found.length > 1) ambiguous = `origem ambígua no push: ${src} existe como ${found.map((f) => f.name).join(', ')}`;
  else if (found.length === 1 && (special || read !== found[0].commit)) ambiguous = `origem ambígua no push: ${src} é também ${special ? 'pseudo-ref ou sha' : 'lido pelo rev-parse como outro commit'} e existe como ${found[0].name}`;
  return { commits, ambiguous };
}

function scan(cmd, cwd) {
  // subcomandos: separadores fora de aspas; marca o que o hook não lê com segurança
  const segs = [[]];
  const risky = [false]; // por subcomando
  let cur = null, q = null, all = /<</.test(cmd); // heredoc pode esconder o que vem depois: todo push vira ASK
  const end = () => { if (cur !== null) { segs[segs.length - 1].push(cur); cur = null; } };
  const mark = () => { risky[risky.length - 1] = true; };
  const next = () => { end(); segs.push([]); risky.push(false); };
  for (let i = 0; i < cmd.length; i++) {
    const ch = cmd[i];
    if (q) { if (ch === q) q = null; else cur += ch; continue; }
    if (ch === "'" || ch === '"') { q = ch; cur = cur ?? ''; mark(); continue; }
    if (ch === '\\') {
      if (cmd[i + 1] === '\n') { end(); i++; continue; } // continuação de linha: é espaço
      mark(); cur = (cur ?? '') + (cmd[i + 1] ?? ''); i++; continue;
    }
    if (ch === '#' && cur === null) { all = true; break; } // comentário: o bash ignora o resto da linha
    if (ch === ' ' || ch === '\t') { end(); continue; }
    if (ch === '$') mark();
    if ('`{}'.includes(ch)) all = true;
    // & e | colados a um redirecionamento (2>&1, >&2, &>arquivo, >|arquivo) fazem parte dele, não separam comandos
    if ((ch === '&' && ('<>'.includes(cmd[i - 1]) || cmd[i + 1] === '>')) || (ch === '|' && cmd[i - 1] === '>')) { cur = (cur ?? '') + ch; continue; }
    if (';&|\n()`{}'.includes(ch)) { next(); continue; }
    cur = (cur ?? '') + ch;
  }
  end();
  if (q !== null) all = true;
  let worst = 'OK';
  const rank = { OK: 0, ASK: 1, DENY: 2 };
  const take = (v) => { if (rank[v.split(' ')[0]] > rank[worst.split(' ')[0]]) worst = v; };
  let moved = false; // subcomando anterior que muda o contexto do git (export GIT_*, cd para outro repositório)
  for (let n = 0; n < segs.length; n++) {
    const t = segs[n];
    if (['export', 'declare', 'typeset', 'cd', 'pushd', 'popd', 'source', '.', 'unset', 'alias', 'set'].includes(t[0])) moved = true;
    // redirecionamentos não são argumentos: 2>&1, >arquivo, > arquivo, &>arquivo, <arquivo
    const toks = [];
    for (let k = 0; k < t.length; k++) {
      const a = t[k];
      if (/^\d*(>>?|<|>\|)&?\d*-?$/.test(a) || /^&>>?$/.test(a)) { if (!/&\d/.test(a)) k++; continue; }
      if (/^(\d*>>?|<|&>>?|\d*>\|)\S/.test(a)) continue;
      toks.push(a);
    }
    const envs = [];
    // palavras do shell e prefixos que deixam o git depois deles: if ...; then git push, ! git push, env A=b git push
    for (;;) {
      if (toks.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(toks[0])) { envs.push(toks.shift()); continue; }
      if (toks.length && ['then', 'do', 'else', 'elif', '!', 'time', 'command', 'exec', 'nohup', 'env'].includes(toks[0])) { toks.shift(); continue; }
      break;
    }
    if (!toks.length || toks[0].replace(/^.*\//, '') !== 'git') continue;
    let k = 1, cfg = false, dir = cwd;
    while (k < toks.length && toks[k].startsWith('-')) {
      if (toks[k] === '-C') { dir = resolve(cwd, toks[k + 1] ?? '.'); k += 2; continue; }
      cfg = true; k += toks[k] === '-c' ? 2 : 1; // -c, --git-dir, --exec-path, --work-tree... mudam o que o git executa
    }
    if (toks[k] !== 'push') continue;
    if (envs.some((e) => /^GIT_/.test(e))) { take('DENY variável GIT_* antes do git push'); continue; }
    if (cfg) { take('DENY opção global do git antes de push (só -C é aceito)'); continue; }
    const v = checkPush(toks.slice(k + 1), envs);
    if (all || risky[n]) { take(v.startsWith('DENY') ? v : 'ASK o comando tem aspas, $, crase, chaves, heredoc, comentário ou barra junto de um git push'); continue; }
    if (v === 'OK' && moved) { take('ASK git push depois de export, cd, source ou parecido no mesmo comando'); continue; }
    if (v === 'OK') { const c = redirected(dir); if (c) { take(`ASK a configuração do git desvia o push: ${c}`); continue; } }
    take(v);
  }
  return worst;
}

// O nome "origin" no comando não diz para onde o push vai: quem decide é a configuração. Desvio comum: pushurl,
// insteadOf/pushInsteadOf, sshCommand, hooksPath (o deny de Edit(./.git/**) impede a edição pelas ferramentas).
function redirected(dir) {
  try {
    const o = execFileSync('git', ['-C', dir, 'config', '--show-origin', '--get-regexp', '^(remote\\.origin\\.(pushurl|push|receivepack|mirror)|remote\\.pushdefault|branch\\..*\\.pushremote|url\\..*\\.(insteadof|pushinsteadof)|core\\.(sshcommand|hookspath))$'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: left() });
    // entradas vindas de "command line" são do ambiente que lançou a sessão (o proxy da nuvem reescreve ssh para https
    // do GitHub); um export no mesmo comando já vira ASK. Contam as dos arquivos: .git/config, global e do sistema.
    const hit = o.split('\n').filter((l) => l && !l.startsWith('command line:'))[0];
    if (hit) return hit.split('\t')[1].split(' ')[0];
  } catch (e) {
    if (e.status !== 1) return 'não foi possível ler a configuração do git';
  }
  return pushes(dir);
}

// Configuração que junta refs ao push ou troca o destino de um refspec sem ":" (a conferência de published() vale só
// para a origem e o destino escritos): push.followTags publica tags anotadas de commits intermediários,
// push.recurseSubmodules empurra submódulos, e push.default upstream/tracking manda "x" para o branch.x.merge (que pode
// ser a main). Pelo valor, não pela chave: push.default=simple ou current é comum no ~/.gitconfig e não desvia.
function pushes(dir) {
  const read = (key, ...type) => {
    try {
      return execFileSync('git', ['-C', dir, 'config', ...type, '--get', key],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: left() }).trim().toLowerCase();
    } catch (e) {
      if (e.status === 1) return '';
      throw e;
    }
  };
  try {
    if (['upstream', 'tracking'].includes(read('push.default'))) return 'push.default';
    if (read('push.followtags', '--type=bool') === 'true') return 'push.followtags';
    if (!['', 'no', 'false', 'check'].includes(read('push.recursesubmodules'))) return 'push.recursesubmodules';
    return '';
  } catch {
    return 'não foi possível ler a configuração do git';
  }
}

// O destino efetivo: o git empurra para TODAS as url do origin (sem pushurl), e nunca por um transporte de programa
// auxiliar (ext::, fd::), que executa comando. O repositório precisa ser o do projeto (git-repo.mjs: checkout principal
// ou worktree registrada, com a referência validada), e o origin, ter uma única URL de push, entre as do projeto.
function destination(dir) {
  const urls = (d) => git(d, 'remote', 'get-url', '--push', '--all', 'origin').split('\n').filter(Boolean);
  let got;
  try { got = urls(dir); } catch { return 'origin sem URL de push legível'; }
  if (got.length !== 1) return `origin com ${got.length} URLs de push (o push iria para todas)`;
  if (got[0].includes('::')) return `transporte por programa auxiliar no origin: ${got[0].split('::')[0]}::`;
  const project = process.env.CLAUDE_PROJECT_DIR;
  if (!project) return '';
  const foreign = foreignRepo(dir);
  if (foreign) return foreign;
  let want;
  try { projectRepo(); want = urls(project); } catch (e) { return `repositório ou origin do projeto ilegível: ${e.message}`; }
  return want.includes(got[0]) ? '' : 'o origin deste repositório não é o origin do projeto';
}

function checkPush(args, envs) {
  const pos = [];
  let ask = null;
  for (const a of args) {
    if (a.startsWith('+')) return `DENY refspec com + (force): ${a}`;
    if (!SAFE.test(a)) return `ASK argumento com caractere que o shell expande: ${a}`;
    if (OKFLAGS.has(a)) continue;
    if (ASKFLAGS.test(a)) { ask = ask ?? `ASK ${a} só com aprovação do desenvolvedor`; continue; }
    if (a === '--force' || a === '-f' || /^-[a-z]*f[a-z]*$/.test(a)) return `DENY ${a}: force puro é do desenvolvedor`;
    if (['--delete', '-d', '--mirror', '--all', '--tags', '--prune', '--no-verify'].includes(a) || /^--(receive-pack|exec|repo|push-option)(=|$)/.test(a) || a === '-o')
      return `DENY flag não permitida no git push: ${a}`;
    if (a.startsWith('-')) return `ASK flag que o hook não conhece: ${a}`;
    pos.push(a);
  }
  if (envs.length) ask = ask ?? 'ASK variável de ambiente antes do git push';
  if (pos.length < 2) return 'ASK git push sem remoto e refspec explícitos (use: git push -u origin <branch de atividade>)';
  if (pos[0] !== 'origin') ask = ask ?? `ASK remoto diferente de origin: ${pos[0]}`;
  for (const spec of pos.slice(1)) {
    if (spec.startsWith('+')) return `DENY refspec com + (force): ${spec}`;
    const idx = spec.indexOf(':');
    if (idx === 0) return `DENY refspec que apaga a ref remota: ${spec}`;
    const dst = idx >= 0 ? spec.slice(idx + 1) : spec;
    const name = dst.replace(/^(?:refs\/)?heads\//, ''); // o git casa heads/main com refs/heads/main do remoto
    if (R().NEVER.has(name) || dst === 'HEAD' && idx >= 0) return `DENY push para ${dst}`;
    if (idx < 0 && spec === 'HEAD') { ask = ask ?? 'ASK git push de HEAD sem destino explícito'; continue; }
    if (name.includes('..')) return `DENY destino com ..: ${dst}`;
    if (WIP.test(dst)) continue;
    if (!R().ACT.test(name)) ask = ask ?? `ASK destino fora dos branches de atividade: ${dst}`;
  }
  return ask ?? 'OK';
}
