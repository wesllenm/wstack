// Destinos dos documentos do projeto: onde a escada de aprendizado e a skill lead leem e gravam. Cada um vem da chave
// doc_<nome> do .claude/risk.conf (a última linha vale) e, sem ela, do caminho padrão. Um projeto que já tem lugar
// para esses fatos (decisões em .claude/decisions.md, por exemplo) aponta a chave em vez de manter dois arquivos.
//   decisions    decisões do projeto e o porquê                        docs/decisions.md
//   gotchas      núcleo das armadilhas e índice por área (o CLAUDE.md importa)  docs/gotchas.md
//   gotchas_dir  arquivos de armadilha por área                         docs/gotchas
//   calibration  Registro, Totais e Backlog de mecanismo (gate do Stop)  docs/review-calibration.md
//   rubric       complemento da rubrica de revisão                       docs/review-rubric.md
//   state        pendência e "onde paramos", versionado                  (sem padrão: ficam no .claude/SESSION.md)
// Valor fora da forma (caminho relativo à raiz, sem "..", só [A-Za-z0-9._/-]) é ignorado: vale o padrão e o
// SessionStart avisa. Quem lê: verify-on-stop.sh, summarize-runs.mjs, pr-risk-gate.mjs, bootstrap.sh e o SessionStart.
// Uso: node doc-paths.mjs              imprime "nome=caminho" por linha (state vazio quando não configurado)
//      node doc-paths.mjs --session    avisos de valor ignorado ou arquivo ausente, e os destinos que diferem do padrão
import { existsSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { confValues, projectDir } from './risk-conf.mjs';

export const DOC_DEFAULTS = {
  decisions: 'docs/decisions.md',
  gotchas: 'docs/gotchas.md',
  gotchas_dir: 'docs/gotchas',
  calibration: 'docs/review-calibration.md',
  rubric: 'docs/review-rubric.md',
  state: '',
};
const LABEL = {
  decisions: 'decisões', gotchas: 'armadilhas (núcleo e índice)', gotchas_dir: 'armadilhas por área',
  calibration: 'calibração da revisão', rubric: 'complemento da rubrica', state: 'pendência e onde paramos',
};
const PATH = /^(?![-/])(?!.*(?:^|\/)\.\.(?:\/|$))[A-Za-z0-9._/-]+$/;

// { nome: { path, configured, invalid } } para cada destino
export function docEntries() {
  const out = {};
  for (const [name, def] of Object.entries(DOC_DEFAULTS)) {
    const raw = confValues(`doc_${name}`).at(-1);
    const value = raw?.replace(/\/+$/, '');
    if (raw === undefined || raw === '') out[name] = { path: def, configured: false, invalid: '' };
    else if (!PATH.test(value)) out[name] = { path: def, configured: false, invalid: raw };
    else out[name] = { path: value, configured: value !== def, invalid: '' };
  }
  return out;
}
export const docPaths = () => Object.fromEntries(Object.entries(docEntries()).map(([k, v]) => [k, v.path]));

const self = (() => { try { return realpathSync(fileURLToPath(import.meta.url)); } catch { return ''; } })();
const argv1 = (() => { try { return process.argv[1] ? realpathSync(process.argv[1]) : ''; } catch { return ''; } })();
if (self && self === argv1) {
  const entries = docEntries();
  if (process.argv[2] === '--session') {
    const root = projectDir();
    const lines = [];
    const moved = [];
    for (const [name, e] of Object.entries(entries)) {
      if (e.invalid) lines.push(`AVISO: doc_${name} do risk.conf ignorado (caminho relativo à raiz, sem "..", só letras, números, ., _, / e -): vale ${e.path || 'o padrão'}.`);
      if (!e.configured) continue;
      moved.push(`${LABEL[name]} em ${e.path}`);
      if (root && !existsSync(join(root, e.path))) lines.push(`AVISO: doc_${name} = ${e.path} do risk.conf não existe no projeto.`);
    }
    if (moved.length) {
      lines.push(`Destinos de documento deste projeto (risk.conf, doc_*): ${moved.join('; ')}. Nas skills e agentes do wstack, o caminho padrão citado (docs/decisions.md, docs/gotchas.md, docs/gotchas/, docs/review-calibration.md, docs/review-rubric.md) quer dizer o destino configurado; passe os destinos no contrato de cada subagente.`);
    }
    if (entries.state.configured) {
      lines.push(`Com doc_state, a pendência e o "onde paramos" vão para ${entries.state.path}, versionado; o .claude/SESSION.md guarda só o estado local da sessão (plano, passo, verificado).`);
    }
    if (lines.length) process.stdout.write(lines.join('\n') + '\n');
  } else {
    process.stdout.write(Object.entries(entries).map(([k, e]) => `${k}=${e.path}`).join('\n') + '\n');
  }
}
