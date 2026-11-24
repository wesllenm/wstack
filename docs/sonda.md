# Sonda de instalação do wstack

Registro das sondas 1 e 2. As peças delas (skills `sonda` e `sonda-caminhos`, hooks e scripts `sonda-*`, as regras
`allow` de teste do `.claude/settings.json`) saíram na versão 0.0.4, quando os hooks reais entraram no plugin.

| Fato | Como aparece | Se falhar |
|---|---|---|
| 1. Instala sozinho pelo `.claude/settings.json` numa sessão na nuvem | `wstack <versão> carregado.` no início da sessão | instalação vira passo do setup script (`claude plugin marketplace add` + `install`) |
| 2. Os hooks do plugin rodam | `ask` do hook no registro da sessão para o `echo wstack-sonda` (o diálogo só aparece fora do modo automático) | hooks ficam no projeto, gerados pelo bootstrap |
| 3. Os hooks leem a configuração do PROJETO | `sonda = projeto-wstack` no pedido e na mensagem | o caminho do projeto vem de outro jeito (cwd do payload) |
| 4. Funciona com o repositório privado | os três acima com o repositório privado | o repositório fica público, ou o ambiente recebe acesso |

Roteiro: depois do push na main, abrir uma sessão NOVA neste repositório e pedir "rode a sonda do wstack"; trazer a
linha final `sonda: ...`.

## Resultado da primeira rodada (2026-11-24)

Sessão na nuvem, repositório público, `main` em `9ecae8c`: **`sonda: falhou em 1`**.

- **Fato 1 falhou.** O `.claude/settings.json` declara o marketplace e o `enabledPlugins`, mas a sessão começou sem
  nenhum plugin instalado (`claude plugin list`: "No plugins installed"). Sem plugin, a skill e os dois hooks não
  carregaram, e os fatos 2 e 3 não tiveram como ser testados.
- **Fato 4 não é a causa.** O repositório é público e `claude plugin marketplace add wesllenm/wstack` clonou do
  GitHub sem problema.
- **A alternativa da tabela funciona.** Na mesma sessão, `claude plugin marketplace add wesllenm/wstack` e
  `claude plugin install wstack@wstack` instalaram o `wstack@wstack` 0.0.1 (escopo user, ativo). Os dois comandos
  podem rodar de novo sem erro.

Mudança feita: o ambiente de nuvem `wstack` (pessoal) ganhou este setup script, que roda quando um container é
criado do zero:

```bash
claude plugin marketplace add wesllenm/wstack
claude plugin install wstack@wstack
```

Próximo passo: abrir uma sessão NOVA no ambiente `wstack`, pedir "rode a sonda do wstack" e conferir os fatos 1 a 3
com o plugin instalado pelo setup script.

## Resultado da segunda rodada (2026-11-24)

Sessão nova no ambiente `wstack`, plugin 0.0.1 instalado pelo setup script, modo de permissão automático:
**`sonda: ok`** depois de conferir o registro da sessão (a skill 0.0.1 tinha dito `falhou em 3`).

- **Fato 1 ok.** `wstack 0.0.1 carregado.` no início da sessão, com plugin e projeto definidos.
- **Fato 2 ok.** O hook `PreToolUse:Bash` rodou no `echo wstack-sonda` e devolveu `ask`. No modo automático o
  classificador responde ao `ask` sem mostrar diálogo, e o comando rodou sem pedido visível. Por isso a skill 0.0.1,
  que esperava o diálogo, deu falso negativo.
- **Fato 3 ok.** `sonda = projeto-wstack` na mensagem do `SessionStart`, no `ask` do `PreToolUse` e no
  `.claude/risk.conf`.

Mudança feita (0.0.2): o passo 3 da skill confere o `ask` do hook no registro da sessão
(`~/.claude/projects/*/<sessão>.jsonl`) em vez de esperar o diálogo.

# Sonda 2: caminhos

Decide onde ficam os scripts que as skills e os hooks rodam: **A**, dentro do plugin, chamados por
`${CLAUDE_PLUGIN_ROOT}`; ou **B**, copiados para o `.claude/` do projeto pelo bootstrap, chamados por caminho relativo
(`bash .claude/scripts/<nome>.sh`), com regras `allow` que já sabemos que casam.

| Fato | Como a sonda prova | Peças |
|---|---|---|
| a. Uma skill do plugin chama um script do plugin por `${CLAUDE_PLUGIN_ROOT}` | o texto da skill mostra a variável trocada pelo caminho, ou o Bash tem a variável; o script imprime de que pasta rodou | `skills/sonda-caminhos`, `scripts/sonda-caminho.sh` |
| b. Uma regra `allow` do `.claude/settings.json` do projeto casa com o caminho do script | no modo que pede aprovação, o desenvolvedor nega todo pedido; o número que rodou mesmo assim foi liberado pela sua regra | `scripts/sonda-allow.sh`, regras 1 a 3 no `.claude/settings.json` |
| c. Um hook Node do plugin importa outros módulos do plugin | o hook nega `echo wstack-sonda-node` com um motivo montado por um módulo da mesma pasta e um de `lib/` | `hooks/sonda-node.sh`, `hooks/sonda-node.mjs`, `hooks/sonda-modulo.mjs`, `lib/sonda-comum.mjs` |

Os números do passo B:

| Número | O que libera | Só se aplica se | Lê-se, se rodou |
|---|---|---|---|
| 4 | nada (controle) | sempre | a sessão não está no modo que pede aprovação: o passo B não vale |
| 1 | `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-allow.sh 1)` | a = variável só no Bash | a regra libera comando com a variável escrita |
| 2 | `Bash(bash /root/.claude/plugins/cache/wstack/wstack/*/scripts/sonda-allow.sh 2)` | a = variável trocada no texto | caminho absoluto com `*` na versão casa (só serve onde a home é `/root`) |
| 3 | `Bash(bash */.claude/plugins/cache/wstack/wstack/*/scripts/sonda-allow.sh 3)` | a = variável trocada no texto | `*` no começo casa (serve em qualquer home, mas casa com qualquer pasta que termine assim) |
| 5 | o hook `sonda-node` devolve `allow` para o comando exato | sempre | a aprovação vinda de hook dispensa a regra |

A regra é comparada com o texto do comando que o agente manda, não com o caminho que o bash expande; por isso a coluna
"só se aplica se". Um 1 negado não prova que a forma da regra está errada: o Claude Code pode pedir aprovação para
todo comando com `${...}`, mesmo com regra que casa. Para o workflow, a leitura é a mesma: comando com a variável
escrita não roda sem pedido por regra.

Regra de decisão:
- **A** se a e c deram certo e rodou o 1 ou o 3 (uma regra que não depende da home). Se foi o 1, A depende de a
  variável existir no Bash, o que só esta sessão mediu.
- **A com hook aprovador** se a e c deram certo, o 1 e o 3 não rodaram e o 5 rodou. É outro desenho: o plugin aprova
  os próprios scripts por hook, comparando o comando exato (nunca um padrão). Fica para o desenvolvedor decidir.
- **B** nos outros casos. Se só o 2 rodou, B: a regra amarra o projeto à home da nuvem.

Roteiro, depois do merge na main:

1. Abrir uma sessão NOVA no ambiente `wstack` (o setup script instala o plugin da main) e trocar o modo de permissão
   para o que pede aprovação antes de cada ação (não o automático: nele um classificador responde aos pedidos e o
   passo B não mede nada).
2. Pedir "rode a sonda de caminhos do wstack". No passo A, aprovar só desta vez (nunca "não perguntar de novo": a regra
   gravada liberaria números do passo B). No passo B, negar todo pedido que aparecer com um "No" simples, sem dizer
   ao agente o que fazer diferente; se ele parar depois de uma negação, responder "continue a sonda". No passo C,
   aprovar só desta vez se aparecer pedido (não deve aparecer: o hook nega sozinho).
3. Trazer a tabela e a linha final `sonda-caminhos: a=... b=... c=...`.

## Resultado da sonda 2 (2026-11-24)

Primeira tentativa sem valor: a sessão restaurou o container guardado pelo ambiente antes da 0.0.3 ("Restored saved
setup"; o setup script não rodou), carregou o plugin 0.0.1, que não tem a skill, e estava no modo automático. A
correção do setup script está em `docs/decisions.md` (plugin atualizado ao iniciar a sessão na nuvem).

Segunda tentativa: container novo, plugin 0.0.3, modo "Accept edits". Linha da skill:
`sonda-caminhos: a=variável trocada no texto b=1,2,3,4,5 (controle 4 rodou: passo B não vale); não se aplica: 1 c=ok`.
O registro da sessão diz quem liberou cada comando (`permission_decision` no resultado de cada ferramenta):

| Passo | Veio | `permission_decision` |
|---|---|---|
| A | o texto da skill chegou com `/root/.claude/plugins/cache/wstack/wstack/0.0.3` no lugar de `${CLAUDE_PLUGIN_ROOT}`, em todas as ocorrências (até na frase que explicava a variável); o script imprimiu `rodou de /root/.claude/plugins/cache/wstack/wstack/0.0.3; CLAUDE_PLUGIN_ROOT no Bash: ausente` | `accept`, `rule`, `config` |
| B, números 4, 1, 2, 3 | rodaram | `accept`, `rule`, `config` em todos, inclusive no controle 4, que não tem regra no projeto |
| B, número 5 | rodou | `accept`, `hook`, `hook` |
| C | negado com `wstack-sonda-node: hook Node rodou; módulo da mesma pasta: ok; módulo de outra pasta: ok` | `reject`, `hook`, `hook` |

Leitura:
- **a ok:** a variável é trocada no texto da skill ao carregar; o Bash não a tem.
- **b não mensurável na nuvem:** uma regra de configuração que não é do projeto libera todo Bash (o controle saiu
  igual às regras testadas), e o registro não diz qual regra casou. As configurações da plataforma não são legíveis
  pela sessão.
- **aprovação por hook ok:** o 5 foi liberado pelo hook, não por regra.
- **c ok:** o hook Node do plugin importou um módulo da mesma pasta e um de `lib/`.

A regra de decisão não previa um passo B sem valor (o controle rodou), então ela não decide sozinha. Com a e c
certos, o 5 aprovado por hook e nenhuma regra mensurável, o desenvolvedor escolheu "A com hook aprovador"
(`docs/decisions.md`, scripts no plugin, aprovados por hook).

# Sonda 3: agentes de plugin

Os agentes do harness pré-carregam skills (`skills:`), o lead delega a uma lista fechada de agentes
(`Agent(implementer, ...)`) e é o agente da sessão (`"agent"` no `settings.json`). A documentação do Claude Code diz que
um agente de plugin se chama `wstack:<nome>` e que `hooks`, `mcpServers`, `permissionMode` e `initialPrompt` são
ignorados nele, mas não diz como `skills:` e `Agent(...)` citam nomes do plugin, se `"agent"` aceita agente de plugin, se
`memory: project` vale nele, e se contradiz sobre `${CLAUDE_PLUGIN_ROOT}` no corpo do agente. A sonda mede isso numa
sessão real; o resultado decide como a 2.3 escreve os agentes e a 2.4, o `settings.json` modelo.

| Fato | Como a sonda prova | Peças |
|---|---|---|
| 0. O plugin se atualiza ao iniciar (autoUpdate) | 0.0.5 na mensagem do `SessionStart` não basta (um container novo instala da main): vale só com o container restaurado do guardado ("Restored saved setup" no registro da sessão, que o wstack confere) ou com 0.0.4 e 0.0.5 juntas no cache e a data de atualização em `installed_plugins.json` | `session-start.sh` |
| A. `"agent": "wstack:sonda-principal"` no `settings.json` do projeto liga o agente do plugin | o prompt da sessão tem a linha `PRINCIPAL-ATIVO-<sufixo>` (o sufixo só existe no prompt do agente, não na skill) e o controle de B falha | `agents/sonda-principal.md`, `.claude/settings.json` |
| B. `Agent(...)` na lista de ferramentas aceita nome curto e/ou com prefixo | calibração (desde a 0.0.7): `sonda-projeto`, agente do projeto listado pelo nome curto, tem de responder; `sonda-memoria`, listada nas duas formas, chamada pelos dois nomes; `sonda-folha-a` listada pelo nome curto e `sonda-folha-b` com prefixo, cada uma chamada pelos dois nomes; controle: `general-purpose`, fora da lista, tem de falhar. Sem A, B não mede a lista | `agents/sonda-folha-a.md`, `agents/sonda-folha-b.md`, `agents/sonda-memoria.md` |
| C. `skills:` pré-carrega skill do plugin pelo nome curto e/ou com prefixo | o subagente, sem ferramenta de leitura, responde a marca `abacaxi-7q` da skill, ou `NENHUM`; o número de ferramentas usadas vem junto | `agents/sonda-pre-curto.md`, `agents/sonda-pre-prefixo.md`, `skills/sonda-alvo` |
| D. `${CLAUDE_PLUGIN_ROOT}` é trocado no corpo do agente | os subagentes devolvem o texto como o veem: caminho absoluto ou `${...}` | os mesmos agentes |
| E. `memory: project` vale em agente de plugin | declarado só com TaskList (era TodoWrite até a 0.0.5), o subagente lista as ferramentas que tem (a memória acrescenta Read, Write e Edit) e a linha do prompt que cita a pasta; desde a 0.0.7, a prova é o arquivo que ele grava na pasta de memória, com `sonda-projeto` (agente do projeto) de controle | `agents/sonda-memoria.md`, `.claude/agents/sonda-projeto.md` |

Leitura para a 2.3: os agentes usam, em `skills:` e `Agent(...)`, a forma de nome que funcionou (as duas, se as duas
funcionaram, fica a com prefixo, que é a documentada); `${CLAUDE_PLUGIN_ROOT}` só entra no corpo de agente se D der
"trocada"; `memory: project` fica no `review-agent` só se E der "sim". Se A der "não", a 2.4 não liga o lead pelo
`settings.json` e o desenvolvedor chama `/agents` ou a skill `lead`.

Roteiro, depois do merge na main:

1. Abrir uma sessão NOVA no ambiente `wstack`, em qualquer modo de permissão (a sonda não depende de pedido de
   aprovação). Enquanto a sonda estiver na main, toda sessão nova deste repositório (na nuvem ou na máquina) começa
   como o agente `sonda-principal`, se A funcionar: ele tem as ferramentas normais, mas só delega aos agentes da sonda.
   O `"agent"` sai no PR seguinte.
2. Pedir "rode a sonda de agentes do wstack (skill wstack:sonda-agentes)". Se a skill não existir, a sessão não
   atualizou o plugin: trazer a versão da mensagem do `SessionStart`.
3. Trazer a tabela e a linha final `sonda-agentes: ...`.
4. Se A der NENHUMA com a versão 0.0.5, repetir numa segunda sessão nova: o plugin pode ter sido atualizado durante a
   partida, depois de o Claude Code resolver o `"agent"`.

## Resultado da sonda 3, fato 0 (2026-11-24)

**Fato 0 falhou: o `autoUpdate` não atualizou o plugin ao iniciar a sessão na nuvem.** Os fatos A a E não foram
medidos: a skill `wstack:sonda-agentes` não existia (`Unknown skill`) e nenhum agente `sonda-*` estava disponível.

Duas sessões novas no ambiente `wstack`, abertas depois do merge da sonda 3 (`a576405`, 19:10 UTC), deram o mesmo:

- `wstack 0.0.3 carregado.` no `SessionStart`.
- Cache só com `0.0.3`; em `installed_plugins.json`, os registros de escopo user e project no commit `473e458` (sonda 2),
  com `installedAt` igual a `lastUpdated`: 17:42 UTC, o mesmo instante nas duas sessões. Os registros vieram do
  container guardado pelo ambiente, não de uma instalação na partida, e nada os atualizou depois.
- A cópia do marketplace (`~/.claude/plugins/marketplaces/wstack`) também em `473e458`, com
  `extraKnownMarketplaces.wstack.autoUpdate: true` nas configurações do usuário. O commit `ec5a2f8` (0.0.4) também não
  chegou.
- A linha `PRINCIPAL-ATIVO-` não apareceu, como esperado com a 0.0.3 (o `"agent"` cita um agente que ela não tem).

A atualização à mão funciona: na sessão, `claude plugin marketplace update wstack` levou o marketplace a `a576405`, e
`claude plugin update wstack@wstack` (escopo project, padrão) e `claude plugin update wstack@wstack --scope user`
levaram os dois registros à 0.0.5 ("Restart to apply changes"). Mas isso vale só para aquele container: uma sessão
retomada ou nova parte do container guardado.

Mudança feita: o setup script do ambiente `wstack` passou a rodar, depois do `install` e do `autoUpdate`, as três
atualizações (cada uma com `|| echo` de aviso, para não impedir a sessão de subir):

```bash
claude plugin marketplace update wstack
claude plugin update wstack@wstack --scope user
claude plugin update wstack@wstack --scope project
```

Não provado: se trocar o script força o ambiente a remontar o container guardado (o esperado), e se o `--scope
project` acha o projeto, já que o script roda da pasta acima do repositório (o escopo user basta para carregar o
plugin). Mesmo que funcione, o script só roda quando o container é montado do zero: o plugin continua na versão do
dia da montagem até o ambiente remontar. A decisão "plugin atualizado ao iniciar a sessão na nuvem"
(`docs/decisions.md`) supunha o `autoUpdate` e precisa ser revista.

Próximo passo: abrir uma sessão nova no ambiente `wstack`. Com `wstack 0.0.5 carregado.`, rodar a sonda de agentes
(fatos A a E); com 0.0.3, o container guardado não foi remontado.

## Resultado da sonda 3, fatos A a E (2026-11-24)

Sessão nova no ambiente `wstack`, depois da troca do setup script: `wstack 0.0.5 carregado.`, cache só com `0.0.5`,
registros user e project em `a576405`, gravados às 19:19 UTC. A troca do script fez o ambiente remontar o container,
e o plugin foi instalado na montagem, não atualizado pelo `autoUpdate` (o fato 0 continua falho). Linha da skill:

`sonda-agentes: versão=0.0.5 cache=0.0.5 principal=PRINCIPAL-ATIVO-Kx94 chamada-curta=erro chamada-prefixo=erro folha-a=<curto erro, prefixo erro> folha-b=<curto erro, prefixo erro> controle=falhou pre-curto=erro pre-prefixo=erro variável-no-agente=não memória=<ferramentas a mais: não>`

Na linha, `chamada-prefixo=erro` é recusa por falta de ferramentas (o agente foi achado), e `variável-no-agente=não` e
`memória=não` são falta de dado. Os erros, com o texto exato:

| Chamada | Erro |
|---|---|
| `sonda-memoria`, `sonda-folha-a`, `sonda-folha-b`, `sonda-pre-prefixo`, `general-purpose` | `Agent type '<nome>' not found. Available agents: wstack:sonda-folha-b, wstack:sonda-memoria, wstack:sonda-pre-curto, wstack:sonda-pre-prefixo` |
| `wstack:sonda-folha-a` | `Agent type 'wstack:sonda-folha-a' not found.` (mesma lista) |
| `wstack:sonda-memoria`, `wstack:sonda-folha-b`, `wstack:sonda-pre-curto`, `wstack:sonda-pre-prefixo` | `Agent '<nome>' would be spawned with zero tools — refusing. Its tools list resolved to nothing: unrecognized [TodoWrite]. Fix the agent's tools frontmatter or pass a different subagent_type.` |

`.claude/agent-memory` não existia ao fim da sonda.

Leitura:
- **A ok.** `"agent": "wstack:sonda-principal"` no `settings.json` do projeto ligou o agente do plugin: a linha
  `PRINCIPAL-ATIVO-Kx94` veio no prompt e o controle falhou.
- **B: só a forma com prefixo vale, na lista e na chamada.** A lista `Agent(...)` foi aplicada (o controle
  `general-purpose` não foi achado). Dela só entraram as entradas com prefixo: `sonda-folha-a`, listada só pelo nome
  curto, sumiu nas duas formas; as listadas com prefixo (ou nas duas formas) aparecem como `wstack:<nome>`. Na chamada,
  o nome curto nunca foi achado, nem para as listadas nas duas formas.
- **`TodoWrite` não existe nesta versão do Claude Code.** Um agente cujo `tools:` não resolve nada não é iniciado. Por
  isso os subagentes não rodaram. No `sonda-principal`, que tem outras ferramentas, a entrada foi ignorada sem erro.
- **C, D e E sem dado**, porque nenhum subagente rodou. Único indício de E: o `wstack:sonda-memoria`, com
  `memory: project`, foi recusado por ficar sem ferramentas, então a memória não acrescentou ferramentas antes dessa
  checagem. Não prova que não acrescenta num agente que chega a rodar.

Para a 2.3, já decidido pelos dados: os agentes do harness citam agentes do plugin, em `Agent(...)` e na chamada,
sempre como `wstack:<nome>`. Para medir C, D e E, a sonda precisa de outra rodada com os agentes da sonda declarando,
no lugar de `TodoWrite`, uma ferramenta que exista e não leia arquivos.

Mudança feita (0.0.6): os cinco agentes chamados pela sonda declaram `tools: TaskList`; o `sonda-principal` troca
`TodoWrite` por `TaskList`, lista `wstack:sonda-folha-a` com o prefixo (para a folha A rodar e dar dado de D) e tem
um sufixo novo na linha `PRINCIPAL-ATIVO-` (o anterior está registrado acima). Roteiro igual ao da sonda 3; trazer a
linha final `sonda-agentes: ...` de uma sessão nova com `wstack 0.0.6 carregado.`. O ambiente só instala a versão
nova se remontar o container (o `autoUpdate` não atualiza na partida, fato 0). Na rodada anterior, a remontagem
veio da troca do setup script. Se a sessão subir com 0.0.5, atualizar o plugin nela não serve: o `"agent"` e os agentes
são lidos na partida.

## Resultado da sonda 3 com a 0.0.6 (2026-11-24)

Sessão nova: `wstack 0.0.6 carregado.`, cache só com `0.0.6`, registros user e project em `1414791`, com `installedAt`
igual a `lastUpdated` (instalados na montagem do container, não atualizados). Linha da skill:

`sonda-agentes: versão=0.0.6 cache=0.0.6 principal=PRINCIPAL-ATIVO-Rt27 chamada-curta=erro chamada-prefixo=ok folha-a=curto erro, prefixo ok folha-b=curto erro, prefixo ok controle=falhou pre-curto=abacaxi-7q pre-prefixo=abacaxi-7q variável-no-agente=trocada memória=ferramentas a mais: não`

Leitura:
- **A ok** de novo, e o controle `general-purpose` falhou (`not found`): a lista foi aplicada.
- **B: só `wstack:<nome>` acha agente do plugin.** Todo nome curto deu `Agent type '<nome>' not found`, com a lista de
  agentes disponíveis só na forma com prefixo. A calibração não decidiu: `sonda-memoria` só apareceu com prefixo, então
  não separa a forma da chamada da forma da lista.
- **C: `skills:` pré-carrega skill do plugin pelos dois nomes.** As duas folhas responderam `abacaxi-7q`, sem usar
  ferramentas.
- **D: `${CLAUDE_PLUGIN_ROOT}` é trocado no corpo do agente** (`/root/.claude/plugins/cache/wstack/wstack/0.0.6/hooks`).
- **E fraco.** O `wstack:sonda-memoria` respondeu `FERRAMENTAS: TaskList / MEMORIA: sim / LINHA: NENHUMA`, e
  `.claude/agent-memory` não existia. Sem Read, Write e Edit e sem a linha da pasta, o mais provável é que a memória seja
  ignorada em agente de plugin, mas o "sim" é a palavra do agente e falta um controle em que a memória certamente valha.

Mudança feita (0.0.7):
- **Calibração com agente de projeto.** `.claude/agents/sonda-projeto.md`, cujo nome não tem prefixo, entra no
  `Agent(...)` do `sonda-principal` pelo nome curto. Se responder, a lista aceita nome curto e a chamada acha o agente
  pelo nome exato: o erro do nome curto nos agentes do plugin vem do nome deles.
- **Memória provada por gravação.** `sonda-memoria` e `sonda-projeto` têm `memory: project` e só TaskList; os dois
  gravam `sonda.md` na pasta de memória se tiverem Write (`MARCA-PLUGIN` e `MARCA-PROJETO`), e a skill procura as
  marcas em `.claude/agent-memory` e `~/.claude/agent-memory`. O agente de projeto é o controle.
- Sufixo novo na linha `PRINCIPAL-ATIVO-`. Roteiro igual; trazer a linha final de uma sessão nova com
  `wstack 0.0.7 carregado.`. O `.claude/agents/sonda-projeto.md` sai junto com o `"agent"`.

## Resultado da sonda 3 com a 0.0.7 (2026-11-24)

Antes da rodada, o setup script do ambiente `wstack` passou a instalar o plugin de um marketplace local, a pasta do
clone (`claude plugin marketplace add /home/user/wstack`, depois `claude plugin install wstack@wstack`), no lugar do
marketplace do GitHub e das atualizações forçadas. Sessão nova: `wstack 0.0.7 carregado.`, cache só com `0.0.7`,
registros user e project em `178e14d`, com `installedAt` igual a `lastUpdated` (19:55 UTC). O
`known_marketplaces.json` dá `wstack` com `source: directory`, `/home/user/wstack`; o `.claude/settings.json` continua
declarando a origem GitHub, que a sessão na nuvem não usa. Linha da skill:

`sonda-agentes: versão=0.0.7 cache=0.0.7 principal=PRINCIPAL-ATIVO-Vm52 calibração-projeto=ok chamada-curta=erro chamada-prefixo=ok folha-a=<curto erro, prefixo ok> folha-b=<curto erro, prefixo ok> controle=falhou pre-curto=abacaxi-7q pre-prefixo=abacaxi-7q variável-no-agente=trocada memória-projeto=não gravou memória-plugin=não gravou`

O erro de todo nome que falhou: `Agent type '<nome>' not found. Available agents: sonda-projeto, wstack:sonda-folha-a,
wstack:sonda-folha-b, wstack:sonda-memoria, wstack:sonda-pre-curto, wstack:sonda-pre-prefixo`.

Leitura:
- **Fato 0 resolvido por outro caminho: o plugin é carregado do clone.** As folhas devolveram
  `/home/user/wstack/plugin/hooks` no lugar de `${CLAUDE_PLUGIN_ROOT}`, embora o `installPath` dos dois registros aponte
  para `.../cache/wstack/wstack/0.0.7`: o registro não diz a pasta carregada. Cada sessão clona o repositório de novo,
  então carrega o plugin da branch em que abriu, sem trocar o script. Falta ver acontecer: a primeira sessão depois do
  próximo merge tem de subir com a versão nova sem mudança no script.
- **B decidido.** A calibração respondeu: `sonda-projeto`, agente do projeto, aparece e é achado pelo nome curto.
  A lista aceita nome curto e a chamada usa o nome exato; o nome real de um agente do plugin é `wstack:<nome>`, então
  entrada curta de agente do plugin some da lista (`sonda-memoria`, listada nas duas formas, só aparece com prefixo) e
  chamada curta não o acha.
- **C: `skills:` pré-carrega skill do plugin pelos dois nomes** (`abacaxi-7q` nas duas folhas, sem ferramentas).
- **D: `${CLAUDE_PLUGIN_ROOT}` é trocado no corpo do agente** (agora pela pasta do clone).
- **E sem decisão.** Nenhum dos dois agentes com `memory: project` e só TaskList ganhou Read, Write ou Edit, nenhum
  citou pasta de memória (`LINHA: NENHUMA`, apesar de `MEMORIA: sim`, que é a palavra do agente) e nada foi gravado:
  não existe `.claude/agent-memory` nem `~/.claude/agent-memory`. O controle de projeto deu o mesmo que o plugin, então
  o que se mediu é que a memória não acrescenta ferramentas a agente com `tools:` restrito, não se ela vale em agente
  de plugin. Para decidir, os dois agentes precisam declarar Read, Write e Edit.

## Fato 0 visto acontecer (2026-11-24)

Primeira sessão depois do merge da 0.0.8 (`139b1fa`), sem troca no setup script: `wstack 0.0.8 carregado.`, com o
cache só em `0.0.7`. O `session-start.sh` tira a versão do `plugin.json` da pasta do próprio hook, então rodou de
`/home/user/wstack/plugin`: o merge chegou sozinho. Na mesma sessão, Edit em `plugin/hooks/write-guard.mjs` (e o Edit
que o desfez) foi aceito, pela exceção do plugin dentro do projeto. Edição pelo shell não serve de prova: o
write-guard só vê as ferramentas de escrita.

## Resultado da sonda 3 com a 0.0.9 (2026-11-24)

Rodada só para o passo E: `sonda-memoria` e `sonda-projeto` passaram a declarar TaskList, Read, Write e Edit, e
gravam `sonda.md` com Write se o prompt citar uma pasta de memória. Rodada na sessão que abriu na 0.0.8 e foi retomada
depois do merge da 0.0.9 (`1bf755e`): o hook da retomada deu `wstack 0.0.9 carregado.`, e os dois agentes já
responderam com as ferramentas novas, então as definições da 0.0.9 valeram. Cache e registros iguais aos da 0.0.7
(`0.0.7`, `178e14d`, marketplace `directory` em `/home/user/wstack`). Linha da skill:

`sonda-agentes: versão=0.0.9 cache=0.0.7 principal=PRINCIPAL-ATIVO-Vm52 calibração-projeto=ok chamada-curta=erro chamada-prefixo=ok folha-a=<curto erro, prefixo ok> folha-b=<curto erro, prefixo ok> controle=falhou pre-curto=abacaxi-7q pre-prefixo=abacaxi-7q variável-no-agente=trocada memória-projeto=não gravou memória-plugin=não gravou`

Os dois agentes de memória deram as mesmas quatro linhas, sem usar ferramenta: `FERRAMENTAS: TaskList, Read, Write,
Edit`, `MEMORIA: sim`, `LINHA: NENHUMA`, `GRAVOU: não`. Não existe `.claude/agent-memory` nem `~/.claude/agent-memory`,
e o grep por `MARCA-` não achou nada.

Leitura:
- **B, C e D repetem a rodada da 0.0.7.**
- **E sem decisão sobre o plugin, agora pelo controle.** Com as ferramentas de escrita garantidas, nenhum dos dois
  recebeu pasta de memória no prompt, nem o agente de projeto. Então `memory: project` não chegou a agente nenhum nesta
  sessão na nuvem, e o resultado não separa agente de plugin de agente de projeto. Hipótese não conferida: a sessão na
  nuvem usa a memória hospedada do Claude Code (o servidor MCP `memory`) e não monta a memória de agente. Só uma
  sessão local decide; a 2.3 não espera por ela (`docs/decisions.md`, agentes do plugin sem `memory:`).

## Fim da sonda 3 (2026-11-24)

A sonda 3 terminou: B, C e D decididos, E pendente para sessão local (`docs/decisions.md`, agentes do plugin sem
`memory:`). Saíram o `"agent": "wstack:sonda-principal"` do `.claude/settings.json`, que fazia toda sessão deste
repositório abrir como o agente da sonda e só delegar aos agentes dela, e o `.claude/agents/sonda-projeto.md`. Os
agentes e as skills `sonda-*` do plugin ficam até os agentes reais entrarem na 2.3. Para repetir a sonda, inclusive o
passo E numa sessão local, é preciso devolver os dois: sem eles, a calibração (B.1) e o controle de E dão erro.
