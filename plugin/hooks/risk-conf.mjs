// Leitor do .claude/risk.conf do PRÓPRIO projeto dos hooks (a pasta .claude onde este arquivo está), para o que cada projeto
// declara e os hooks de git e de comando usam: activity_branch, default_branch, protected, allow_module.
// Formato do arquivo (o mesmo do review-dispatch.mjs): "chave = valor" por linha, "#" no começo da linha comenta, CRLF tolerado.
// Arquivo ausente ou ilegível devolve lista vazia e deixa o motivo em confError(): lista vazia restringe activity_branch,
// default_branch e allow_module, mas afrouxaria protected, então o protected-paths.mjs trata o erro como falha fechada.
import { readFileSync } from 'node:fs';

let parsed;
let error = '';
function read() {
  if (parsed) return parsed;
  parsed = new Map();
  let text = '';
  try { text = readFileSync(new URL('../risk.conf', import.meta.url), 'utf8'); } catch (e) { error = e.code ?? e.message; return parsed; }
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const m = /^([a-z_]+)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    parsed.set(m[1], [...(parsed.get(m[1]) ?? []), m[2].trim()]);
  }
  return parsed;
}

// Valores da chave, na ordem do arquivo; [] se ela não aparece ou o arquivo não pôde ser lido.
export const confValues = (key) => read().get(key) ?? [];
// Motivo de o .claude/risk.conf não ter sido lido (ex.: ENOENT, EISDIR); '' se foi lido.
export const confError = () => (read(), error);
