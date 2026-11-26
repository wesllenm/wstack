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

## 2026-11-24: complemento da rubrica no projeto (`docs/review-rubric.md`)

**Decisão** (do desenvolvedor, na 2.3): a skill `review-rubric` é do plugin e igual em todo projeto. O que é de um
repositório (as seções Sempre verificar, Não reportar e Projeto) fica em `docs/review-rubric.md` do projeto, que a skill
manda ler e somar às seções de mesmo nome. A calibração e a escada de aprendizado da skill lead gravam nesse arquivo.
Uma entrada de Não reportar do projeto não rebaixa o que a Severidade da skill chama de bloqueante.

**Por quê:** na origem, a rubrica morava no `.claude/` do projeto, e a escada de aprendizado a editava: a seção Projeto
era toda do produto, e Sempre verificar e Não reportar cresciam com a calibração. No plugin, o projeto não edita skill
(o plugin muda por PR no wstack), então a parte que muda por projeto precisa de um arquivo do projeto.

**O que muda:** a 2.4 cria o modelo do arquivo no bootstrap. Mudança no texto de skill, agente ou hook do plugin, vinda
do aprendizado de um projeto, vira proposta no wstack. Sem o arquivo, vale só a rubrica do plugin.

## 2026-11-25: plugin inerte sem risk.conf

Fecha a pendência de 2026-11-24 "gates do Stop configurados pelo projeto" (o resto do comportamento num repositório sem
bootstrap).

**Decisão** (do desenvolvedor, no plano da 2.4): no repositório que não adotou o wstack os hooks de workflow ficam
inertes e só as travas de segurança continuam. "Não adotou" é `.claude/risk.conf` ausente na árvore **e** em todo
commit que o repositório aponta: HEAD, branches locais, refs remotas, tags e os reflogs, lidos sem objetos de troca
(`confAbsent` em `risk-conf.mjs`; os hooks de shell perguntam a ele com `node risk-conf.mjs --absent`, que sai 10, a regra
mora num lugar só). Na dúvida (git sem resposta, ref quebrada, node que falha), o projeto conta como adotado.
- Inertes: o `session-start` deixa de gravar `.claude/.session/` (continua dizendo a versão, a indicação do
  `/wstack:bootstrap` e o aviso do `safe.bareRepository`), o `iteration-guard` não conta, o `sessions.sh` não registra a
  sessão. O `verify-on-stop`, o
  `edit-check`, o `checkpoint-tests` e o `map-staleness` já não faziam nada sem as chaves.
- Travas que continuam: write-guard, path-guard, redirect-guard, git-read-allow, script-allow e, no push-guard, a
  branch padrão recusada (`main`, `master` e a do `origin/HEAD`, que faz as vezes do `default_branch`), o force e o
  núcleo de caminhos protegidos. O que deixa de acontecer é o pedido forçado para toda branch fora dos prefixos de
  atividade: sem `risk.conf` não há prefixos, e a decisão volta para as regras e o modo da sessão.

**Por quê:** o setup da nuvem instala o plugin no escopo do usuário, e ele roda em todo repositório do ambiente. Gravar
`.claude/` num projeto alheio e pedir aprovação para todo push é atrito sem proteção; as travas de segurança não
dependem de o projeto ter adotado o workflow.

**Risco aceito e o que o fecha:** apagar o arquivo da árvore, ou pôr o HEAD num commit anterior ao bootstrap (um
checkout que não cita a trava), não liga o modo inerte enquanto o arquivo estiver em alguma branch ou ref remota: o hook
continua na falha fechada de antes. A primeira versão olhava só o HEAD, e a revisão CRITICA da 2.4 mostrou o checkout
afrouxando o push-guard (achado bloqueante, corrigido antes do commit). A revisão do delta achou mais dois caminhos, também
corrigidos: um `git replace` que troca a ponta (ou a subárvore `.claude`) por uma sem o arquivo, fechado lendo o git com
`GIT_NO_REPLACE_OBJECTS=1` (também no push-guard e no protected-paths, que o mesmo replace cegava antes da 2.4); e
`git branch -d` com `-d -r`, que apagam as branches e as refs de rastreio sem citar a trava, fechado pelos reflogs (lidos também com o HEAD numa branch órfã).
Sobra limpar também os reflogs (`git reflog expire`), uma sequência de comandos que um a um não citam a trava: o hook é
cinto de segurança, não fronteira (Riscos aceitos em `docs/harness-capabilities.md`). Um commit que apaga o arquivo é
mudança em caminho protegido, e publicá-lo pede aprovação. No modo inerte, destino em
espaço de nome do git (`refs/tags/...`, `tags/...`) continua pedindo: tag não é branch. Provas: `test-inert.sh`,
`test-push-guard.sh` (projeto sem `risk.conf`, tag, arquivo apagado da árvore, HEAD num commit anterior ao bootstrap),
`test-risk-conf.sh` (inclui ref quebrada, replace, reflog, branch órfã e 20 mil refs); os três reprovam o código anterior.

## 2026-11-25: versão do plugin fixada por tag, instalada pelo setup da nuvem

Fecha as pendências de 2026-11-24 "destinos do inventário" (conferir a versão fixada na 2.4) e "no ambiente do wstack, o
plugin vem do clone" (como o ambiente de outro projeto se atualiza).

**Decisão** (do desenvolvedor, no plano da 2.4): o `settings.json` modelo declara o marketplace `wstack` com
`"ref": "v<versão>"`, a tag do wstack para aquela versão do `plugin.json`. Cada versão publicada ganha a tag na `main`,
depois do merge. O `cloud/setup.sh` lê essa referência do `.claude/settings.json` do projeto (só com `enabledPlugins`
ligado, fonte `github` e repositório e ref no alfabeto fechado) e instala o plugin nela, no escopo do usuário; o
`--check` (que o `cloud-services.sh` põe no contexto) acusa plugin ausente ou em outra versão. Sem `ref`, o setup não
mexe no plugin (é o caso do ambiente do próprio wstack, que instala do clone).

**Evidência** (Claude Code 2.1.332, HOME isolado):
- `claude plugin marketplace add "wesllenm/wstack#<sha>" --scope project` gravou `"ref": "<sha>"` na fonte do
  marketplace, e o `install` trouxe a versão daquele commit (0.0.10), registrada com `version` e `gitCommitSha` em
  `installed_plugins.json`.
- Com a entrada já declarada nas configurações do usuário, `marketplace add` com outra ref é recusado ("its source
  doesn't match its extraKnownMarketplaces entry"); `marketplace remove`, `add` com a ref nova e `install` levam à
  versão nova. O setup faz essa sequência só quando o instalado não confere.
- A instalação real pelo `setup.sh` num repositório sintético instalou o commit fixado; o `--check` saiu 0 e a segunda
  rodada reconheceu a versão instalada.
- `claude plugin validate plugin` e `claude plugin validate .` passaram.

**O que muda:** container restaurado do guardado não roda o setup (decisão de 2026-11-24); a versão nova chega na
montagem seguinte ou rodando o `setup.sh` na sessão, que o aviso do `--check` manda fazer. Até a tag `v0.0.11` existir
no GitHub, o bootstrap fixa no commit (`--ref <sha>`, a skill confere com `git ls-remote --tags`).

## 2026-11-25: plugin antes do bootstrap na nuvem

**Contexto:** o setup só instalava o plugin com a versão fixada no `.claude/settings.json` do projeto, que só existe
depois do `/wstack:bootstrap`. A primeira sessão de um projeto novo na nuvem subia sem o plugin, então sem o bootstrap;
e cada sessão começa num contêiner novo, então instalar à mão numa sessão não vale para a seguinte. Adotar exigia um
passo no Claude Code local.

**Decisão** (do desenvolvedor, no plano da unidade seguinte à 2.4: "a ideia era já nascer na nuvem"): o projeto cujo
`settings.json` não cita `wstack@wstack` (ou que não tem `settings.json`) recebe do setup a maior tag
`v<maior>.<menor>.<correção>` do wstack no GitHub (`git ls-remote --tags`, ordenada por versão; pré-release e tag fora
desse formato ficam de fora), instalada como a versão fixada. O projeto que cita o plugin sem `ref` continua sem
instalação pelo setup (o ambiente do próprio wstack). Sem rede ou sem tag, só aviso. O `session-start` do projeto sem
`risk.conf` passa a indicar o `/wstack:bootstrap`.

**Por quê:** a tag é versão publicada e é a mesma que o bootstrap vai fixar, então a troca para a versão fixada não
reinstala nada. Instalar a `main` levaria código não publicado a toda máquina; embutir a versão no `setup.sh`
envelheceria no texto colado no ambiente. Sem `risk.conf` o plugin fica inerte, salvo as travas (plugin inerte sem
risk.conf), então ele ligado num repositório que não vai adotar o wstack não grava nada nem pede aprovação a mais.

**Evidência:** `test-cloud-setup.sh` (tags `v0.0.9`, `v0.0.10`, `v0.0.11` e duas fora do formato num repositório local
visto como o GitHub pelo `insteadOf`: instala a `v0.0.11`; sem tag, só aviso; projeto sem `ref` não muda);
`test-inert.sh` (a indicação do bootstrap só sem `risk.conf`); o `setup.sh` real num repositório vazio, `HOME`
isolado, clonou a `v0.0.11` do GitHub e instalou o commit `b5488ba`, e o `--check` saiu 0.

## 2026-11-25: modelos do projeto e bootstrap determinístico

**Decisão:** os arquivos que o projeto mantém ficam em `plugin/templates/` e o `/wstack:bootstrap` os copia por um
script (`scripts/bootstrap.sh`) que nunca sobrescreve, nunca grava através de link e só troca marcadores de alfabeto
fechado; o resto (comandos, globs, domínios) a skill preenche depois da aprovação única. Entram também
`.claude/project.md` e `.claude/architecture.md`, que o inventário não listava mas a skill lead e o planner citam (a
tabela Domínios), e `docs/gotchas.md` e `docs/decisions.md`, que o `CLAUDE.md` modelo importa ou cita. A `verify-<app>`
entra como esqueleto, só com `--app`, e é escrita e provada pela skill. O script pede aprovação de propósito (grava no
projeto): fica fora do `script-allow`.

**Por quê:** a cópia é a parte em que um erro custa caro (apagar a configuração que o projeto já tem) e é
determinística; o preenchimento depende do diagnóstico e fica com o modelo, na aprovação única. Os testes do plugin
passam a ler os modelos no lugar das fixtures da 2.2, e os dois casos fracos anotados ali deixam de ser triviais.

**O que muda:** as `review_rule` do modelo apontam para checklist do próprio projeto: o `review-dispatch.mjs` exige o
arquivo dentro do projeto, então os checklists de `review-rubric/reference/paths/` do plugin não podem ser citados ali
(follow-up). O gate de aprendizado do Stop passa a tratar `docs/gotchas/` e `docs/review-rubric.md` como arquivos de
aprendizado, onde a escada da skill lead grava desde a 2.3.

## 2026-11-25: skill lead em núcleo e leitura sob demanda

**Decisão:** o `SKILL.md` da skill `lead` fica só com o que vale em toda tarefa (classificar, planejar, aprovação
única, roteamento, testes, as duas velocidades da revisão, commits, pipeline, interrupções, stop condition, aprendizado
e relatório). O detalhe que só parte das tarefas usa vai para `plugin/skills/lead/reference/`: `revisao.md`,
`delegacao.md`, `limpeza.md`, `sessao.md`, `paralelo.md`, `nuvem.md`, `lote.md` e `aprendizado.md`. A tabela Leitura sob
demanda do núcleo diz quando ler cada um, e cada seção que saiu deixa no núcleo um parágrafo com o gatilho e o que não
muda em nenhum caso. O texto foi movido sem reescrita; só mudaram as referências cruzadas e `${CLAUDE_PLUGIN_ROOT}`,
que em `reference/` vira `<plugin>`. A primeira mensagem de toda tarefa passa a trazer as linhas Objetivo e Menor
mudança, e o plano parte delas.

**Por quê:** com 76 KB carregados em toda tarefa, as regras do meio do arquivo eram as que mais se perdiam. O núcleo
ficou com cerca de 43 KB, e o detalhe passa a ser lido no momento em que é usado, mais perto da ação. A linha de menor
mudança segura o escopo antes de o processo crescer em volta dele.

**O que muda:** o relatório ganha os campos Objetivo e menor mudança e Referências lidas; arquivo que o momento pedia e
não foi lido conta como passo pulado. O `test-skills-agents.sh` passa a conferir os caminhos `${CLAUDE_PLUGIN_ROOT}/skills/…`,
os scripts na forma `<plugin>/scripts/<x>` de `reference/` e que todo `reference/<x>.md` seja citado no `SKILL.md` da
skill. Que o modelo leia o arquivo no momento certo é orientação, sem hook que confira: o campo Referências lidas e a
calibração mostram se falha.

## 2026-11-25: correção do desenvolvedor registrada na hora (skill `correct`)

**Decisão:** a skill `correct` (`/wstack:correct`, ou carregada pelo `lead` quando o desenvolvedor corrige o agente)
corrige o trabalho em curso, escreve a correção como fato de uma linha, procura se ela já estava escrita (primeira,
ignorada ou repetida), escolhe o degrau da escada de correção e grava tudo na seção Correções do `.claude/SESSION.md`.
Texto do projeto (degraus 3 a 5) é aplicado na hora. Mecanismo (degraus 1 e 2), hook, `settings.json` e texto do plugin
ficam como proposta para o relatório. O passo Aprendizado do `lead` consome a seção, e o Clean state check exige destino
para cada linha.

**Por quê:** a escada já promovia na primeira vez a correção vinda do desenvolvedor, mas só no fim da tarefa. A correção
feita no meio se perdia em compactação, reinício da VM ou interrupção. O `SESSION.md` já é arquivo de aprendizado para o
gate do Stop (gravar nele não dispara build) e já é lido no Início e no Aprendizado.

**O que não faz:** nenhum hook detecta a correção. Que a skill seja carregada depende do gatilho da `description` e da
linha na seção Aprendizado do `lead`; o `/wstack:correct` cobre o caso em que o modelo não percebe. Um `UserPromptSubmit`
que reconheça correção por texto fica para quando a calibração mostrar correções perdidas.

## 2026-11-25: playbooks por tipo de tarefa na skill lead

**Decisão:** depois de classificar o risco, o `lead` escolhe o tipo da tarefa pela tabela Tipo de tarefa do núcleo e
põe os passos do playbook na lista de tarefas. Só três tipos ganham playbook, em `plugin/skills/lead/playbooks/`, porque
só eles mudam a sequência de passos: `bug.md` (reproduzir, achar a causa, corrigir), `investigacao.md` (hipóteses e
evidência, sem diff nem commit; a resposta substitui o relatório) e `performance.md` (alvo, linha de base, uma mudança
por vez medida de novo, ganho preso por teste). Feature segue o Pipeline do nível; refatoração, auditoria de testes,
manutenção do aprendizado e retomada apontam para o que já existia (skill `refactoring`, Pipeline, `aprendizado.md`,
`sessao.md`).

**Por quê:** o nível de risco decidia quanto processo aplicar, mas tratava toda tarefa como "implementar uma mudança".
Um bug corrigido sem reprodução e sem causa, ou uma otimização sem linha de base, passam por todos os gates e continuam
errados. Risco e tipo são eixos separados: um bug CRITICA segue o playbook de bug com os gates da CRITICA.

**O que muda:** o Registro aceita `investigação` no lugar do nível (o `summarize-runs.mjs` a conta) e o relatório ganha
o campo Tipo. O `test-skills-agents.sh` aplica a `playbooks/` as mesmas regras de `reference/`. Que o tipo seja escolhido
e o playbook lido é orientação; o campo Referências lidas do relatório mostra quando não foi.

## 2026-11-25: interrogatório por outro fornecedor e arena de design

**Decisão (interrogatório):** o `interrogate.mjs` manda o pacote de revisão de COMPLEXA e CRITICA para os modelos que
o projeto declara em `interrogate_cmd` no `risk.conf` (`<nome> <comando>`, um por modelo; o comando lê o pedido da
entrada padrão). Cada modelo tenta quebrar o diff e devolve candidatos no formato da `review-rubric`, que passam pela
ancoragem do `check-findings.mjs` e pelo `review-verifier` como os das lentes: um ataca, o outro confirma. Desligado
por padrão. O `script-allow` o aprova sem pedido porque o consentimento é o `interrogate_cmd`, num arquivo que já é
trava (ask/deny).

**Por quê:** as lentes, o verificador e o `review-critical` são todos do mesmo fornecedor, e erram parecido. Um modelo
de outro fornecedor tende a errar diferente. O plugin não escolhe fornecedor nem guarda chave: o comando é do projeto,
como os `verify_*`.

**Riscos aceitos:** o pacote sai da máquina para o fornecedor, então ligar é decisão registrada no `docs/decisions.md`
do projeto (em projeto de cliente, decisão do cliente). O diff pode trazer texto hostil para o modelo externo: a CLI
deve ser configurada sem ferramentas de escrita nem de execução, e a saída dele só vira correção depois do verificador.
O ganho ainda não foi medido: o relatório conta por modelo os candidatos, os descartados na ancoragem e os
confirmados, e a manutenção do aprendizado decide se o interrogatório fica.

**Decisão (arena):** em decisão de design cara de reverter (modelagem de domínio, contrato público, forma do dado
persistido), no plano de COMPLEXA ou CRITICA, dois ou três `planner` em paralelo com posturas diferentes, critérios
escritos antes das propostas, e protótipo em worktree por `implementer` só para critério que só se decide rodando. A
comparação vai ao plano, e a aprovação única decide. Arena de N implementações completas para juntar as melhores partes
ficou de fora: juntar partes que tocam o mesmo invariante é uma proposta nova, e o custo de integrar e revisar N
implementações não se paga onde a decisão difícil é de design.

## 2026-11-25: princípios citados na decisão

**Decisão:** o campo Skills usadas do relatório vira Princípios aplicados, `skill — regra — decisão que mudou`, um por
linha, e só vale skill carregada na sessão e regra que fez o plano ou o código sair diferente; `nenhum` é resposta
válida. No fechamento, o `principles.mjs` lê a transcrição da sessão e dos subagentes, lista o que foi carregado
(ferramenta Skill, `/comando`, pré-carga dos agentes chamados) e lido (`reference/`, `playbooks/`), e recusa citação sem
leitura. A linha de Registro ganha `— princípios: <citadas> (carregadas: N)`, que o `summarize-runs.mjs` conta.

**Por quê:** "Skills usadas" listava o que foi carregado, não o que mudou alguma coisa, e não havia como conferir. Com a
citação presa a uma decisão e a leitura conferida na transcrição, o raciocínio fica auditável e a manutenção de 90 dias
ganha o dado que o orçamento de complexidade pedia: skill carregada e nunca citada tem gatilho largo ou texto que não
muda decisão; skill que nem aparece é candidata a sair.

**O que muda:** as skills de engenharia continuam como estão (já eram skills separadas e curtas). O `principles.mjs`
pede aprovação, como o `permission-asks.mjs`, porque lê a transcrição. Que a regra citada tenha de fato mudado a
decisão continua sendo palavra do relatório: o script só garante que ela foi lida.

## 2026-11-25: skills de entender código (`how` e `why`)

**Decisão:** duas skills só de leitura, fora do pipeline de risco do `lead` (sem classificação, plano, aprovação nem
Registro), invocáveis por `/wstack:how` e `/wstack:why` ou pela `description`, e válidas em repositório sem o wstack
adotado. A `how` segue o caminho da entrada ao efeito lendo o código, com `arquivo:linha` em cada passo e o que foi
deduzido sem abrir separado em Não verificado. A `why` acha no histórico o commit que mudou o significado do trecho
(`git log -L` e `git log -S`, que o `git-read-allow` aprova; `git blame` pediria permissão), o PR e a revisão, as
decisões e os gotchas, e separa motivo registrado de inferido.

**Por quê:** perguntar algo sobre o código exigia passar pelo `lead` ou chamar o `explore` à mão, e o `explore` devolve
localização, não explicação nem motivo. Em projeto de cliente, entender antes de mudar é a maior parte do trabalho.
Separar registrado de inferido importa porque a pergunta "por que isso está aqui" costuma preceder "posso tirar?".

**O que não faz:** não decide se o código pode sair, não roda experimento (isso é o playbook de investigação) e não
reescreve o histórico de onde a resposta vem: em clone raso, diz que o histórico acaba ali.

## 2026-11-25: texto técnico em PT-BR sem enfeite (skill `unslop`)

**Decisão:** a skill `unslop` reúne as regras de escrita para commit, PR, documentação, relatório e comentário de
revisão em português: o que cortar, o que trocar, formato e a gramática que texto gerado erra. O que dá para checar por
padrão foi para o `slop-check.mjs`. **Erro** é o que sempre sai: abertura e fecho vazios, "este commit", muleta de
ênfase, gerundismo, "a nível de", "o mesmo" como pronome e emoji. **Aviso** é palavra suspeita, que só fica se disser
algo concreto. A skill `commit` passa a escrever a mensagem num arquivo da pasta temporária, rodar o script e commitar
com `git commit -F <arquivo>`. O corpo do PR passa pelo mesmo script antes do `gh pr create`.

**Por quê:** os commits são em português, e as listas de anti-slop que existem são de inglês. Erro e aviso ficaram
separados porque palavras como "otimizar" e "através de" têm uso legítimo. Nos commits desta branch, o script deu um
aviso e nenhum erro; em `docs/decisions.md`, dois avisos legítimos.

**O que não faz:** não julga clareza nem estrutura, que continuam com a skill. Não é hook: rodar antes do commit é
orientação da skill `commit`. O script imprime só a linha e o padrão, nunca o texto, porque o `script-allow` o aprova
sem pedido e ele não pode servir para ler um arquivo protegido por tabela.

## 2026-11-26: núcleo do lead menor e Registro com princípios exigido no Stop

**Decisão (núcleo):** saem do núcleo, sem reescrita, para `reference/`: a sequência por nível (`pipeline.md`), o Clean
state check, os scripts que completam a linha de Registro e o modelo do relatório (`fechamento.md`), a triagem de
medições, o caminho pesado por extenso e o fluxo de banco (`revisao.md`), as regras ao subir na escada
(`aprendizado.md`), a retomada (`sessao.md`) e o início em worktree (`paralelo.md`). No núcleo fica um gatilho com o
que não muda. Medido com `wc -w`: de 6.926 para 4.939 palavras. O que sobra é o que vale em toda tarefa: Início,
aprovação única, tipo de tarefa, classificação, roteamento, duas velocidades, interrupções e a escada.

**Por quê:** o núcleo vai pré-carregado inteiro no agente, e as regras do meio eram as que mais se perdiam. A meta de
cerca de 4 mil palavras não foi atingida porque cortar mais faria o agente ler arquivo em toda tarefa.

**Decisão (Stop):** depois de commit de código na sessão, o gate de aprendizado também exige `princípios:` numa linha
acrescentada ao Registro desde o início da sessão. Antes, rodar o `principles.mjs` era só orientação.

**O que não faz:** o gate confere o campo, não que o script rodou; escrever o campo à mão passa. É um degrau acima do
texto (a linha não sai mais sem o campo) e abaixo de rodar o script no hook, que exigiria o caminho da transcrição no
`Stop` e aprovação para lê-la.

## 2026-11-26: o bootstrap pergunta sobre a revisão por outro fornecedor

**Decisão:** a proposta do `/wstack:bootstrap` sempre tem a linha "Revisão por outro fornecedor", com o custo dito por
extenso: o diff de COMPLEXA e CRITICA sai da máquina para o fornecedor do modelo. O diagnóstico levanta as CLIs
disponíveis e se o repositório é de cliente. Sem CLI, o padrão é não ligar. Ligada ou não, a escolha vai para o
`docs/decisions.md` do projeto.

**Por quê:** o `interrogate.mjs` só roda com `interrogate_cmd` no `risk.conf`, e o bootstrap não tocava nessa chave.
O revisor de outro fornecedor ficava desligado em todo projeto sem que ninguém tivesse decidido isso. Mandar código
para terceiros continua sendo decisão do projeto; o que muda é que ela passa a ser tomada e registrada.

## 2026-11-26: Stop confere o conteúdo do Registro; interrogate falha fechado

**Decisão (Stop):** com `transcript_path` na entrada (campo comum dos hooks, documentado), o gate de aprendizado roda o
`principles.mjs --cited` sobre a lista de `princípios:` da linha de Registro e o `permission-asks.mjs` sobre a
transcrição da sessão e dos subagentes (`<sessão>/subagents`). Bloqueia skill citada que não foi carregada e
`pedidos:` ausente ou menor que a contagem da transcrição. Isso substitui a decisão do mesmo dia que conferia só a
presença do campo.

**Por quê:** a conferência só de texto passava com `princípios: ok`. Agora o gate roda o mesmo script que o fechamento
manda rodar, e a garantia deixa de depender do modelo. `pedidos:` é conferido por baixo e não por igualdade, porque a
transcrição pode estar atrasada em relação ao turno atual, o que só diminui a contagem; igualdade bloquearia por atraso.

**Decisão (interrogate):** quando nenhum modelo responde no formato, a saída é `falhou: <modelo — motivo>; ...` com
código 4, nunca `sem achados`. Na CRITICA isso bloqueia o commit até o desenvolvedor decidir; na COMPLEXA vai como
pendência. Pasta de saída sem escrita sai 2 antes de chamar os modelos.

**Por quê:** um modelo que estourava o prazo virava "sem achados", e um interrogatório que não aconteceu passava por
um que não achou nada.

## 2026-11-26: conferência do Registro no Stop falha fechada

**Decisão:** na conferência contra a transcrição, o `Stop` só passa quando o `principles.mjs` sai 0 e o
`permission-asks.mjs` sai 0 com a contagem. Qualquer outro código (script ausente, arquivo ilegível, uso errado, node
ausente) bloqueia com "não consegui verificar". A transcrição ausente continua como aviso, não bloqueio.

**Por quê:** só o código 3 bloqueava, e o `permission-asks.mjs` com saída vazia pulava a checagem: o gate passava
justamente quando não conseguia conferir. Ler o `transcript_path` também conta como conferência: node ausente ou entrada que não é JSON bloqueia, em vez de cair no aviso. Transcrição ausente é outro caso: acontece em Claude Code sem
`transcript_path` e em execução manual, e bloquear ali travaria sessões legítimas.

## 2026-11-26: Stop portável e sem falha aberta por ambiente

**Decisão:** a impressão digital que dispensa nova verificação passa a ser do `git hash-object` (o hook já exige o
git), sem `sha1sum` nem `xargs -r`; impressão vazia não dispensa a verificação nem grava carimbo. O stderr do node que
lê o `transcript_path` vai para outro arquivo, para um aviso do node não virar caminho. Sem `session_id` na entrada,
com o arquivo de calibração, o gate de aprendizado bloqueia em vez de ser pulado.

**Por quê:** no macOS padrão não há `sha1sum`; a impressão ficava vazia, casava com o carimbo vazio da passada
anterior, e build e testes eram pulados sem aviso. Os outros dois casos também passavam sem conferir. Na nuvem (Linux)
o primeiro não acontecia, mas o hook roda igual no terminal local.

## 2026-11-26: `verify-blocked.md` libera o que o ambiente não deixou conferir

**Decisão:** os bloqueios de "não consegui verificar" (entrada sem `session_id`, script de conferência ou node
quebrados) passam a ser liberados por `.claude/verify-blocked.md`, como o build já era, com o motivo no
`systemMessage` para o desenvolvedor. Divergência de conteúdo no Registro (skill citada sem carga, `pedidos:` abaixo
ou ausente, campo `princípios:` ausente) continua bloqueando com o arquivo presente. Sem o HEAD do início da sessão, o
gate de aprendizado avisa em vez de ser pulado em silêncio. O motivo vai cortado em 300 bytes sem partir caractere.

**Por quê:** as mensagens mandavam registrar o motivo no arquivo, mas o bloqueio saía antes de ele ser lido: com o
ambiente quebrado, o agente registrava, tentava encerrar e era bloqueado de novo, até alguém consertar à mão.
Divergência de conteúdo fica de fora porque o agente resolve corrigindo a linha, e liberar por arquivo seria o
contorno que o gate existe para impedir. O corte antigo em bytes partia a letra acentuada, que chegava como U+FFFD.

## 2026-11-26: exceção de verificação amarrada à sessão

**Decisão:** o `.claude/verify-blocked.md` só vale com a linha `sessão: <session_id>` da sessão atual (entrada sem
`session_id`: `head: <SHA do HEAD>`). As mensagens de bloqueio mostram a linha exata a escrever. Arquivo de outra
sessão é ignorado com aviso, e os gates rodam. O `SessionStart` avisa quando o arquivo existe. O `session_id` só é
aceito no alfabeto `[A-Za-z0-9_-]`, porque vira caminho de arquivo.

**Por quê:** desde a decisão anterior o arquivo libera, além de build e testes, as conferências do Registro que o
ambiente impediu. Sem dono nem prazo, um registro esquecido de semanas atrás desligava os gates de todas as sessões
seguintes, sem ninguém perceber.

## 2026-11-26: só o desenvolvedor cria a exceção de verificação, e ela vale uma vez

**Decisão:** gravar `.claude/verify-blocked.md` pede aprovação: o `write-guard` devolve `ask` para Edit e Write nesse
caminho (pela ferramenta, então vale também na nuvem), e o `path-guard` e o `ask` do `settings.json` modelo pegam o
caminho pelo Bash, como já faziam com o `.verify-ok`. A exceção vale para um encerramento: o `Stop` a apaga ao usar.
As mensagens de bloqueio dizem que a exceção depende da aprovação do desenvolvedor.

**Por quê:** o agente escrevia a exceção sozinho, e as mensagens entregavam a linha pronta com o `session_id`: sob
pressão para terminar, o build quebrado virava exceção, e os gates viravam conselho. A garantia do wstack vem de hook,
não da boa vontade do modelo. O uso único cobre o que prender ao fingerprint cobriria (a exceção não vale para o
código editado depois nem para os encerramentos seguintes), sem o hook precisar calcular o fingerprint antes do gate
de aprendizado.

**Risco aceito:** na nuvem a trava de texto do Bash é livre (decisão "trava por texto na nuvem"), então um
redirecionamento pelo Bash grava o arquivo sem pedir. A ferramenta de escrita pede; o Bash na nuvem fica com o PR e o
CI como barreira, como o resto do harness ali.

## 2026-11-26: exceção usada segura o push até a verificação verde

**Decisão:** quando o `Stop` libera um encerramento pela exceção de verificação, ele grava
`.claude/.session/unverified` (motivo, sessão, HEAD). Enquanto o marcador existe, o `push-guard` recusa todo push de
branch, só o checkpoint `wip/` passa. O marcador sai quando um `Stop` termina com todos os gates verdes, em qualquer
sessão. A pasta `.claude/.session` deixa de contar como código no gate, mesmo sem a linha no `.gitignore`.

**Por quê:** na nuvem a trava de texto do Bash é livre (decisão "trava por texto na nuvem"), então o agente consegue
gravar a exceção pelo Bash sem pedir. Pedir aprovação ali travaria a sessão, porque muitas vezes ninguém responde. A
garantia vai para o que sai da máquina: o agente consegue encerrar, mas nada sem verificação chega a um PR. O marcador
vale para o repositório, não para a sessão, para uma sessão nova não enviar os mesmos commits.

**Limite:** um push que não passa pelo Bash (ferramentas de API do GitHub que gravam arquivo direto) não é visto pelo
`push-guard`. A barreira ali continua sendo o CI do PR.

## 2026-11-26: o marcador de verificação pendente só sai com verificação de verdade

**Decisão:** substitui, na entrada anterior, a regra de limpeza e o marcador único.
- O `Stop` só apaga o marcador quando o build e os testes rodaram nesse encerramento e passaram. Árvore limpa, carimbo
  de verificação anterior e projeto sem comandos `verify_*` não contam: com o marcador, o build roda mesmo sem mudança
  pendente, sobre o que está commitado.
- O HEAD do encerramento pela exceção fica gravado no marcador (`head: <SHA>`), e o marcador só sai quando o HEAD
  verificado descende dele.
- Um marcador por sessão (`.claude/.session/unverified-<sessão>`, `unverified-sem-sessao` sem `session_id`). O
  `push-guard` recusa o push se existir qualquer um. Só o encerramento verde da própria sessão apaga o dela; o de uma
  sessão encerrada fica para o desenvolvedor, e o `SessionStart` avisa que ele existe.
- `.claude/.session/` e `.claude/verify-blocked.md` ficam fora do alcance do agente também na nuvem, com deny: o
  `write-guard` recusa gravar em `.claude/.session/`, e o `path-guard` recusa comando de Bash que cita o marcador,
  apaga, move ou copia algo em `.claude/.session/` ou roda de dentro dela. Na nuvem, também comando que cita
  `.claude/verify-blocked.md`. Fora da nuvem a exceção continua pedindo aprovação.

**Por quê:** a limpeza dependia só do código de saída 0. O fluxo normal do lead depois da exceção é commitar e
encerrar; com a árvore limpa o hook saía 0 sem rodar nada e apagava o marcador, e o push saía sem verificação. Com um
marcador só, o verde de uma sessão liberava o push dos commits sem verificação de outra. Na nuvem a trava de texto era
livre, então o agente apagava o marcador pelo Bash sem pedir.

**Limite:** a trava do Bash continua sendo por texto. Um comando que monta o caminho para esconder (variável, `eval`)
passa, como nas outras travas por texto (ver Riscos aceitos em `docs/harness-capabilities.md`).

## 2026-11-26: todo o estado dos hooks fora do alcance do agente, e marcador só com a árvore limpa

**Decisão:** completa a entrada anterior.
- O `path-guard` recusa, também na nuvem, comando que cita qualquer coisa em `.claude/.session/` ou o carimbo
  `.claude/.verify-ok`, inclusive `.session/` de dentro de `.claude` e glob logo abaixo de `.claude/`. Leitura pura
  (`cat`, `ls`, `grep`) segue livre. O `write-guard` recusa gravar o `.verify-ok` além de `.claude/.session/`.
- O `Stop` só apaga o marcador com a árvore limpa. Verde com mudança sem commit mantém o marcador e pede o commit no
  `systemMessage`. O carimbo deixa de contar como código.
- Saída sem verificação com o marcador desta sessão (sem comandos `verify_*`, sem o arquivo da solução) avisa no
  `systemMessage` que o push segue recusado.

**Por quê:**
- O `checkpoint-ok` e o `.verify-ok` ficavam só na entrada geral do `path-guard`, que o modo nuvem desliga: um `touch`
  pulava os testes do checkpoint, e um carimbo forjado pulava os do `Stop`.
- O verde sobre a árvore de trabalho apagava o marcador mesmo com o conserto sem commit, e o push levava o HEAD
  vermelho.
- Sem aviso, o push recusado não tinha explicação.

## 2026-11-26: o marcador preso diz como destravar

**Decisão:** a recusa do `push-guard` e o aviso do `SessionStart` trazem o comando que apaga os marcadores
(`rm -f .claude/.session/unverified-<sessão>`), para o desenvolvedor rodar fora do agente. O `Stop` verde sobre a
árvore limpa, quando o HEAD gravado no marcador saiu do histórico (amend, rebase, reset), mantém o marcador e mostra o
mesmo comando no `systemMessage`. Marcador sem a linha `head:` (repositório sem commit na hora da exceção) sai com o
verde sobre a árvore limpa, sem a conferência de histórico.

**Por quê:** depois de reescrever o commit da exceção, o marcador não sai mais naquela sessão, e o agente não pode
apagá-lo. Sem o comando na mensagem, o primeiro caso vira investigação. Um script de destravar no plugin seria
chamável pelo agente (o `path-guard` libera os scripts do plugin na raiz), então a mensagem traz o `rm`, que o
`path-guard` recusa ao agente.

**Complemento:** o `rm -f` da recusa só lista nomes no formato que o `Stop` grava (`unverified` ou
`unverified-<sessão>` com `[A-Za-z0-9_-]`), para a linha não levar nada que o shell interprete. Um arquivo
`unverified*` com outro nome segura o push do mesmo jeito, e a recusa avisa que ele existe. O aviso do `Stop` sem
comandos `verify_*` ou sem o arquivo da solução também traz o comando. Sem `CLAUDE_PROJECT_DIR` e fora de repositório
git, o `push-guard` recusa o push, porque não dá para procurar os marcadores.

## 2026-11-26: revisão com prova por execução, lacuna de lente e comentário de restrição

Lote 1 das melhorias trazidas do pstack (`cursor/plugins/pstack`, skills `interrogate`, `swarm` e `no-comments`).

**Decisão:**
- **Prova por execução.** O candidato ganha o campo `prova: <comando> → <saída esperada da falha>`. Ela é
  obrigatória em bloqueante e importante, salvo `reuse`, `simplicity` e `scope`, cuja evidência é outro trecho de
  código. Sem ela, o `check-findings.mjs` marca `situação: a confirmar` e mantém o candidato. O `review-verifier` roda
  a prova antes de confirmar, anexa comando e saída (`execução:`), e prova que não reproduz vira `refutado por
  execução`. Candidato a confirmar só é confirmado se o verificador escrever e rodar uma prova. As provas rodam com as
  travas de Bash de sempre.
- **Lacuna de lente.** Cada lente termina com `status: achados`, `status: sem achados` ou `status: falhou: <motivo>`.
  O `check-findings.mjs` lê um arquivo por lente: sem status, com status que contradiz o conteúdo ou com falha, a
  lente é lacuna, o script sai 4 e nunca imprime `sem achados`. O lead chama a lente de novo uma vez; na segunda
  falha, em CRITICA a lacuna em lente obrigatória bloqueia o commit, e em SIMPLES e COMPLEXA vira pendência no
  `SESSION.md`. O `interrogate.mjs` fecha a lista com `status: achados`.
- **Comentário de restrição.** O `diff-smells.mjs` separa como `RESTRICAO` o comentário novo, fora de documentação,
  que descreve uma regra ("não", "nunca", "sempre", "deve", "obrigatório" e os equivalentes em inglês). A
  `review-simplicity` propõe a garantia no degrau mais alto da escada do `correct`, como nit; a garantia só é
  implementada com aprovação no plano. A restrição conta no limite de comentários do `--gate`, como antes.

**Por quê:** um achado plausível e errado chegava à correção porque a ancoragem só prova que o trecho existe. Uma
lente que estourava o tempo ou respondia fora do formato podia ser lida como "sem achados", a mesma falha aberta já
corrigida no interrogate. E regra escrita em comentário só vale enquanto o modelo a lê.

**Divergências do documento de trabalho:** a rubrica usa `bloqueante | importante | nit`, não "alta" e "crítica"; a
prova obrigatória ficou em bloqueante e importante de comportamento. O `lote.md` descreve codemod por script e não
tem workers, então a regra de status não se aplica a ele. `TODO`, `HACK` e `workaround` já eram `MARCADOR`, com gate
mais estrito, e continuam assim. Comentário de documentação (`///`, `/** */`) segue `DOC`: contar a restrição dele no
limite apertaria o gate em todo projeto com documentação XML.

**Limite:** repetir a lente, tratar a lacuna e rodar a prova são orientação ao lead e ao verificador; o mecanismo é
o `check-findings.mjs`, que garante que lacuna e falta de prova aparecem na saída.
