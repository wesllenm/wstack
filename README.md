# wstack

Plugin do Claude Code com um workflow de desenvolvimento com agentes, para qualquer projeto. A sessão roda como um
coordenador técnico (o agente `lead`). Ele classifica o risco de cada tarefa, apresenta um plano, pede **uma**
aprovação e executa até a condição de parada: delega a subagentes, revisa em proporção ao risco e commita. Hooks
garantem o que não pode depender da boa vontade do modelo: travas de permissão, build e testes verdes antes de
encerrar, e push só para branch de atividade.

**Feito para a nuvem.** Tudo roda no Claude Code na nuvem (claude.ai/code): o ambiente, o setup das ferramentas, a
instalação do plugin, as sessões, os subagentes e os testes. Você acompanha e aprova pelo navegador ou pelo app, e o
que sai de lá são branches e PRs no GitHub. Não é preciso instalar nada na sua máquina, nem para começar um projeto do
zero. O Claude Code local também funciona ([No Claude Code local](#no-claude-code-local)).

**Estado: versão 0.0.48.** A migração do harness para o plugin está concluída (unidades 2.2 a 2.4, ver
`docs/migracao.md`). Ficaram para depois, de propósito:
- os workflows do GitHub (gates, merge por risco, revisão de PR) e a configuração de MCP do banco, que ficam para
  depois da 0.1.0 (`docs/decisions.md`);
- a avaliação comportamental dos agentes;
- a conferência num projeto real: uma sessão com `"agent": "wstack:lead"` num projeto que passou pelo bootstrap,
  delegando aos agentes reais, e as provas `plugin/tests/prove-*.sh`, que usam o Claude Code real e rodam à mão;
- a medição na máquina do projeto, com os `plugin/tests/measure-*.sh`: o custo dos hooks por comando
  (`measure-hook-cost.sh`), os pedidos de aprovação de uma sessão (`measure-permission-asks.sh`) e o hook de fim com a
  aplicação rodando e travando a saída do build (`measure-stop-locked-build.sh`). Rodam também no Windows com Git Bash.

## Como funciona

```mermaid
flowchart LR
    A["Você pede<br/>a tarefa"] --> B["Claude planeja<br/><i>na nuvem</i>"] --> C{{"Você aprova<br/>o plano"}} --> D["Claude codifica,<br/>testa e revisa<br/><i>na nuvem</i>"] --> E["PR no<br/>GitHub"] --> F{{"Você faz<br/>o merge"}}

    classDef voce fill:#fde68a,stroke:#b45309,color:#000
    class A,C,F voce
```

Em amarelo, o que é seu; o resto o Claude faz numa sessão em claude.ai/code. Cada sessão roda num contêiner novo na
nuvem, que o setup script do ambiente prepara com as ferramentas do projeto e o plugin. O contêiner é descartado ao
fim; o que precisa durar (código, configuração do workflow, aprendizado, decisões) vai para o repositório no GitHub.

## Como uma tarefa anda

Dentro de cada sessão, o Claude (o agente `lead`) leva o pedido até o PR assim:

```mermaid
flowchart LR
    A["Classifica<br/>o risco"] --> B["Planeja"] --> C{{"Você aprova"}} --> D["Implementa<br/>com testes"] --> E["Revisa"]
    E -->|achou problema| D
    E --> F["Commit<br/>e PR"]

    classDef voce fill:#fde68a,stroke:#b45309,color:#000
    class C voce
```

Os hooks valem em todos os passos, sem depender do modelo: travas de escrita, de comando e de push na execução, e
build, formato e testes verdes antes de a sessão encerrar.

1. **Início.** A primeira mensagem repete o objetivo do pedido e a menor mudança que o atende, e o plano parte dela.
   Lê o contexto do projeto (`CLAUDE.md`, `.claude/project.md`, decisões), confere sessões paralelas no mesmo
   repositório (`sessions.sh`) e recupera histórico de sessões anteriores quando a área já foi trabalhada (skill
   `recall`).
2. **Classificação.** O nível de risco não é opinião do modelo. Ele vem de `scripts/classify-diff.sh`, calculado pelos
   caminhos tocados, pelo tamanho do diff e pelos globs `critical`, `complex` e `domain` do `.claude/risk.conf`. O
   `lead` pode subir o nível, nunca descer. A classificação roda no plano e de novo no diff real. Depois dela, o
   `lead` escolhe o tipo da tarefa (feature, bug, investigação, performance, refatoração) e segue o playbook do tipo:
   o risco decide os gates, o tipo decide os passos. Pergunta sobre o código vai para as skills `how` e `why`, fora
   desse fluxo.
3. **Plano e aprovação única.** Escopo, exclusões, testes, agentes e uma condição de parada verificável (comando e
   resultado esperado). Decisão de design cara de reverter passa antes pela arena: propostas paralelas comparadas
   pelos mesmos critérios. O desenvolvedor aprova uma vez. Dali em diante o `lead` lê, edita, testa, delega, corrige e
   commita sem pedir confirmação a cada passo. Push, PR e afrouxar testes só entram se o plano disser.
4. **Execução.** O `implementer` recebe um sprint contract delimitado e trabalha com TDD. O `planner` e o `explore`
   levantam contexto em código desconhecido.
5. **Revisão**, em quatro etapas:
   - preparar: `diff-smells.mjs` limpa código comentado e marcadores, separa o comentário que descreve uma regra
     ("não chamar antes de Init()") para a lente de simplicidade propor como garanti-la no código, e
     `review-dispatch.mjs` agrupa os arquivos e indica a regra de cada caminho;
   - achar: as lentes rodam em paralelo e, em COMPLEXA e CRITICA, modelos de outro fornecedor tentam quebrar o diff
     quando o projeto os configura (`interrogate.mjs`); se nenhum responde, em CRITICA o commit espera a sua decisão.
     Cada lente termina com uma linha de status, e lente que não terminou é lacuna, nunca "sem achados": em CRITICA,
     depois de uma nova tentativa, o commit espera a sua decisão;
   - verificar: `check-findings.mjs` descarta o achado cujo trecho não existe no código e marca "a confirmar" o
     achado grave sem o comando que o prova; o `review-verifier` roda esse comando, refuta o que não reproduz e
     tenta refutar o resto;
   - corrigir: só o confirmado é corrigido, e o delta é revisto de novo (no máximo duas rodadas).
6. **Commit** pela skill `commit` (Conventional Commits, em português), numa branch de atividade, com a mensagem
   conferida pelo `slop-check.mjs` (skill `unslop`).
7. **Limpeza e aprendizado.** Remove o que a sessão criou (worktrees, branches temporárias, contêineres) e registra o
   que aprendeu em `docs/gotchas/` e em `docs/review-calibration.md`, que calibra a revisão ao longo do tempo. A
   correção que você faz no meio da sessão é registrada na hora (skill `correct`) e sobe na escada de correção no fim.
   O relatório diz qual regra de qual skill mudou qual decisão, e o hook `Stop` confere na transcrição da sessão que
   cada skill citada foi carregada e que os pedidos de permissão registrados batem.

### Níveis de risco

| Nível | Quando | Revisão |
|---|---|---|
| TRIVIAL | até 3 arquivos e 50 linhas, um domínio, nada crítico | `review-agent` e `review-verifier`; doc pura só com checagens determinísticas |
| SIMPLES | até 5 arquivos e 200 linhas, um domínio | caminho rápido na sessão; caminho pesado em segundo plano |
| COMPLEXA | acima disso, vários domínios ou glob `complex` | plano completo; caminho pesado em segundo plano, com `security-agent` se houver superfície |
| CRITICA | glob `critical` (auth, segredos, migrations, contratos públicos...) ou teste removido | tudo da COMPLEXA mais `review-critical`; o caminho pesado roda antes do commit, com prova do fato de segurança |

O **caminho rápido** é a camada determinística (build, formato, testes, garantidos pelo hook `Stop`) mais o
`review-agent` e o `review-verifier`. O **caminho pesado** soma benchmark nas áreas quentes, sinais de qualidade,
`review-simplicity`, as lentes condicionais e os especialistas. Sem `risk.conf`, o classificador devolve CRITICA.

## Começar um projeto na nuvem

```mermaid
flowchart LR
    A["<b>1. Criar o ambiente</b><br/>com o repositório<br/>e o setup.sh"] --> B["<b>2. /wstack:bootstrap</b><br/>na primeira sessão<br/>e merge"] --> C["<b>3. Pedir tarefas</b><br/>em cada sessão"]
```

1. **Criar o ambiente** em claude.ai/code com o repositório do projeto, que pode estar vazio. No setup script, colar
   o conteúdo de `plugin/cloud/setup.sh`. A rede do ambiente precisa alcançar `github.com`, de onde o plugin é
   baixado. Isso se faz uma vez por projeto.
2. **Abrir a primeira sessão.** O setup instala as ferramentas das stacks que detectar e, como o projeto ainda não
   adotou o wstack, a maior tag publicada do plugin. A sessão começa com "Projeto sem o wstack: ...
   /wstack:bootstrap". Nesse estado o plugin fica inerte: só as travas de segurança valem.
3. **Rodar `/wstack:bootstrap`.** Ele diagnostica o repositório (stacks, comandos de build e teste, branch padrão),
   propõe os arquivos e, com a sua aprovação, cria o que faltar, sem sobrescrever nada que já exista:

   | Arquivo | Para quê |
   |---|---|
   | `.claude/settings.json` | agente `wstack:lead`, plugin fixado em `v<versão>`, permissões (`deny`, `ask`, `allow`) |
   | `.claude/risk.conf` | globs de risco, comandos de verificação (`verify_*`), prefixos de branch, caminhos protegidos |
   | `CLAUDE.md` | regras do projeto, comandos e o que o código não mostra |
   | `.claude/project.md`, `.claude/architecture.md` | produto, domínios (com a skill de cada um) e arquitetura |
   | `.claude/cloud/hosts.conf` | hosts que a nuvem precisa por stack |
   | `docs/review-rubric.md` | complemento da rubrica: Sempre verificar, Não reportar, Projeto |
   | `docs/review-calibration.md`, `docs/gotchas.md`, `docs/decisions.md` | aprendizado e decisões do projeto; o projeto que já tem lugar para esses fatos aponta as chaves `doc_*` do `risk.conf` (com `doc_state`, a pendência vai para um arquivo versionado, fora do `SESSION.md`) |
   | `.claude/skills/verify-<app>/` | esqueleto da skill que sobe a aplicação e prova comportamento (só com aplicação) |

   A proposta também pergunta se o projeto liga a revisão por outro fornecedor (`interrogate_cmd`): o diff de COMPLEXA
   e CRITICA sai da máquina para esse fornecedor. Ligada ou não, a resposta vai para o `docs/decisions.md` do projeto.

4. **Revisar e fazer o merge.** O bootstrap preenche o que consegue detectar nos `<...>` dos modelos; o resto, e a
   receita da `verify-<app>` (que sai como esqueleto), você completa na mesma sessão. O commit vai para a branch
   `chore/bootstrap-wstack`; o merge na branch padrão fixa a versão do plugin no projeto.
5. **Trabalhar.** Da sessão seguinte em diante, o setup instala a versão fixada e a sessão já começa como
   `wstack:lead`: você faz o pedido, aprova o plano e faz o merge do PR. O `--check` do setup, rodado no início de
   cada sessão, aponta o que faltar (ferramenta da stack, plugin em outra versão).

Por que o setup script: na nuvem, o `.claude/settings.json` do projeto não instala plugin sozinho (`docs/sonda.md`,
fato 1), e cada sessão começa num contêiner novo; o setup roda a cada contêiner e instala o plugin de novo.

### No Claude Code local

Também funciona no terminal, no desktop ou na IDE: instalar o plugin com `/plugin marketplace add wesllenm/wstack` e
`/plugin install wstack@wstack`, e seguir do passo 3. O setup script é só da nuvem; localmente, as ferramentas da stack
são as da sua máquina. Os hooks precisam de bash, git e node no PATH (no Windows, pelo Git Bash): sem o node, o `Stop`
não consegue conferir o registro de aprendizado e bloqueia o encerramento depois de commit de código.

### Cobertura por stack

O workflow, as travas, a classificação de risco e a revisão não dependem de linguagem: valem para qualquer
repositório git. O que depende da stack:
- **Ferramentas na nuvem:** o `setup.sh` instala .NET (SDK do `global.json`), Node (dependências de cada pasta com
  lockfile), Rust, Go e Python (`.venv` com os `requirements*.txt`). Outra stack (Java, por exemplo) entra no setup
  script do ambiente à mão.
- **Referências específicas** de revisão e performance: .NET, Node, Bash e frontend web; de plano de execução: EF Core
  e PostgreSQL. Nas outras stacks, as skills de engenharia valem do mesmo jeito, com orientação genérica.
- **Comandos de build, formato e teste:** são do projeto, declarados nas chaves `verify_*` do `.claude/risk.conf`; o
  hook `Stop` roda os que estiverem ali.

O projeto mantém os próprios arquivos. Uma mudança em skill, agente ou hook do plugin vira proposta aqui no wstack,
não edição no projeto.

**Repositório sem bootstrap.** Com o plugin instalado no escopo do usuário, ele roda em todo repositório. Sem
`.claude/risk.conf` (fora da árvore e de todo commit apontado), os hooks de workflow ficam inertes e só as travas de
segurança continuam (`docs/decisions.md`, plugin inerte sem risk.conf).

## O que tem no plugin

```text
.claude-plugin/marketplace.json   marketplace "wstack" (um plugin, em ./plugin)
plugin/
  .claude-plugin/plugin.json      nome e versão
  agents/       18 subagentes (wstack:<nome>)
  skills/       34 skills (/wstack:<nome>); em lead/playbooks/, 6 playbooks por tipo de tarefa
  hooks/        hooks.json e as travas e verificações
  scripts/      scripts que as skills, os agentes e os hooks chamam
  cloud/        setup.sh do ambiente da nuvem
  templates/    modelos que o /wstack:bootstrap copia para o projeto
  tests/        testes (CI) e provas com o Claude Code real (à mão)
docs/           decisões, inventário da migração, matriz de garantias, sondas
```

### Mapa por etapa

Uma coluna por etapa da tarefa, com o que entra nela de cima para baixo, na ordem em que dispara. A cor diz quem garante: em vermelho, hook que
roda sem depender do modelo; em azul, script determinístico; em verde, skill (orientação que o modelo segue); em
roxo, agente; em amarelo, o que é seu.

```mermaid
flowchart LR
    subgraph PLAN["1 · Planejar"]
        direction TB
        p1["how · why · recall<br/>entender o código"] --> p2["classify-diff.sh<br/>nível de risco"] --> p3["blast-radius<br/>o que quebra<br/>fora do diff"] --> p4["arena<br/>propostas + juiz"] --> p5{{"Você aprova<br/>o plano"}}
    end
    subgraph DESIGN["2 · Desenhar"]
        direction TB
        d1["esboço da fatia<br/>uso e assinaturas"] --> d2["domain-modeling<br/>api-design"] --> d3["vertical-slice<br/>db-evolution"]
    end
    subgraph BUILD["3 · Construir"]
        direction TB
        b1["implementer<br/>sprint contract"] --> b2["tdd · test-audit<br/>teste antes<br/>do código"] --> b3["edit-check<br/>iteration-guard<br/>a cada edição"]
    end
    subgraph REVIEW["4 · Revisar e provar"]
        direction TB
        r1["diff-smells.mjs<br/>escape, marcador,<br/>restrição"] --> r2["review-dispatch.mjs<br/>grupos e regras"] --> r3["lentes<br/>agent · simplicity<br/>failures · domain<br/>security"] --> r4["check-findings.mjs<br/>trecho, prova,<br/>lacuna"] --> r5["review-verifier<br/>roda a prova"] --> r6["review-critical<br/>fato de segurança"] --> r8["verify-#lt;app#gt;<br/>na aplicação real"]
        r7["interrogate.mjs<br/>outro fornecedor"] --> r4
    end
    subgraph SHIP["5 · Entregar"]
        direction TB
        s1["checkpoint-tests<br/>antes do commit"] --> s2["commit<br/>slop-check"] --> s3["verify-on-stop<br/>build e testes<br/>verdes"] --> s4["push-guard<br/>branch de atividade"] --> s5["PR<br/>slop-check --pr"] --> s6{{"Você faz<br/>o merge"}}
    end
    subgraph LEARN["6 · Aprender e manter"]
        direction TB
        l1["Registro<br/>principles.mjs"] --> l2["triagem das lições<br/>aceita · rejeitada<br/>backlog"] --> l3["correct<br/>/correct historico"] --> l4["Regras e garantias<br/>no CLAUDE.md"] --> l5["map-staleness.mjs"] --> l6["verify-#lt;app#gt;<br/>manutenção"]
    end
    subgraph ALWAYS["A qualquer momento"]
        direction TB
        a1["lead<br/>tipo de tarefa<br/>e playbook"] ~~~ a2["path-guard<br/>write-guard<br/>redirect-guard<br/>verifier-guard"] ~~~ a3["princípios<br/>attack-the-premise<br/>build-the-lever<br/>separate-before-<br/>serializing<br/>subtract-before-<br/>you-add"] ~~~ a4["unslop · commit<br/>texto em PT-BR"]
    end
    PLAN ~~~ DESIGN ~~~ BUILD ~~~ REVIEW ~~~ SHIP ~~~ LEARN ~~~ ALWAYS

    classDef voce fill:#fde68a,stroke:#b45309,color:#000
    classDef trava fill:#fecaca,stroke:#b91c1c,color:#000
    classDef script fill:#bfdbfe,stroke:#1d4ed8,color:#000
    classDef skill fill:#bbf7d0,stroke:#15803d,color:#000
    classDef agente fill:#e9d5ff,stroke:#7e22ce,color:#000
    class p5,s6 voce
    class b3,s1,s3,s4,a2 trava
    class p2,r1,r2,r4,r7,s5,l1,l5 script
    class p1,p3,p4,d1,d2,d3,b2,r8,s2,l2,l3,l4,l6,a3,a4 skill
    class b1,r3,r5,r6,a1 agente
```

O diagrama não lista tudo: as tabelas abaixo têm cada agente, skill, hook e script.

O projeto que tem a própria versão de uma skill ou de um agente do plugin declara a troca com `override` no
`risk.conf` (`override = tdd`, `override = test-audit -> auditoria-de-testes`); a `lead` passa a usar a do projeto.
Agente do projeto só substitui com o mesmo nome do agente do plugin.

Tarefa que muda dois repositórios juntos: o projeto declara o outro com `companion = ../<repositório>` no `risk.conf`,
e cada um mantém o próprio `risk.conf`. O `classify-diff.sh --companions` dá o nível da tarefa (no mínimo COMPLEXA
quando os dois mudam código), o `Stop` verifica os dois, o checkpoint do commit usa as áreas do repositório dele e o push do outro segue o `risk.conf` dele; cada repositório tem o seu PR, e os dois trazem a mesma ordem de merge.

### Agentes

| Agente | Modelo | Papel |
|---|---|---|
| `lead` | o da sessão (Opus) | coordenador: classifica, planeja, delega, revisa, commita |
| `planner` | Opus | contexto amplo e plano preliminar, somente leitura |
| `explore` | Haiku | localizar código e mapear impacto, somente leitura |
| `implementer` | Sonnet | implementa um sprint contract com TDD |
| `simplify` | Sonnet | aplica achados de simplicidade confirmados |
| `review-agent` | Sonnet | lente de corretude (toda alteração de código) |
| `review-simplicity` | Sonnet | lente de simplicidade e reuso |
| `review-failures` | Sonnet | lente de tratamento de erro (condicional) |
| `review-domain` | Sonnet | lente de modelagem de domínio (condicional) |
| `review-verifier` | Opus | tenta refutar cada candidato antes de qualquer correção |
| `review-critical` | Opus | revisão independente do nível CRITICA |
| `security-agent` | Opus | auditoria adversarial de segurança |
| `database-helper` | Haiku | consulta o banco real via MCP, somente leitura |
| `database-reviewer` | Opus | migrations, queries, índices, locks, rollback |
| `performance-agent` | Opus | investiga gargalo com medição |
| `playwright-e2e` | Sonnet | testes E2E com Playwright |
| `e2e-critical-review` | Opus | E2E crítico e flakiness |
| `ci-reviewer` | Sonnet | revisão de PR dentro do GitHub Actions |

### Skills

- **Workflow:** `lead` (o processo acima), `commit`, `review-rubric` (régua comum de severidade, evidência e formato
  dos achados), `test-audit` (gate de autoria de testes e auditoria), `recall` (sessões anteriores), `correct`
  (correção do desenvolvedor registrada na hora, com o degrau da escada), `unslop` (texto técnico em PT-BR sem
  enfeite), `bootstrap` (adoção num projeto), `blast-radius` (o que a mudança pode quebrar fora do diff e o fato
  de segurança que a prova, no plano de CRITICA e de COMPLEXA com contrato, migration ou mensageria).
- **Entender o código:** `how` (como funciona) e `why` (por que está assim), só leitura e fora do pipeline de risco.
- **Engenharia:** `tdd`, `testing-strategy`, `clean-code`, `refactoring`, `clean-architecture`, `vertical-slice`,
  `domain-modeling`, `api-design`, `concurrency`, `resilience`, `event-driven`, `observability`, `security`,
  `performance`, `continuous-delivery`, `frontend`, `ux`.
- **Banco:** `db-evolution` (migrations e schema), `query-plan` (plano de execução no banco real).
- **Princípios**, curtos e citáveis no relatório: `attack-the-premise` (duas correções falharam no mesmo gate:
  verificar a premissa), `build-the-lever` (uma unidade à mão, depois a ferramenta), `separate-before-serializing`
  (tirar o compartilhamento antes de sincronizar) e `subtract-before-you-add` (superfície igual ou menor).

As referências por stack ficam em `reference/*.md`: .NET, Node, Bash e frontend web em `performance` e
`review-rubric` (esta também tem regras por caminho), e EF Core e PostgreSQL em `query-plan`. A skill `lead` tem um
núcleo com o que vale em toda tarefa e, em `reference/`, o detalhe que só parte das tarefas usa (sequência por nível,
revisão, delegação, limpeza, `SESSION.md`, modo paralelo, nuvem, mudança em lote, fechamento com o relatório,
manutenção do aprendizado), lido no momento que a tabela Leitura sob demanda do núcleo indica. Em `playbooks/` ficam as sequências por tipo de tarefa (bug, investigação,
performance com subida iterativa, diagnóstico de runtime, protótipo e a de tarefa sem playbook, com unidades e
veredito), escolhidas depois da classificação de risco: o risco decide os gates, o tipo decide os passos. A arena
(`reference/arena.md`) compara propostas paralelas de `planner` em decisão de design cara de reverter, com um
`planner` juiz que pontua sem ter gerado proposta e a pontuação do lead feita sem ver a dele, e o
`interrogate.mjs` manda o diff de COMPLEXA e CRITICA para modelos de outro fornecedor que o projeto configure no
`risk.conf`, com os achados passando pelo `review-verifier`. O relatório diz qual regra de qual skill mudou qual decisão
(Princípios aplicados), e o `principles.mjs` recusa citação de skill que a sessão não carregou.

### Hooks

| Evento | Hook | O que faz |
|---|---|---|
| `PreToolUse` Edit/Write | `write-guard` | a ferramenta de escrita não grava em `.git`, na config do git nem na pasta do plugin, e pede a sua aprovação para gravar a exceção do `Stop` (`.claude/verify-blocked.md`); em `.claude/.session/` e no `.claude/.verify-ok`, estado dos hooks, não grava |
| `PreToolUse` Bash | `push-guard` | push só na forma exata, para branch de atividade, nunca na padrão; pede aprovação se publica caminho protegido; recusa o push enquanto um turno encerrado pela exceção de verificação não for seguido, na mesma sessão, de um encerramento em que o build e os testes rodaram e passaram sobre a árvore limpa (marcador preso, de sessão encerrada ou de commit reescrito, só você apaga, e a recusa mostra o comando); por projeto, `push_force_with_lease` e `push_delete` no `risk.conf` liberam o push com lease e apagar a branch de atividade já incorporada |
| | `path-guard` | pede aprovação para comando que cita trava (`settings.json`, `risk.conf`, `.git`, workflows, a pasta do plugin) ou segredo; recusa, também na nuvem, comando que mexe no estado dos hooks (`.claude/.session/`, com o marcador de verificação pendente e o `checkpoint-ok`, e o carimbo `.claude/.verify-ok`) e, na nuvem, comando que cita a exceção `.claude/verify-blocked.md` |
| | `redirect-guard` | pede aprovação para `>` fora das formas fechadas |
| | `verifier-guard` | nos comandos do `review-verifier`, que roda a prova escrita por uma lente: nega rede, pipe para interpretador, `eval` e `base64 -d`, deixa passar só executor de teste, script do repositório e `git log`/`show`/`blame` com flags listadas, com saída para a pasta temporária, e pede aprovação para o resto (o verifier lê código com Read, Grep e Glob) |
| | `git-read-allow` | aprova `git log/diff/show` na forma fechada |
| | `script-allow` | aprova os scripts do plugin na forma fechada |
| | `dotnet-allow` | aprova `dotnet build/test/restore/format/ef/list package` na forma fechada, só com `allow_module = dotnet` válido no `risk.conf`; o `deny` e o `ask` do `settings.json` continuam valendo |
| | `checkpoint-tests` | roda os testes da área antes do `git commit` |
| `TaskCompleted` | `checkpoint-tests` | idem, ao fechar uma tarefa |
| `PostToolUse` edição | `edit-check` | lint e formatação do arquivo recém-editado |
| | `iteration-guard` | lembra a regra das três tentativas a cada N edições sem commit |
| `Stop` | `verify-on-stop` | não encerra com build, formato ou teste vermelho, nem sem registro de aprendizado depois de commit de código; os campos `princípios:` e `pedidos:` do registro são conferidos contra a transcrição da sessão; quando não consegue conferir (script, node ou entrada quebrados), bloqueia em vez de passar, e só libera com a exceção em `.claude/verify-blocked.md`, que só você aprova, vale para a sessão que a gravou e para um encerramento, e aparece para você ao encerrar |
| `SessionStart` | `session-start`, `sessions.sh`, `map-staleness`, `cloud-services` | versão em uso, registro da sessão, aviso de mapa de features velho, serviços da nuvem |
| `SessionEnd` | `sessions.sh` | tira a sessão do registro |
| `Notification` | `notify` | aviso do sistema operacional quando a sessão espera você |

Os hooks são cinto de segurança, não fronteira: leem o texto do comando, e um caminho montado para esconder não
aparece. A fronteira é o PR, o isolamento e o `deny` do `settings.json`. O que cada mecanismo garante, o que não
garante e o teste que prova estão em `docs/harness-capabilities.md`.

Risco aceito: rodar teste do projeto é rodar código do projeto. O `verifier-guard` deixa passar executor de teste e
script do repositório, e um repositório hostil pode ter código malicioso num teste; o hook de `Stop` e a `verify-<app>`
rodam esse código de qualquer jeito. Impedir isso impediria a prova por execução. A fronteira é o isolamento do
ambiente: na nuvem, o contêiner descartável e a lista de domínios liberados; no terminal local, a sua máquina.

### Scripts

Os principais: `classify-diff.sh` (nível de risco), `review-dispatch.mjs`, `diff-smells.mjs` e `check-findings.mjs`
(revisão), `quality-signals.sh` e `bench-compare.sh` (sinais de qualidade e benchmark), `sessions.sh`,
`nova-atividade.sh` e `worktree-env.sh` (sessões em paralelo, cada uma numa worktree), `checkpoint.sh` (checkpoint da
sessão na nuvem), `prune-merged.sh` (limpa branches de PR mesclado), `bootstrap.sh` (modelos do projeto),
`interrogate.mjs` (revisão por outro fornecedor), `principles.mjs` (princípios citados contra os lidos) e
`slop-check.mjs` (texto de commit e PR). Os que vieram do harness de origem estão no inventário de `docs/migracao.md`,
com quem chama cada um; os criados depois, em `docs/decisions.md`.

## Versões

Cada projeto fixa a versão pela tag no `ref` do marketplace, no seu `.claude/settings.json`. Para publicar uma
versão:
1. Subir `version` em `plugin/.claude-plugin/plugin.json` no PR.
2. Depois do merge, criar a tag na `main` e enviá-la, de uma máquina com permissão de push:

   ```bash
   git tag -a v<versão> -m "wstack <versão>" <commit do merge>
   git push origin v<versão>
   ```

Para atualizar um projeto, troque o `ref` no `.claude/settings.json` dele. O setup da nuvem reinstala na próxima
sessão.

## Desenvolver o plugin

- Testes: `for t in plugin/tests/test-*.sh; do bash "$t" || exit 1; done` (precisa de bash, git, jq e node). O CI
  (`.github/workflows/ci.yml`) roda os mesmos testes em todo PR.
- Validação: `claude plugin validate plugin` e `claude plugin validate .`.
- Documentos:
  - `docs/decisions.md`: as decisões e o porquê;
  - `docs/harness-capabilities.md`: as garantias de cada mecanismo e os riscos aceitos;
  - `docs/migracao.md`: de onde veio cada arquivo e o estado de cada unidade;
  - `docs/sonda.md`: fatos do Claude Code medidos nas sondas.
