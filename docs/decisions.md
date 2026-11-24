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
- Os workflows e a configuração de MCP do banco ficam para depois da 0.1.0.
- O arquivo de calibração da revisão entra na 2.4 como modelo do projeto: o hook de Stop exige esse arquivo para
  registrar o aprendizado da sessão.
- A versão fixada pelo projeto é a referência que o marketplace declara no `settings.json` do projeto; o
  `autoUpdate` atualiza dentro dela, e o setup script da nuvem declara a mesma referência. Conferir na 2.4 com o
  `claude plugin validate` e uma sessão de teste.
- A avaliação comportamental fica para depois da 0.1.0, no repositório wstack (não no plugin), decidindo então entre
  portar os scripts da origem e usar o `claude plugin eval`.

## 2026-11-24: trava mínima nos comandos

**Decisão:** os hooks que leem o texto dos comandos Bash (path-guard, redirect-guard, push-guard) são cinto de
segurança, não fronteira. Pedem aprovação só para o que desligaria as próprias travas (os arquivos do plugin, o
`settings.json` e o `risk.conf` do projeto, `.git`, `.gitignore`, workflows, `.mcp.json`) ou exporia segredo; o resto é
livre. A fronteira é o PR revisado, o isolamento da sessão e as regras `deny`.

**Por quê:** no modo automático e no "Accept edits", o Claude Code não aplica as regras `ask` de Edit aos comandos de
terminal (`plugin/tests/prove-write-matrix.sh` mede isso com o Claude Code real); só um hook que leia o comando cobre
esse caminho. Ler texto de comando nunca é completo (aspas no meio do nome, caminho montado em variável), então pedir
aprovação para tudo o que parece arriscado só gera pedidos que o desenvolvedor aprova sem ler.

**O que muda no plugin:** os hooks e os scripts que eles e as skills rodam moram em `~/.claude/plugins/...`, fora do
projeto e fora do que o push publica. Por isso `.claude/plugins` entrou nas travas do path-guard (comando que cita ou
roda nessa pasta pede aprovação) e `Edit(~/.claude/plugins/**)` entra no `deny` do `settings.json` modelo: o plugin muda
por `claude plugin update`, nunca por edição. O script do plugin chamado pelo caminho da própria pasta do plugin, no
começo do comando e com a pasta do comando na raiz do projeto, não conta como citação de trava (o resto do comando
continua conferido); `.claude/scripts` e `.claude/hooks` num projeto deixam de ser do harness e pedem como qualquer
trava.

## 2026-11-24: trava por texto na nuvem

**Decisão:** na sessão na nuvem (`CLAUDE_CODE_REMOTE=true`), a mera citação de caminho do harness (arquivos do plugin,
`.claude/` do projeto, workflows) não pede aprovação. Continuam pedindo: `.git` (config e hooks do git executariam
código no push com a credencial da sessão), `~/.claude.json`, segredos, credenciais e comandos de config que executam
programa.

**Por quê:** a VM da nuvem é descartável e ninguém está olhando para aprovar a cada pedido; a trava por texto é
contornável de qualquer jeito. O que importa é o que sai da VM: o push-guard e o `checkpoint.sh` conferem os caminhos
protegidos do que o push publica, e o resto passa pelo PR.

**Risco aceito:** dentro da VM, o agente pode alterar os arquivos do plugin, inclusive o push-guard e o
protected-paths, e com isso desligar essa conferência para os pushes seguintes da mesma sessão. A alteração não sai da
VM (o plugin não é publicado pelo push), mas o que o push leva passa a depender só do lado do GitHub: o PR revisado e a
proteção da branch padrão. Fora da nuvem, a pasta do plugin pede aprovação (path-guard) e a ferramenta de escrita não
grava nela (write-guard).

## 2026-11-24: gates do Stop configurados pelo projeto

**Decisão:** o hook de Stop (verify-on-stop) é do plugin e lê os comandos do projeto do `.claude/risk.conf`
(`verify_solution`, `verify_build`, `verify_lint`, `verify_test`); sem eles, o gate de verificação não roda. O gate de
aprendizado (commit de código na sessão exige um registro no arquivo de calibração) só vale no projeto que tem
`docs/review-calibration.md`, que o bootstrap cria.

**Por quê:** os comandos eram lacunas preenchidas no próprio arquivo do hook, que agora é igual em todo projeto. E o
setup da nuvem instala o plugin no escopo do usuário: os hooks rodam em todo repositório do ambiente, inclusive nos que
não adotaram o workflow, onde o gate de aprendizado bloquearia o fim de toda sessão com commit e mandaria seguir uma
skill que o projeto não usa. No projeto que tem o arquivo, o gate é o mesmo (`plugin/tests/test-verify-on-stop.sh`).

**Pendente (2.4):** o resto do comportamento num repositório sem bootstrap. Hoje o iteration-guard age com o limite
padrão (40 edições), o session-start e o iteration-guard criam `.claude/.session/` e o push-guard pede aprovação para
todo push fora de `ccr-` e `wip/` (sem `activity_branch`). Decidir se o plugin fica inerte sem `.claude/risk.conf`,
mantendo só as travas de segurança.
