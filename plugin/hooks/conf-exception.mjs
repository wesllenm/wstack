// Exceção do .claude/risk.conf com validade. As chaves que afrouxam um gate (allow_module libera formas de comando no
// path-guard; review_exclude tira arquivos da revisão; smell_exclude tira arquivos do diff-smells) só valem com motivo
// e data de vencimento no futuro (ou hoje):
//   allow_module = dotnet | vence: 2027-03-31 | motivo: formas fechadas do dotnet, aprovado no bootstrap
// Sem data, data inválida, data passada ou sem motivo, a exceção é ignorada (o gate volta ao normal) e o session-start
// avisa: exceção sem data conta como vencida. Renovar é editar o risk.conf, que pede aprovação a cada edição.
// Uso como script (hook SessionStart): node conf-exception.mjs --warn   imprime um aviso por exceção ignorada e por
// linha que nenhum hook ou script lê (chave fora do modelo do risk.conf do plugin, com a mais parecida, ou linha sem
// "="): chave com erro de digitação deixa a configuração desligada sem sinal. Sai 0.
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
  // chaves conhecidas: as do modelo do risk.conf do plugin, comentadas ou não (a lista é o próprio modelo)
  let known = null;
  try {
    const model = readFileSync(new URL('../templates/.claude/risk.conf', import.meta.url), 'utf8');
    known = new Set([...model.matchAll(/^#?\s?([a-z_]+)\s*=/gm)].map((x) => x[1]));
  } catch { known = null; }
  const dist = (a, b) => { const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]); for (let j = 1; j <= b.length; j++) d[0][j] = j; for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++) d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)); return d[a.length][b.length]; };
  text.split(/\r?\n/).forEach((raw, i) => {
    const line = raw.trim();
    if (!line || line.startsWith('#')) return;
    const m = /^([a-z_]+)\s*=\s*(.*)$/.exec(line);
    // o conteúdo da linha não vai para o aviso (o contexto da sessão): só o número
    if (!m) { console.log(`AVISO: linha ${i + 1} do .claude/risk.conf não é "chave = valor" (minúsculas e _) e nenhum hook a lê.`); return; }
    if (known && !known.has(m[1])) {
      const near = [...known].map((k) => [k, dist(m[1], k)]).sort((x, y) => x[1] - y[1])[0];
      console.log(`AVISO: chave desconhecida na linha ${i + 1} do .claude/risk.conf: ${m[1]}${near && near[1] <= 3 ? ` (quis dizer ${near[0]}?)` : ''}. Nenhum hook nem script a lê, então a configuração dela está desligada.`);
      return;
    }
    // valor vazio: o script lê 0 ou o padrão dele, sem aviso (smell_comment_limit = vira 0, base = compara com o HEAD).
    // Só verify_lint vazio é de propósito: o modelo documenta que vazio não roda o formato
    if (!m[2].trim() && m[1] !== 'verify_lint') { console.log(`AVISO: ${m[1]} está vazio na linha ${i + 1} do .claude/risk.conf: quem a lê usa 0 ou o padrão dele. Preencher ou comentar a linha.`); return; }
    if (!EXCEPTION_KEYS.includes(m[1])) return;
    const e = parseException(m[2]);
    const shown = `${m[1]} = ${e.value}`.replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 160);
    if (!e.valid) console.log(`AVISO: exceção do .claude/risk.conf ignorada (linha ${i + 1}, ${shown}): ${e.problem}. O gate que ela afrouxava voltou ao normal; para renovar, o desenvolvedor aprova a edição com "| vence: AAAA-MM-DD | motivo: <texto>".`);
  });
  process.exit(0);
}
