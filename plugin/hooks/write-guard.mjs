// Veredito do write-guard.sh para Edit, Write, MultiEdit e NotebookEdit (payload do PreToolUse na entrada padrão).
// Imprime OK ou "DENY <motivo>"; a regra das pastas git está em write-rule.mjs. Recusa também a pasta deste plugin (os
// hooks e os scripts que eles e o hook aprovador rodam): o plugin muda por atualização, nunca por edição, e um script
// alterado seria aprovado pelo script-allow. Vale por qualquer caminho que leve a ela (link simbólico, relativo, a pasta
// que o Claude Code informa), sem depender da regra deny do settings.json do projeto.
// Exceção: o plugin que roda de dentro do próprio projeto (o repositório do wstack, plugin carregado do clone) é código
// do projeto e muda por edição e PR; aí o script-allow só aprova script igual ao da branch padrão em origin
// (docs/decisions.md, edição do plugin no próprio wstack).
import { pluginInProject, pluginRoots } from './plugin-root.mjs';
import { inside, physical, writeVerdict } from './write-rule.mjs';

let d = '';
process.stdin.on('data', (c) => (d += c)).on('end', () => {
  let j;
  try { j = JSON.parse(d); } catch { out('DENY payload ilegível'); return; }
  const file = j?.tool_input?.file_path ?? j?.tool_input?.notebook_path;
  if (typeof file !== 'string' || !file) { out('DENY caminho ausente no payload'); return; }
  const cwd = String(j?.cwd ?? process.cwd());
  const p = (/^(\/|[A-Za-z]:[\\/])/.test(file) ? file : `${cwd}/${file}`).replace(/\\/g, '/');
  let r;
  try { r = physical(p); } catch (e) { out(`DENY caminho que o hook não resolve: ${e.message}`); return; }
  if (!pluginInProject() && pluginRoots().some((root) => inside(p, root) || inside(r, root))) {
    out(`DENY gravação na pasta do plugin wstack (muda por atualização do plugin, não por edição): ${file}`);
    return;
  }
  out(writeVerdict(file, cwd));
});
function out(v) { process.stdout.write(v); }
