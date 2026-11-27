// Skills e agentes do plugin que o projeto substitui pelos dele: chave override do .claude/risk.conf, uma linha por item.
//   override = tdd                                  a skill (ou o agente) tdd do projeto no lugar do wstack:tdd
//   override = test-audit -> auditoria-de-testes   com outro nome no projeto (só skill: ver abaixo)
// O Claude Code não desliga um componente de plugin por vez (o skillOverrides não vale para skill de plugin); as duas
// versões continuam listadas, e quem escolhe é a lead (núcleo, Substituições do projeto) e o contrato de delegação.
// Medido com o Claude Code 2.1.332 (prove-overrides.sh): o skills: sem prefixo de um agente do plugin pré-carrega a
// skill do projeto de mesmo nome; a lead só chama agente da lista Agent(...) do frontmatter dela, que traz os nomes do
// plugin também sem prefixo, então agente do projeto só substitui com o mesmo nome.
// Uso: node overrides.mjs             imprime "tipo<TAB>plugin<TAB>projeto" por substituição válida
//      node overrides.mjs --session   avisos (nome inválido, item que o plugin não tem, arquivo do projeto ausente,
//                                     agente com outro nome, mesmo nome sem declaração) e as substituições
import { existsSync, readdirSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { confValues, projectDir } from './risk-conf.mjs';

const NAME = /^[a-z0-9][a-z0-9-]{0,63}$/;
const pluginDir = fileURLToPath(new URL('..', import.meta.url));
const list = (d, f) => { try { return readdirSync(d).map(f).filter(Boolean); } catch { return []; } };
export const pluginSkills = () => new Set(list(join(pluginDir, 'skills'), (n) => (existsSync(join(pluginDir, 'skills', n, 'SKILL.md')) ? n : '')));
export const pluginAgents = () => new Set(list(join(pluginDir, 'agents'), (n) => (n.endsWith('.md') ? n.slice(0, -3) : '')));
const projectHas = (root, kind, name) =>
  kind === 'skill' ? existsSync(join(root, '.claude', 'skills', name, 'SKILL.md')) : existsSync(join(root, '.claude', 'agents', `${name}.md`));

// { valid: [{ kind, plugin, project }], warnings: [texto] }
export function overrides(root = projectDir()) {
  const skills = pluginSkills(), agents = pluginAgents();
  const valid = [], warnings = [];
  for (const raw of confValues('override')) {
    const m = /^([^\s>]+)(?:\s*->\s*(\S+))?$/.exec(raw);
    const plugin = m?.[1] ?? '', project = m?.[2] ?? plugin;
    if (!m || !NAME.test(plugin) || !NAME.test(project)) { warnings.push(`override "${raw}" ignorado: use override = <nome no plugin> [-> <nome no projeto>], com minúsculas, dígitos e hífen.`); continue; }
    const kind = skills.has(plugin) ? 'skill' : agents.has(plugin) ? 'agente' : '';
    if (!kind) { warnings.push(`override = ${plugin} ignorado: o plugin não tem skill nem agente ${plugin}.`); continue; }
    if (kind === 'agente' && project !== plugin) { warnings.push(`override = ${raw} ignorado: agente do projeto só substitui o do plugin com o mesmo nome (a lista Agent(...) da lead é fixa).`); continue; }
    if (root && !projectHas(root, kind, project)) warnings.push(`override = ${raw}: o projeto não tem ${kind === 'skill' ? `.claude/skills/${project}/SKILL.md` : `.claude/agents/${project}.md`}; vale o wstack:${plugin}.`);
    else valid.push({ kind, plugin, project });
  }
  // mesmo nome no projeto sem declaração: a skill do projeto já entra no pré-carregamento dos agentes do plugin
  if (root) {
    const declared = new Set(valid.map((v) => v.plugin).concat(confValues('override').map((r) => r.split(/\s|->/)[0])));
    const shadow = [...skills].filter((n) => !declared.has(n) && projectHas(root, 'skill', n)).map((n) => `skill ${n}`)
      .concat([...agents].filter((n) => !declared.has(n) && projectHas(root, 'agente', n)).map((n) => `agente ${n}`));
    if (shadow.length) warnings.push(`o projeto tem ${shadow.join(', ')} com o mesmo nome de item do plugin, sem override no risk.conf: os agentes do plugin já pré-carregam a skill do projeto de mesmo nome. Declare override = <nome> se a troca é de propósito, ou renomeie a do projeto.`);
  }
  return { valid, warnings };
}

const self = (() => { try { return realpathSync(fileURLToPath(import.meta.url)); } catch { return ''; } })();
const argv1 = (() => { try { return process.argv[1] ? realpathSync(process.argv[1]) : ''; } catch { return ''; } })();
if (self && self === argv1) {
  const { valid, warnings } = overrides();
  if (process.argv[2] === '--session') {
    const lines = warnings.map((w) => `AVISO: ${w}`);
    if (valid.length) {
      lines.push(`Substituições do projeto (risk.conf, override): ${valid.map((v) => `${v.kind} ${v.project} do projeto no lugar do wstack:${v.plugin}`).join('; ')}. Chame e carregue a versão do projeto pelo nome sem prefixo, e passe as trocas no contrato de cada subagente.`);
    }
    if (lines.length) process.stdout.write(lines.join('\n') + '\n');
  } else {
    process.stdout.write(valid.map((v) => `${v.kind}\t${v.plugin}\t${v.project}`).join('\n') + (valid.length ? '\n' : ''));
  }
}
