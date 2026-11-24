# Decisões do wstack

Cada decisão: data, o que se decidiu, por quê (com a evidência) e o que muda. Decisão nova entra no fim; decisão que
muda uma anterior cita a anterior pela data.

## 2026-11-24: scripts no plugin, aprovados por hook (sonda 2)

**Decisão:** os scripts que skills, agentes e hooks rodam ficam dentro do plugin (opção A). As skills os chamam pelo
caminho que o Claude Code escreve no texto ao trocar `${CLAUDE_PLUGIN_ROOT}`. Um hook `PreToolUse` do próprio plugin
aprova esses comandos sem regra `allow` no projeto, conferindo o comando inteiro contra formas fechadas montadas com a
pasta real do plugin, nunca por prefixo. A opção B (copiar os scripts para o `.claude/` de cada projeto) não foi
desmentida pela sonda; foi descartada pelo desenvolvedor porque obriga cada projeto a carregar cópias e o bootstrap a
mantê-las na versão do plugin, enquanto em A há uma cópia só, versionada com o plugin.

**Evidência** (`docs/sonda.md`, Resultado da sonda 2; uma sessão na nuvem, home `/root`):
- O Claude Code trocou `${CLAUDE_PLUGIN_ROOT}` pelo caminho absoluto do plugin em todo o texto do SKILL.md, e o script
  chamado assim rodou da pasta do plugin. O Bash não tinha a variável.
- O comando que só o hook aprovava rodou com `permission_decision` `reason_type: hook`.
- Um hook Node do plugin importou um módulo da mesma pasta e um de outra pasta do plugin.
- Regra `allow` do projeto não se mediu: o controle sem regra rodou com `reason_type: rule, source: config`, igual
  aos números com regra, e o registro não diz qual regra casou. Ficou sem conferir se a regra veio de configuração da
  plataforma ou do `~/.claude/settings.json` do container.

**O que muda:**
- Hooks e scripts vão para `plugin/hooks/` e `plugin/scripts/`, lado a lado (há script que importa módulo de hook por
  caminho relativo); o bootstrap não copia script para o projeto.
- O texto das skills não pode citar a variável como texto: toda ocorrência vira caminho. Os scripts não recebem
  `CLAUDE_PLUGIN_ROOT` no Bash; se precisarem da própria pasta, tiram de `$0` (ou de `import.meta.url`, no Node).
- A sonda só provou a forma exata de um comando sem argumento. Os scripts reais recebem argumentos (atividade, commit,
  caminhos, transcrição); a forma fechada de cada um, com o que cada argumento aceita, é desenho da 2.2. Até ter forma
  fechada, o script pede aprovação. Script que hoje pede aprovação de propósito (o que manda trabalho para a nuvem)
  fica fora do aprovador.
- O hook aprovador é uma trava: cada forma liberada precisa de teste que prove que as variações (aspas, `$(...)`,
  argumento a mais, outro caminho) não são aprovadas. Ele roda junto com os hooks que pedem aprovação no mesmo
  comando, e o pedido de um deles vale sobre a aprovação do outro, então a revisão do path-guard cobre os caminhos
  do plugin.
- O que se mediu sobre hooks e modos: `deny` vindo de hook foi respeitado em "Accept edits" (sonda 2, passo C); `ask`
  vindo de hook, no modo automático, foi respondido pelo classificador sem diálogo (sonda 1, segunda rodada). Regra
  `allow` do projeto não mudou nada na sessão da nuvem; regra `deny` do projeto não foi testada.

## 2026-11-24: plugin atualizado ao iniciar a sessão na nuvem

**Decisão:** o setup script do ambiente de nuvem instala o plugin e grava `"autoUpdate": true` na entrada do
marketplace `wstack` em `~/.claude/settings.json`.

**Evidência:**
- Uma sessão nova recebeu o plugin 0.0.1 com a `main` já na 0.0.3. O registro dela mostra "Restored saved setup" e
  "Setup script cached from previous run": o ambiente reusou o container guardado sem rodar o script de novo.
- Num container com o plugin 0.0.1 instalado, `claude plugin install wstack@wstack` respondeu que o plugin já estava
  instalado e que o marketplace oferecia a 0.0.3, mandando rodar `claude plugin update`; o `update` levou à 0.0.3.
- O próprio Claude Code (2.1.331) descreve `autoUpdate` como "atualizar este marketplace e os plugins instalados ao
  iniciar" e diz, na mensagem sobre a chave, que ela só é lida de "user settings, --settings and managed settings";
  por isso ela vai no `~/.claude/settings.json`, não no do projeto.

**O que muda:** a troca do setup script fez a sessão seguinte montar um container novo, com a 0.0.3. A atualização
automática ainda não foi vista acontecer: conferir pela versão na mensagem do `SessionStart` quando sair a próxima
versão. Como ela convive com o plugin fixado numa versão pelo projeto é pendência do inventário (`docs/migracao.md`).

## 2026-11-24: destinos do inventário

Decisões do desenvolvedor sobre as pendências do inventário (`docs/migracao.md`):
- Os workflows do GitHub Actions do projeto baixam o wstack na versão fixada pelo projeto e rodam de lá os scripts
  de que precisam; o bootstrap não copia script para o projeto, nem para o CI.
- Os conversores de stack que a origem tratava como arquivo do projeto vão para o plugin, como os demais: não têm
  dado do projeto.
- A matriz de garantias dos hooks é documento do wstack, não modelo do projeto: os hooks agora são do plugin.
- Os workflows, a configuração de MCP do banco e o arquivo de calibração da revisão ficam para depois da 0.1.0.
