// A pasta deste plugin, nas formas em que um comando ou caminho pode citá-la: o caminho real (o Node já resolve os
// links simbólicos de import.meta.url) e a CLAUDE_PLUGIN_ROOT que o Claude Code passa aos hooks e escreve no texto das
// skills, quando ela aponta para a mesma pasta real (por exemplo, ~/.claude atrás de um link). Uma CLAUDE_PLUGIN_ROOT
// que leve a outra pasta não conta. Sem barra no fim, com / no lugar de \.
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const norm = (p) => p.replace(/\\/g, '/').replace(/\/+$/, '');
const real = (p) => { try { return norm(realpathSync.native(p)); } catch { return ''; } };

export const pluginReal = real(fileURLToPath(new URL('..', import.meta.url)));

export function pluginRoots() {
  const roots = [pluginReal];
  const env = process.env.CLAUDE_PLUGIN_ROOT;
  if (env && real(env) === pluginReal) roots.push(norm(env));
  return [...new Set(roots.filter(Boolean))];
}

// A pasta do plugin, relativa à raiz do projeto ($CLAUDE_PROJECT_DIR), quando o plugin roda de dentro do próprio projeto:
// o repositório do wstack com o marketplace local apontando para o clone (docs/decisions.md, no ambiente do wstack, o
// plugin vem do clone). Fora desse caso, ''. Compara caminhos reais: um link para a pasta do plugin não a põe no projeto.
export function pluginInProject() {
  const project = process.env.CLAUDE_PROJECT_DIR;
  const top = project ? real(project) : '';
  if (!top || !pluginReal) return '';
  const fold = (p) => (process.platform === 'win32' ? p.toLowerCase() : p);
  return fold(pluginReal).startsWith(`${fold(top)}/`) ? pluginReal.slice(top.length + 1) : '';
}
