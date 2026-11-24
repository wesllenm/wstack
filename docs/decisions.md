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

## 2026-11-24: no ambiente do wstack, o plugin vem do clone

Muda a decisão de 2026-11-24 "plugin atualizado ao iniciar a sessão na nuvem".

**Decisão:** o setup script do ambiente `wstack` instala o plugin de um marketplace local, a pasta do clone
(`claude plugin marketplace add /home/user/wstack` e `claude plugin install wstack@wstack`), sem `autoUpdate` e sem
atualização forçada.

**Por quê** (`docs/sonda.md`, sonda 3, fato 0 e resultado com a 0.0.7):
- O `autoUpdate` não atualizou o plugin na partida, e o setup script só roda quando o ambiente remonta o container
  (troca do script ou dos hosts, ou cache vencido, cerca de 7 dias). Cada versão nova exigia mexer no script.
- Marketplace local é carregado da própria pasta: na sessão com o script novo, `${CLAUDE_PLUGIN_ROOT}` virou
  `/home/user/wstack/plugin`, embora o `installed_plugins.json` registre a pasta de cache. Cada sessão clona o
  repositório de novo, então carrega o plugin da branch em que abriu.

**O que muda:**
- Visto acontecer (2026-11-24): a primeira sessão depois do merge da 0.0.8, sem troca no script, deu
  `wstack 0.0.8 carregado.` com o cache só em `0.0.7`. O `session-start.sh` lê a versão do `plugin.json` da pasta do
  próprio hook, então ele rodou do clone. Na mesma sessão, Edit em `plugin/hooks/write-guard.mjs` foi aceito (decisão
  seguinte).
- Vale só para o ambiente do próprio wstack, cujo clone é o plugin. O ambiente de outro projeto continua instalando do
  GitHub e fica na versão do dia da montagem; como ele se atualiza fica pendente para a 2.4.
- O write-guard recusa gravação na pasta do plugin, e agora essa pasta é `plugin/` do clone: Edit e Write em
  `plugin/` seriam recusados nas sessões deste ambiente. Resolvido na decisão seguinte.

## 2026-11-24: edição do plugin no próprio wstack

**Decisão:** quando a pasta real do plugin fica dentro do projeto (`$CLAUDE_PROJECT_DIR`), o write-guard deixa a
ferramenta de escrita gravar nela. É o caso do repositório do wstack com o plugin carregado do clone; um link para a
pasta do plugin não conta. Nesse caso, o script-allow só aprova os scripts do plugin com a pasta `plugin/` inteira igual
à de `origin/<branch padrão>`: nada alterado, apagado, fora do git ou marcado para o git não ver
(`assume-unchanged`, `skip-worktree`). Sem `origin/<branch padrão>`, não aprova.

**Por quê:** no ambiente do wstack o plugin é o código do projeto e muda por edição e PR; a recusa impedia o
desenvolvimento dele. O write-guard recusava a pasta do plugin para que um script alterado não fosse aprovado pelo
script-allow; a comparação com a branch padrão mantém isso: script ou módulo alterado na sessão volta a pedir
aprovação, e só o que passou por PR roda sem pedir. A pasta inteira, porque um script importa hooks e módulos.

**Risco aceito:** o hook alterado vale já na sessão (o plugin é lido da pasta), então a sessão pode afrouxar as
próprias travas, inclusive o push-guard. Na nuvem isso já era possível pelo Bash (decisão "trava por texto na nuvem");
o que muda é que no wstack a alteração sai da VM pelo push, porque `plugin/` é código do repositório e não é caminho
protegido. A barreira é o PR revisado e a proteção da `main`. Fora da nuvem, o path-guard continua pedindo aprovação
para comando que cite a pasta do plugin.

## 2026-11-24: agentes do plugin sem `memory:`

**Decisão:** na unidade 2.3, os agentes do harness entram no plugin sem depender do campo `memory:` do frontmatter. O
que um agente precisar guardar entre sessões vai para arquivo do projeto que ele lê e grava pelas ferramentas
(`docs/gotchas.md`, `docs/review-calibration.md`), como o harness de origem já faz nas skills.

**Por quê** (`docs/sonda.md`, sonda 3, resultados com a 0.0.7 e a 0.0.9): na nuvem, `memory: project` não deu pasta de
memória nem ao agente de projeto, mesmo com Read, Write e Edit declarados. Não se sabe se vale em agente de plugin, e
o ambiente em que o wstack é desenvolvido e testado não mostra a memória funcionando em agente nenhum.

**O que muda:**
- Os nomes que a sonda 3 decidiu valem para a 2.3: agente do plugin é chamado e listado em `Agent(...)` só como
  `wstack:<nome>`; `skills:` pré-carrega skill do plugin pelo nome curto ou com prefixo; `${CLAUDE_PLUGIN_ROOT}` no
  corpo do agente vira o caminho do plugin.
- **Pendente:** rodar o passo E numa sessão local. Se a memória valer em agente de plugin, um agente pode passar a usá-la
  numa mudança própria, com decisão nova.

## 2026-11-24: subagente isolado nasce do HEAD (`worktree.baseRef`)

**Decisão:** o `settings.json` modelo do projeto (2.4) grava `"worktree": { "baseRef": "head" }`. A skill lead conta com
isso para delegar com `isolation: worktree` (seção Delegação) e para abrir atividade com `claude -w` (Modo paralelo
assistido).

**Por quê** (medido no harness de origem em 2026-11-18, Claude Code 2.1.133 ou mais novo): sem a chave, o subagente com
`isolation: worktree` nasceu da branch padrão (a sonda isolada devolveu o commit da `main` com o HEAD da sessão em
outro commit), sem o trabalho em andamento nem o plano; com a chave, nasceu do HEAD, e a mudança valeu na sessão sem
reiniciar. Mudança não commitada não vai para a worktree em nenhum dos casos.

**O que muda:** a citação do arquivo de gotchas da origem sai da skill lead, que passa a dizer o efeito da chave. A 2.4
confere a chave no modelo do `settings.json`.
