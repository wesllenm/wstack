# Decisões do wstack

Cada decisão: data, o que se decidiu, por quê (com a evidência) e o que muda. Decisão nova entra no fim; decisão que
muda uma anterior cita a anterior pela data.

## 2026-11-24: scripts no plugin, aprovados por hook (sonda 2)

**Decisão:** os scripts que skills, agentes e hooks rodam ficam dentro do plugin (opção A). As skills os chamam pelo
caminho que o Claude Code escreve no texto ao trocar `${CLAUDE_PLUGIN_ROOT}`. Um hook `PreToolUse` do próprio plugin
aprova esses comandos, comparando o comando inteiro com uma lista fechada de formas exatas, montadas com a pasta real
do plugin; nunca por padrão ou prefixo. O `settings.json` do projeto não precisa de regra `allow` para eles. A
alternativa B (copiar os scripts para o `.claude/` de cada projeto) fica descartada.

**Por quê** (resultado em `docs/sonda.md`, Sonda 2):
- O Claude Code troca `${CLAUDE_PLUGIN_ROOT}` pelo caminho absoluto do plugin em todo o texto do SKILL.md, e o script
  chamado assim rodou da pasta do plugin.
- A aprovação vinda de hook funcionou (`permission_decision` com `reason_type: hook`), em qualquer home e sem
  depender da configuração do projeto.
- Regra `allow` do projeto não se mede na nuvem: lá, uma configuração da plataforma libera todo comando Bash (o
  controle sem regra saiu `reason_type: rule, source: config`, igual às regras testadas). Fora da nuvem, uma regra
  com o caminho do plugin dependeria da home ou de um `*` no começo, que casaria com qualquer pasta terminada igual.
- Um hook Node do plugin importa módulos da mesma pasta e de outra pasta do plugin.

**O que muda:**
- Hooks e scripts vão para `plugin/hooks/` e `plugin/scripts/`; o bootstrap não copia script para o projeto.
- O texto das skills não pode citar a variável como texto: toda ocorrência vira caminho. Os scripts não recebem
  `CLAUDE_PLUGIN_ROOT` no Bash; se precisarem da própria pasta, tiram de `$0` (ou de `import.meta.url`, no Node).
- O hook aprovador é uma trava: cada forma liberada precisa de teste que prove que uma variação (aspas, `$(...)`,
  argumento a mais, outro caminho) não é aprovada.
- Na nuvem, regra do projeto não segura nada que a configuração da plataforma libere; as travas do wstack são hooks
  (`deny` e `ask` vindos de hook valem em todo modo).

## 2026-11-24: plugin atualizado ao iniciar a sessão na nuvem

**Decisão:** o setup script do ambiente de nuvem instala o plugin e grava `"autoUpdate": true` na entrada do
marketplace `wstack` em `~/.claude/settings.json`.

**Por quê:** o ambiente guarda o container depois do setup script e o reusa nas sessões seguintes sem rodar o script
de novo ("Setup script cached from previous run"); uma sessão nova recebeu o plugin 0.0.1 com a `main` já na 0.0.3.
Com o plugin instalado, `claude plugin install` não atualiza (avisa para rodar `claude plugin update`). O Claude Code
só lê `autoUpdate` das configurações do usuário, de `--settings` e das gerenciadas, não do `.claude/settings.json` do
projeto.

**O que muda:** a troca do setup script fez a sessão seguinte montar um container novo, com a 0.0.3. A atualização
automática ainda não foi vista acontecer: confirmar pela versão na mensagem do `SessionStart` quando sair a próxima
versão.
