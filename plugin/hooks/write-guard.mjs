// Veredito do write-guard.sh para Edit, Write, MultiEdit e NotebookEdit (payload do PreToolUse na entrada padrão).
// Imprime OK ou "DENY <motivo>"; a regra está em write-rule.mjs.
import { writeVerdict } from './write-rule.mjs';

let d = '';
process.stdin.on('data', (c) => (d += c)).on('end', () => {
  let j;
  try { j = JSON.parse(d); } catch { out('DENY payload ilegível'); return; }
  const file = j?.tool_input?.file_path ?? j?.tool_input?.notebook_path;
  if (typeof file !== 'string' || !file) { out('DENY caminho ausente no payload'); return; }
  out(writeVerdict(file, String(j?.cwd ?? process.cwd())));
});
function out(v) { process.stdout.write(v); }

