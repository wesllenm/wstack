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
