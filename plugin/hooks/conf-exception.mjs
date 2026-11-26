// Exceção do .claude/risk.conf com validade. As chaves que afrouxam um gate (allow_module libera formas de comando no
// path-guard; review_exclude tira arquivos da revisão; smell_exclude tira arquivos do diff-smells) só valem com motivo
// e data de vencimento no futuro (ou hoje):
//   allow_module = dotnet | vence: 2027-03-31 | motivo: formas fechadas do dotnet, aprovado no bootstrap
// Sem data, data inválida, data passada ou sem motivo, a exceção é ignorada (o gate volta ao normal) e o session-start
// avisa: exceção sem data conta como vencida. Renovar é editar o risk.conf, que pede aprovação a cada edição.
// Uso como script (hook SessionStart): node conf-exception.mjs --warn   imprime um aviso por exceção ignorada; sai 0.
import { readFileSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const EXCEPTION_KEYS = ['allow_module', 'review_exclude', 'smell_exclude'];

const today = () => new Date().toISOString().slice(0, 10);
const realDate = (s) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return d.toISOString().slice(0, 10) === s;
};

// "<valor> | vence: AAAA-MM-DD | motivo: <texto>" -> { value, vence, motivo, valid, problem }
export function parseException(raw) {
  const [value, ...meta] = String(raw).split('|').map((s) => s.trim());
  const field = (k) => meta.map((m) => new RegExp(`^${k}\\s*:\\s*(.*)$`, 'i').exec(m)?.[1]?.trim()).find((v) => v !== undefined) ?? '';
  const vence = field('vence'), motivo = field('motivo');
  let problem = '';
  if (!vence) problem = 'sem data de vencimento (vence: AAAA-MM-DD)';
  else if (!realDate(vence)) problem = `data inválida: ${vence}`;
  else if (vence < today()) problem = `venceu em ${vence}`;
  else if (!motivo) problem = 'sem motivo (motivo: <texto>)';
  return { value, vence, motivo, valid: !problem, problem };
}

// Valores das exceções válidas de uma lista de linhas cruas da chave (o resto é ignorado).
export const validValues = (raws) => raws.map(parseException).filter((e) => e.valid).map((e) => e.value);

const self = (() => { try { return realpathSync(fileURLToPath(import.meta.url)); } catch { return ''; } })();
const argv1 = (() => { try { return process.argv[1] ? realpathSync(process.argv[1]) : ''; } catch { return ''; } })();
if (self && self === argv1 && process.argv[2] === '--warn') {
  let text = '';
  try { text = readFileSync(join(process.env.CLAUDE_PROJECT_DIR || '.', '.claude', 'risk.conf'), 'utf8'); } catch { process.exit(0); }
  text.split(/\r?\n/).forEach((raw, i) => {
    const line = raw.trim();
    const m = /^([a-z_]+)\s*=\s*(.*)$/.exec(line);
    if (!m || line.startsWith('#') || !EXCEPTION_KEYS.includes(m[1])) return;
    const e = parseException(m[2]);
    const shown = `${m[1]} = ${e.value}`.replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 160);
    if (!e.valid) console.log(`AVISO: exceção do .claude/risk.conf ignorada (linha ${i + 1}, ${shown}): ${e.problem}. O gate que ela afrouxava voltou ao normal; para renovar, o desenvolvedor aprova a edição com "| vence: AAAA-MM-DD | motivo: <texto>".`);
  });
  process.exit(0);
}
