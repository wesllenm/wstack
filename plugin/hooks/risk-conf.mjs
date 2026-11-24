// Leitor do .claude/risk.conf do projeto, para o que cada projeto declara e os hooks de git e de comando usam:
// activity_branch, default_branch, protected, allow_module. Os hooks ficam no plugin, então o arquivo nunca vem da pasta
// deles: o projeto é $CLAUDE_PROJECT_DIR (que o Claude Code passa aos hooks) e, sem ela, a raiz git da pasta atual (os
// scripts que o agente roda pelo Bash não recebem a variável, e rodam no repositório que tratam).
// Formato do arquivo (o mesmo do review-dispatch.mjs): "chave = valor" por linha, "#" no começo da linha comenta, CRLF tolerado.
// Arquivo ausente ou ilegível, ou projeto indeterminado, devolve lista vazia e deixa o motivo em confError(): lista vazia
// restringe activity_branch, default_branch e allow_module, mas afrouxaria protected, então o protected-paths.mjs trata o
// erro como falha fechada.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

function projectDir() {
  if (process.env.CLAUDE_PROJECT_DIR) return process.env.CLAUDE_PROJECT_DIR;
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

let parsed;
let error = '';
function read() {
  if (parsed) return parsed;
  parsed = new Map();
  const project = projectDir();
  if (!project) { error = 'projeto indeterminado (sem CLAUDE_PROJECT_DIR e fora de repositório git)'; return parsed; }
  let text = '';
  try { text = readFileSync(join(project, '.claude', 'risk.conf'), 'utf8'); } catch (e) { error = e.code ?? e.message; return parsed; }
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
