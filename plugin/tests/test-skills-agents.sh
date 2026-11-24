#!/usr/bin/env bash
# Conferência estática das skills e agentes do plugin (unidade 2.3, docs/migracao.md):
# - nada cita o harness no projeto (.claude/scripts, .claude/hooks, .claude/cloud/setup.sh), o documento de origem (§)
#   nem o projeto de origem;
# - todo ${CLAUDE_PLUGIN_ROOT}/scripts/<x> e ${CLAUDE_PLUGIN_ROOT}/cloud/<x> citado existe no plugin, e a variável não
#   aparece em reference/*.md (lidos pelo Read, onde o Claude Code não a troca);
# - comando de script do plugin escrito numa skill usa um interpretador que o script-allow aceita para ele;
# - agente sem memory:, mcpServers:, hooks:, permissionMode: (docs/decisions.md, agentes do plugin sem memory:) e sem
#   TodoWrite; Agent(...) só com wstack:<nome> de agente que existe; skills: só com skill que existe;
# - cada skill tem SKILL.md com name: igual à pasta, e cada agente tem name: igual ao arquivo.
# Uso: test-skills-agents.sh [<pasta do plugin>]
# Código: 0 todos passaram, 1 algum falhou, 2 uso errado.
set -uo pipefail

plugin=${1:-$(dirname "$0")/..}
[ -d "$plugin/skills" ] && [ -d "$plugin/agents" ] && [ -f "$plugin/hooks/script-allow.mjs" ] \
  || { echo "pasta do plugin inválida: $plugin" >&2; exit 2; }

node - "$plugin" <<'EOF'
const fs = require('node:fs');
const path = require('node:path');
const plugin = process.argv[2];
let fails = 0;
const fail = (msg) => { console.log(`FALHOU: ${msg}`); fails++; };

const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
  const p = path.join(dir, e.name);
  return e.isDirectory() ? walk(p) : [p];
});
const rel = (p) => path.relative(plugin, p);
const files = [...walk(path.join(plugin, 'skills')), ...walk(path.join(plugin, 'agents'))].filter((f) => f.endsWith('.md'));

const frontmatter = (text) => {
  const m = text.match(/^---\n([\s\S]*?)\n---\n/);
  return m ? m[1] : null;
};
// Campo do frontmatter: valor na linha ou lista "  - item" nas linhas seguintes.
const field = (fm, key) => {
  const lines = fm.split('\n');
  const i = lines.findIndex((l) => l.startsWith(`${key}:`));
  if (i < 0) return null;
  const inline = lines[i].slice(key.length + 1).trim();
  if (inline) return inline;
  const items = [];
  for (const l of lines.slice(i + 1)) {
    const m = l.match(/^\s+-\s+(.*)$/);
    if (!m) break;
    items.push(m[1].trim());
  }
  return items;
};

// Interpretadores aceitos por script, lidos do próprio script-allow ('' = execução direta).
const allowSrc = fs.readFileSync(path.join(plugin, 'hooks', 'script-allow.mjs'), 'utf8');
const block = allowSrc.match(/const SCRIPTS = \{([\s\S]*?)\n\};/);
const allowed = {};
if (!block) fail('script-allow.mjs: tabela SCRIPTS não encontrada');
else for (const m of block[1].matchAll(/'([^']+)':\s*\[([^\]]*)\]/g)) {
  allowed[m[1]] = [...m[2].matchAll(/'([^']*)'/g)].map((x) => x[1]);
}

const skills = new Set(fs.readdirSync(path.join(plugin, 'skills'), { withFileTypes: true })
  .filter((e) => e.isDirectory()).map((e) => e.name));
const agents = new Set(fs.readdirSync(path.join(plugin, 'agents')).filter((f) => f.endsWith('.md'))
  .map((f) => f.replace(/\.md$/, '')));

for (const f of files) {
  const text = fs.readFileSync(f, 'utf8');
  const r = rel(f);
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    const at = `${r}:${i + 1}`;
    if (/\.claude\/(scripts|hooks)\/|\.claude\/cloud\/setup\.sh/.test(line)) fail(`${at}: caminho do harness no projeto`);
    if (line.includes('§')) fail(`${at}: citação § do documento de origem`);
    if (/squad ?os/i.test(line)) fail(`${at}: nome do projeto de origem`);
    if (/\/reference\//.test(r) && line.includes('${CLAUDE_PLUGIN_ROOT}')) {
      fail(`${at}: \${CLAUDE_PLUGIN_ROOT} em reference/ (o Read não troca a variável)`);
    }
    for (const m of line.matchAll(/\$\{CLAUDE_PLUGIN_ROOT\}\/(scripts|cloud|hooks)\/([A-Za-z0-9_.-]+)/g)) {
      if (!fs.existsSync(path.join(plugin, m[1], m[2]))) fail(`${at}: ${m[1]}/${m[2]} não existe no plugin`);
    }
    // Comando entre crases: [bash |node ]${CLAUDE_PLUGIN_ROOT}/scripts/<x>
    for (const m of line.matchAll(/`(?:(bash|node) )?\$\{CLAUDE_PLUGIN_ROOT\}\/scripts\/([A-Za-z0-9_.-]+)[^`]*`/g)) {
      const interp = m[1] || '';
      const ok = allowed[m[2]];
      if (ok && !ok.includes(interp)) {
        fail(`${at}: ${m[2]} com interpretador '${interp}', o script-allow aceita [${ok.map((x) => `'${x}'`).join(', ')}]`);
      }
    }
  });

  if (r.startsWith('skills/') && path.basename(f) === 'SKILL.md') {
    const fm = frontmatter(text);
    const dir = path.basename(path.dirname(f));
    if (!fm) fail(`${r}: sem frontmatter`);
    else if (field(fm, 'name') !== dir) fail(`${r}: name: diferente da pasta (${dir})`);
  }

  if (r.startsWith('agents/')) {
    const fm = frontmatter(text);
    if (!fm) { fail(`${r}: sem frontmatter`); continue; }
    const name = path.basename(f, '.md');
    if (field(fm, 'name') !== name) fail(`${r}: name: diferente do arquivo`);
    for (const key of ['memory', 'mcpServers', 'hooks', 'permissionMode']) {
      if (field(fm, key) !== null) fail(`${r}: campo ${key}: (agente de plugin não usa)`);
    }
    const tools = field(fm, 'tools') || '';
    const toolText = Array.isArray(tools) ? tools.join(', ') : tools;
    if (/\bTodoWrite\b/.test(toolText)) fail(`${r}: TodoWrite não existe nesta versão do Claude Code`);
    const call = toolText.match(/Agent\(([^)]*)\)/);
    if (call) {
      for (const entry of call[1].split(',').map((x) => x.trim()).filter(Boolean)) {
        if (!entry.startsWith('wstack:')) fail(`${r}: Agent(${entry}) sem o prefixo wstack:`);
        else if (!agents.has(entry.slice('wstack:'.length))) fail(`${r}: Agent(${entry}) não existe no plugin`);
      }
    }
    const pre = field(fm, 'skills');
    for (const s of Array.isArray(pre) ? pre : pre ? pre.split(',').map((x) => x.trim()) : []) {
      if (!skills.has(s.replace(/^wstack:/, ''))) fail(`${r}: skills: ${s} não existe no plugin`);
    }
  }
}

if (fails === 0) { console.log(`test-skills-agents: todos os casos passaram (${files.length} arquivos)`); process.exit(0); }
console.log(`test-skills-agents: ${fails} falha(s)`);
process.exit(1);
EOF
