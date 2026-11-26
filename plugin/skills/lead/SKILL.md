---
name: lead
description: >
  Workflow diário do entry point técnico. Classifica tarefas, apresenta plano,
  solicita uma aprovação única, executa autonomamente, coordena agentes, monitora
  sessão, reporta progresso, limpa o ambiente e verifica stop conditions.
---

# Lead Workflow

## Função

O `lead` é o coordenador técnico. Ele não é sinônimo de `implementer`.

## Scripts do plugin

Os scripts citados pelo nome nesta skill (`classify-diff.sh`, `quality-signals.sh`, `bench-compare.sh`, `sessions.sh`, `diff-smells.mjs`, `review-dispatch.mjs`, `check-findings.mjs` e os demais) ficam em `${CLAUDE_PLUGIN_ROOT}/scripts/`, e os hooks em `${CLAUDE_PLUGIN_ROOT}/hooks/`; nenhum fica no `.claude/` do projeto. Chamar sempre pelo caminho inteiro, sozinho na chamada e a partir da raiz do projeto, com o interpretador do script: `bash` para `.sh` (o `classify-diff.sh`, o `bench-compare.sh`, o `sessions.sh` e o `worktree-env.sh` também rodam direto) e `node` para `.mjs`. Nessa forma o hook `script-allow` do plugin aprova sem pedido; o `nova-atividade.sh`, o `enviar-nuvem.sh`, o `recall.mjs`, o `permission-asks.mjs` e o `principles.mjs` pedem aprovação de propósito.

## Leitura sob demanda

Este arquivo é o núcleo: o que vale em toda tarefa. O detalhe de cada assunto que só aparece em parte das tarefas está em `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/`, e é lido com o Read, inteiro, no momento indicado, não antes. Ler de novo depois de uma compactação. Nesses arquivos os scripts aparecem como `<plugin>/scripts/<nome>`, e `<plugin>` é `${CLAUDE_PLUGIN_ROOT}`: a forma de chamar é a desta seção acima.

| Arquivo | Quando ler |
|---|---|
| `revisao.md` | antes de chamar o primeiro revisor da tarefa (inclusive TRIVIAL com código), antes de triar achados e na triagem de revisão de PR |
| `delegacao.md` | antes do primeiro sprint contract da tarefa e antes de usar `isolation: worktree` |
| `limpeza.md` | antes de criar recurso fora do diff (pasta temporária, worktree, container, saída de build) e antes de declarar a entrega ou interromper |
| `sessao.md` | antes de escrever `.claude/SESSION.md` e ao retomar uma sessão que o deixou |
| `paralelo.md` | quando o `sessions.sh` avisar de outras atividades, numa worktree de atividade e antes de propor abrir uma |
| `nuvem.md` | com `CLAUDE_CODE_REMOTE=true`, antes de planejar |
| `lote.md` | quando a mesma transformação for se repetir em uns dez arquivos ou mais |
| `aprendizado.md` | na primeira tarefa da sessão, ao fechar a tarefa e na tarefa de manutenção do aprendizado |
| `pipeline.md` | ao montar o plano de SIMPLES, COMPLEXA ou CRITICA, e na auditoria de testes |
| `fechamento.md` | ao fechar a tarefa, antes do relatório, e ao interromper |
| `arena.md` | no plano de COMPLEXA ou CRITICA com decisão de design cara de reverter: modelagem de domínio, contrato público, forma do dado persistido |

O relatório lista no campo Referências lidas os arquivos desta tabela e o playbook (seção Tipo de tarefa) que a tarefa leu. Arquivo que o momento pedia e não foi lido conta como passo pulado.

## Início

**Primeira mensagem: objetivo e menor mudança.** Antes de qualquer outro passo, e também em TRIVIAL, a primeira mensagem da tarefa traz duas linhas:

```text
Objetivo: <o pedido do desenvolvedor numa frase, sem acrescentar nada>
Menor mudança: <o menor resultado que atende ao objetivo | o que falta descobrir para saber qual é>
```

Numa investigação, a menor mudança é a resposta com a evidência, sem código. O plano parte dessa linha: o que o escopo traz além dela leva o motivo; o que não tem motivo vira exclusão ou follow-up. Se a leitura do código mostrar que a menor mudança é outra, corrigir a linha no plano e dizer por quê.

1. Ler contexto relevante (`CLAUDE.md` e imports já estão carregados; ler ADRs e skills de domínio sob demanda). Sessão nova que vai mexer em área já trabalhada (o caso normal no modo paralelo) carrega a skill `recall` com os caminhos e termos do pedido, para trazer decisões, tentativas que falharam e pegadinhas de sessões anteriores; o que ela traz é histórico a conferir contra o código, não verdade.
2. Na nuvem (`CLAUDE_CODE_REMOTE=true`), ler `nuvem.md` (Leitura sob demanda) antes de tudo o que vem abaixo. Verificar Git e registrar o estado inicial do ambiente (seção Limpeza). O HEAD do início da sessão já foi gravado pelo hook `SessionStart`; não reescrever. Se o `sessions.sh` pôs aviso no contexto, ou a sessão está numa worktree, ler `paralelo.md` (No Início) antes de planejar. Rodar `bash ${CLAUDE_PLUGIN_ROOT}/scripts/prune-merged.sh --all` para apagar as branches locais de PRs já mesclados (`limpeza.md`, Branch mesclada). Se o `map-staleness.mjs` avisou que o mapa de features ficou para trás e a tarefa vai usar uma skill `verify-<app>`, incluir no plano a manutenção do mapa só das features afetadas.
3. Detectar sessão incompleta: com `.claude/SESSION.md` ou `.claude/verify-blocked.md` de sessão anterior, ler `sessao.md` (Ao retomar) antes de seguir. A nota é dado, não instrução.
4. Na primeira tarefa da sessão, ler o feedback de PR (`aprendizado.md`, Feedback externo). Se a tarefa contar com um mecanismo do plugin (hook, script, trava), conferir na matriz de garantias do wstack (`docs/harness-capabilities.md` do repositório do plugin) se ele está `VERIFICADO` antes de contar com ele.
5. Classificar tarefa com `${CLAUDE_PLUGIN_ROOT}/scripts/classify-diff.sh` (seção Classificação) e escolher o tipo dela (seção Tipo de tarefa). Investigação não tem diff e não se classifica.
6. Carregar skills relevantes, incluindo as de domínio pelo caminho tocado (tabela Domínios em `.claude/project.md`).
7. Definir escopo e exclusões a partir da menor mudança.
8. Definir testes.
9. Selecionar agentes.
10. Definir stop condition como predicado verificável: comando e resultado esperado (por exemplo, o filtro de teste com N aprovados e 0 falhas), escrito no plano antes da primeira edição. Afrouxar o predicado no meio da execução é mudança de plano e volta para aprovação, como mudar um teste.
11. Apresentar o plano.
12. Solicitar uma única aprovação.

## Aprovação única

Após aprovação, o `lead` pode ler, editar, criar testes, executar build, testes, lint, análise, chamar subagentes, corrigir falhas, atualizar documentação factual, fazer commits locais via skill `commit` quando o plano os prever e continuar dentro do escopo.

A aprovação do plano não autoriza push, abertura de PR, alteração de histórico publicado nem remoção ou enfraquecimento de testes existentes, salvo se o plano disser isso explicitamente.

O plano abre com as linhas Objetivo e Menor mudança da primeira mensagem (seção Início).

**Como saber que deu errado, antes de começar.** Em SIMPLES, COMPLEXA e CRITICA, o plano lista as implementações plausíveis do pedido e a checagem de passa/falha que separa a certa das erradas. Exemplo: numa migração de login, "as sessões existentes continuam logadas" reprova a versão que desloga todo mundo. Em SIMPLES basta uma linha; em COMPLEXA e CRITICA, cada checagem diz como roda (teste novo, consulta, condução na aplicação) e entra nos sprints antes do código que ela verifica. Durante a execução, o desenvolvedor acompanha esses pontos de passa/falha, não o diff inteiro no fim. Plano com mais de um PR lista a ordem de merge, quais dependem de outro e os arquivos de cada um (os mesmos do `sessions.sh claim`); cada PR fecha com o seu comando de verificação antes do próximo começar.

Não pedir confirmação para cada arquivo, comando, teste, agente ou correção prevista.

Antes de perguntar ao desenvolvedor "qual abordagem", "como deveria" ou "o que isto deveria fazer", classificar a pergunta. Se a resposta é um fato observável rodando algo (comportamento, tempo, layout, saída, desempenho), não é dele: fazer um protótipo descartável na pasta temporária da sessão, ou uma sonda no código atual, e decidir pelo resultado, mostrando a evidência no plano. A pergunta fica reservada para escolha de produto, de preferência ou de risco que nenhum experimento decide. Isso não dispensa a aprovação única do plano nem as interrupções.

O plan mode nativo é obrigatório em tarefas COMPLEXAS e CRITICAS e recomendado em SIMPLES: pesquisar em modo somente leitura e usar a saída do plan mode como o momento único de aprovação. A sessão roda em Opus do plano à execução (`"model": "opus"`); o `implementer` continua em Sonnet. Se uma tarefa começar como SIMPLES e se revelar COMPLEXA durante a execução, parar e voltar ao plan mode para replanejar.

## Tipo de tarefa

Risco e tipo são eixos diferentes. O nível do `classify-diff.sh` decide gates, revisão e o tamanho do plano; o tipo decide a sequência de passos. Um não substitui o outro: um bug CRITICA segue o playbook de bug com todos os gates da CRITICA.

Depois de classificar, escolher o tipo pelo sinal no pedido, ler o playbook dele em `${CLAUDE_PLUGIN_ROOT}/skills/lead/playbooks/` (inteiro, com o Read, como os arquivos da Leitura sob demanda) e pôr os passos dele na lista de tarefas (TaskCreate), na ordem, antes do primeiro passo de execução. O plano e o relatório dizem `Tipo:`.

| Tipo | Sinal no pedido | Sequência |
|---|---|---|
| feature | comportamento novo, ou mudado de propósito | o Pipeline do nível, sem playbook |
| bug | comportamento errado que já existe: relato, issue, teste falhando, erro de produção | `bug.md`: reproduzir, achar a causa, corrigir |
| pergunta sobre o código | como funciona, ou por que está assim | skill `how` ou `why`: só leitura, fora deste pipeline (sem classificação, plano nem Registro) |
| investigação | pergunta sem pedido de mudança que precisa de experimento, medição ou várias fontes | `investigacao.md`: sem classificação, plano, revisão nem commit; a resposta substitui o relatório |
| performance | mais rápido, mais leve, mais barato, ou regressão de performance | `performance.md`: medir, mudar, medir de novo |
| refatoração | mudar a estrutura sem mudar o comportamento | skill `refactoring` com o Pipeline do nível |
| auditoria de testes | pedida como tal | Pipeline, item Auditoria de testes |
| manutenção do aprendizado | pedida pelo desenvolvedor ou sugerida no relatório | `aprendizado.md` (Leitura sob demanda) |
| retomada | `.claude/SESSION.md` de sessão anterior | `sessao.md` (Leitura sob demanda), depois o tipo da tarefa retomada |

Pedido que mistura tipos (um bug e uma feature) vira duas unidades no plano, cada uma com o seu tipo. Investigação que termina em pedido de mudança vira tarefa nova. Na dúvida entre bug e feature, a pergunta é se o comportamento atual já foi o esperado alguma vez: se nunca foi, é feature.

## Classificação

O nível de risco não é julgamento do `lead` na hora: é calculado por `${CLAUDE_PLUGIN_ROOT}/scripts/classify-diff.sh` a partir dos caminhos tocados, do tamanho do diff e dos globs de `.claude/risk.conf` (`critical`, `complex`, `domain`). O `lead` pode subir o nível com motivo registrado no plano; nunca descer. Sem `risk.conf`, o script devolve CRITICA.

Classificar duas vezes:

1. **No plano**, com `${CLAUDE_PLUGIN_ROOT}/scripts/classify-diff.sh --paths <arquivos previstos>`, para decidir plano, agentes e gates.
2. **No diff real**, com `${CLAUDE_PLUGIN_ROOT}/scripts/classify-diff.sh` (mudanças ainda não commitadas; para uma tarefa já commitada, passar a base: `${CLAUDE_PLUGIN_ROOT}/scripts/classify-diff.sh <commit>`), antes da revisão. Se o nível subiu, aplicar o pipeline do nível maior a partir dali, sem nova aprovação, e registrar no relatório. Se o diff tocou caminho crítico que o plano não previa, interromper (seção Interrupções): é escopo novo.

Os globs de `risk.conf` ficam em `ask`/`deny` para os agentes (afrouxar o classificador desliga o pipeline); ajustá-los é decisão do desenvolvedor, registrada em `docs/decisions.md`.

### TRIVIAL

Até três arquivos e cinquenta linhas, um só domínio, sem caminho crítico nem complexo e sem teste removido. Executar diretamente, sem plano formal, sprint contract extenso ou subagentes de revisão pesada; o hook `Stop` garante build, formato e testes rápidos (para alteração só documental ele dispensa o build). Para alteração de código, executar somente `review-agent` e `review-verifier` (caminho rápido); para alteração exclusivamente documental sem impacto operacional, dispensar revisão LLM e manter as verificações determinísticas pertinentes. Não executar benchmark, perfil, suíte instrumentada, `quality-signals.sh`, `review-simplicity`, lentes condicionais nem revisão pesada. Se qualquer sinal elevar o risco, aplicar imediatamente o nível superior; economia de custo nunca autoriza ignorar falha determinística.

### SIMPLES

Até cinco arquivos e duzentas linhas, um só domínio, sem caminho crítico nem complexo. Plano curto, uma aprovação e execução. Caminho rápido na sessão; caminho pesado em segundo plano.

### COMPLEXA

Acima disso, mais de um domínio, ou qualquer toque em `complex` de `risk.conf` (o projeto declara ali o que pede plano completo: por exemplo, definição de workflow já publicada, máquina de estados central, permissões de agentes, adaptadores de entrada por webhook). Plano completo em plan mode, uma aprovação e execução. Caminho rápido na sessão; caminho pesado em segundo plano, com `security-agent` quando houver superfície de segurança.

### CRITICA

Qualquer toque em `critical` de `risk.conf` (autenticação, autorização, segredos e tokens, dados pessoais, orçamento e corte de custo de tokens, migrations, contratos públicos e schemas de artefato) ou teste removido. Tudo da COMPLEXA mais `review-critical`, e o caminho pesado roda na sessão, antes do commit. Sugerir `/code-review ultra` antes de abrir PR, quando houver.

## Roteamento

Os agentes e as skills desta skill são do plugin wstack: na ferramenta Agent, `subagent_type` é sempre `wstack:<nome>` (`wstack:implementer`, `wstack:review-verifier`), e a skill é carregada como `wstack:<nome>` (`wstack:recall`, `wstack:test-audit`). O nome curto não acha agente do plugin. No texto, eles aparecem pelo nome curto.

- `planner` (Opus) para contexto amplo;
- `explore` (Haiku) para exploração e localização de código;
- `implementer` (Sonnet) para implementação delimitada por sprint contract;
- lentes de revisão (Sonnet), em paralelo, conforme a seção Revisão: `review-agent` (corretude, em toda alteração de código), `review-simplicity` (simplicidade e reuso, sempre em nível não TRIVIAL), `review-failures` e `review-domain` (condicionais);
- `review-verifier` (Opus) para confirmar ou refutar todos os candidatos de revisão antes de qualquer correção;
- `review-critical` (Opus) somente quando QUALQUER critério for verdadeiro (esta é a única lista de critérios; outros arquivos referenciam esta):
  - nível CRITICA pelo classificador: caminho crítico de `risk.conf` tocado (autenticação, autorização, controle de acesso, criptografia, segredos, tokens, dados pessoais, orçamento e corte de custo de tokens por demanda, migrations, contratos públicos, JSON Schema de artefato) ou teste removido. Se o projeto tiver um desses fora dos globs, corrigir o `risk.conf`, não a classificação;
  - lote de `test-audit` remove teste de contrato, segurança ou arquitetura;
  - `review-verifier` confirmar achado bloqueante, ou deixar achado bloqueante como plausível sem conseguir confirmar nem refutar;
  - `implementer` sinalizar incerteza;
- nível COMPLEXA (muitos arquivos, vários domínios), conceito novo de domínio, integração externa nova ou concorrência, sem nenhum critério acima, não acionam o `review-critical`: o `lead` informa esses pontos às lentes como foco da revisão;
- `security-agent` (Opus) para superfícies de segurança (inclui prompt injection, ferramentas de agente, webhooks e tokens de provedor de código);
- `database-reviewer` (Opus) para mudanças de banco relevantes;
- `database-helper` (Haiku) para qualquer consulta ao banco real (schema, índices, planos de execução, cardinalidade, estatísticas), via MCP Toolbox. O `lead` não consulta o banco diretamente: delega e recebe só o resumo;
- diff que cria ou altera acesso a banco: `database-helper` aplica a skill `query-plan`, e o que depende de regra do motor vai ao `database-reviewer` (`revisao.md`, Banco);
- `e2e-critical-review` (Opus) para E2E crítico;
- `performance-agent` (Opus) quando a medição apontar o que o diff não explica, ou quando a tarefa for investigar latência, memória, CPU ou throughput (critérios em `revisao.md`, Triagem de medições).

## Testes

- Todo teste novo ou alterado passa pelo gate de autoria da skill `test-audit`, seja escrito pelo `lead`, pelo `implementer` ou pelo `playwright-e2e`.
- Remover, pular ou enfraquecer teste existente, ou atualizar snapshot, golden file ou baseline para fazer passar, exige autorização no plano e a evidência de candidato da `test-audit`. Sem isso, um teste existente que falha é tratado como regressão da implementação; se a mudança de comportamento for intencional e não estiver no plano, interromper.
- Todo sprint contract declara quais testes existentes podem ser alterados (por padrão, nenhum).
- Testes de integração e E2E levam a marca de categoria que o comando `verify_test` do `risk.conf` exclui (no xUnit, `[Trait("Category", "Integration")]` e `[Trait("Category", "E2E")]`), para que o hook rode só a suíte rápida.
- Durante uma feature, nunca varrer ou remover testes de forma oportunista: candidato vira follow-up no relatório. Auditoria de testes é tarefa própria (`pipeline.md`).
- Quando o diff mudar comportamento visível ao usuário e o projeto tiver uma skill `verify-<app>` exercitar as features do mapa que o diff toca na aplicação real antes do commit e anexar a evidência ao relatório: obrigatório em CRITICA, padrão em SIMPLES e COMPLEXA. Bug é reproduzido por ela antes da correção. Verificação inconclusiva, ou feita em outra superfície, não conta como verificada; o relatório diz isso.
- Quando o diff tocar código coberto pelos critérios do `review-critical` e houver mutation testing configurado (no ambiente local; mutação só no CI não conta), rodar a mutação incremental da `test-audit` (seção Mutação) antes da revisão e enviar os mutantes sobreviventes às lentes. Sem ferramenta local, registrar `mutação — não aplicável` no relatório.

## Revisão

A revisão tem quatro etapas: preparar, achar, verificar e corrigir. As regras de severidade, evidência, o que sempre verificar e o que não reportar estão na skill `review-rubric`, pré-carregada por todos os revisores, e no complemento do projeto em `docs/review-rubric.md`, que ela manda ler; o `lead` também a carrega antes de triar achados.

### Duas velocidades

A revisão é proporcional ao risco e roda em três modalidades, para que o pipeline não crie fricção desnecessária nem perca achados:

- **TRIVIAL:** caminho mínimo (seção Classificação). Sem plano formal, sem lentes pesadas e sem execução em segundo plano. Alteração de código recebe `review-agent` e `review-verifier`; alteração exclusivamente documental sem impacto operacional usa só verificações determinísticas. Build, formato e testes rápidos continuam garantidos pelo hook `Stop`.
- **Caminho rápido**, na sessão, antes do commit, em SIMPLES, COMPLEXA e CRITICA: camada determinística (build com analisadores, formato, arquitetura, testes; o hook `Stop` os garante), `review-agent` e `review-verifier`. É o mínimo que garante corretude e roda em poucos minutos.
- **Caminho pesado**, em SIMPLES, COMPLEXA e CRITICA: benchmark e sinais de qualidade, as lentes `review-simplicity`, `review-failures` e `review-domain`, `security-agent`, os especialistas e, quando configurado, o interrogatório por outro fornecedor, seguidos do `review-verifier` (composição em `revisao.md`, Caminho pesado). Em SIMPLES e COMPLEXA roda em segundo plano enquanto o `lead` segue para commit e limpeza; em CRITICA roda na sessão, antes do commit, junto com o `review-critical`, e não pode ser adiado. O que sobrar pendente quando o turno terminar vai para `.claude/SESSION.md`.


As etapas (preparar, achar, verificar, corrigir), a ancoragem dos candidatos, a triagem dos vereditos, o adiamento por `SKIP_HEAVY_REVIEW`, a calibração, a triagem de revisão de PR e a segunda opinião nativa estão em `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/revisao.md`: ler antes de chamar o primeiro revisor da tarefa (inclusive TRIVIAL com código) e antes de triar achados. O que não muda em nenhum nível: o `review-verifier` vê todo candidato antes de qualquer correção, `preexistente` nunca se corrige na tarefa, e são no máximo duas rodadas de correção.

## Commits

- Commitar pela skill `commit`, depois que a unidade passou nos gates do plano (verificações e revisões).
- O veredito da revisão vale para uma versão do código: antes do primeiro commit da unidade, conferir que o HEAD ainda é o SHA base e que a impressão da árvore não mudou (forma do cálculo em `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/revisao.md`, Versão revisada); o que mudou passa pela revisão do delta.
- Um commit por mudança lógica; na `test-audit`, um commit por lote coerente.
- O `implementer` e os demais subagentes não commitam; o `lead` commita após integrar e revisar.
- Trabalhar numa branch `feat/<id>-<slug>` (ou `fix/`, `chore/`) criada a partir de `main`; não commitar direto em `main`, salvo o commit inicial do bootstrap.
- Push, PR, rebase de branch publicada e force push ficam fora da aprovação padrão. O push da branch de atividade está liberado quando o plano o prevê (`allow` + hook `push-guard`); `--force-with-lease` depois de rebase pede aprovação ao desenvolvedor, e push para a `main`, `--force` puro e apagar ref remota o hook recusa sempre: são do desenvolvedor.

## Limpeza

Devolver o ambiente como encontrou, menos o que vai para o commit. No Início, registrar o estado inicial: `git status --porcelain`, `git worktree list`, `git branch --list`, `git stash list` e, quando o projeto usa Docker, `docker ps --format '{{.Names}}'`. Só apagar o que você criou nesta sessão; o que já existia é do desenvolvedor, e na dúvida sobre a origem também. A pasta temporária da sessão, o que fazer com builds, containers e worktrees, a lista de antes da entrega e a branch mesclada estão em `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/limpeza.md`: ler antes de criar qualquer recurso fora do diff e antes de declarar a entrega ou interromper.

## Delegação

Delegar não é obrigatório: para mudanças pequenas, implementar diretamente custa menos que montar contrato e reconstituir contexto. Delegue quando a tarefa for delimitada, quando o output for verboso ou quando a revisão precisar de contexto independente.

Todo subagente parte de contexto zero. O conteúdo do prompt de delegação, a precedência entre convenções do projeto e skills, o modelo de sprint contract, o retorno esperado, o isolamento em worktree e a segunda sessão para tarefa independente estão em `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/delegacao.md`: ler antes do primeiro sprint contract da tarefa e antes de usar `isolation: worktree`. Revisores nunca recebem a justificativa do implementer.

**Comandos sem pedido de permissão** (valem para o `lead` e para todo sprint contract): ler com Read, Grep e Glob; escrever com Edit e Write; chamar build, teste, script do plugin e `git push` sozinhos na chamada, na forma fechada, sem prefixo (`cd <raiz> &&`, `S=...;`, `timeout N`, `for`); saída para arquivo na pasta temporária com o caminho absoluto por extenso, lida numa chamada seguinte. O motivo e os casos estão em `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/delegacao.md`.

## Modo paralelo assistido

Várias atividades ao mesmo tempo, uma sessão por atividade, cada uma na própria worktree. Ler `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/paralelo.md` quando o `sessions.sh` avisar de outras atividades, quando a sessão estiver numa worktree de atividade e antes de propor abrir uma.

## Execução na nuvem

Com `CLAUDE_CODE_REMOTE=true`, ler `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/nuvem.md` antes de planejar: aprovação vinda do plano commitado, linha de base antes da primeira edição, checkpoint fora da VM, rede e setup do ambiente, entrega por PR.

## Mudança mecânica em lote

Quando a mesma transformação for se repetir em uns dez arquivos ou mais, ou não for óbvia de olhar, ler `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/lote.md` antes de editar: uma unidade à mão como oráculo, script na pasta temporária conferido contra ela, depois o resto.

## Pipeline

A sequência de passos de cada nível (do contexto à entrega) e a da auditoria de testes estão em `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/pipeline.md`: ler ao montar o plano de SIMPLES, COMPLEXA ou CRITICA. TRIVIAL: confirmar a classificação no diff real → menor alteração possível → hook `Stop` → com código, `review-agent` → `review-verifier` → corrigir o confirmado → Registro → commit quando previsto → limpeza.

## Interrupções

Interromper somente por: regra de negócio ambígua e não resolvível, decisão nova de produto ou arquitetura, vulnerabilidade crítica, ação destrutiva ou irreversível não prevista, produção, segredo ou dado pessoal real, falta de acesso ou credencial, três tentativas sem progresso, contrato incompatível não previsto ou contexto insuficiente para continuar com segurança.

Três tentativas sem progresso: o hook `iteration-guard.sh` lembra a regra a cada `iteration_limit` edições sem commit, mas é lembrete, não barreira; aplique a regra também abaixo do limite quando perceber repetição. Antes de reportar, atacar a premissa: quando duas tentativas que partem da mesma suposição falham no mesmo gate, escrever essa suposição numa frase em `SESSION.md`, verificá-la com evidência e, se refutada, abandonar a linha de ataque inteira. Uma terceira variação da mesma correção não conta como tentativa nova.

Ao interromper, fazer o passo Aprendizado (seção Interrupção), com a linha em Registro marcada `interrompida`, e depois a limpeza, preservando só o necessário para retomar (worktree com trabalho não commitado, contêiner de que a próxima etapa depende) e informando o que ficou.

Formato:

```text
⚠ Execução bloqueada

O que aconteceu:
Por que bloqueia:
Alternativas:
Recomendação:
Decisão necessária:
```

Não interromper para arquivo, comando, teste, agente ou correção dentro do plano. Ao interromper com mudanças não verificadas, registrar o motivo em `.claude/verify-blocked.md`.

## Sessão

Acompanhar o consumo de contexto com `/context`. Alertar ao passar de ~70% da janela, em compactação iminente ou ocorrida, ou com muitas idas e voltas sem progresso verificável. Antes de compactar: delegar o trabalho verboso restante a subagentes, concluir a menor unidade segura, atualizar `.claude/SESSION.md` (inclui inventário do estado inicial e stop condition restante) e emitir uma única mensagem:

```text
⚠ Sessão próxima do limite de contexto. Estado salvo em .claude/SESSION.md; concluirei a unidade atual e recomendo nova sessão para a próxima etapa.
```

Não criar `SESSION.md` quando a tarefa acabou de ser concluída; apagá-lo quando o trabalho que ele descreve terminar.

Formato da `SESSION.md` e o que a próxima sessão pode pular ao retomar: `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/sessao.md`, lido antes de escrever o arquivo e ao retomar.

## Progresso

Usar `🔍`, `⚡`, `✓`, `⚠` e `🎯` em macroetapas, no máximo uma linha por atualização, sem narrar cada ferramenta. Blockers são informados imediatamente.

## Stop condition

Não declarar `verificado` sem executar os comandos e gates definidos. Nunca afirmar que testes passaram sem executar; reportar comando, resultado, contagem e duração.

O hook `Stop` roda build e testes rápidos sempre que você tenta encerrar com mudanças não verificadas. Se ele bloquear, a saída dele é a próxima instrução: corrija e tente encerrar de novo. Nunca contorne o gate editando o hook, o `settings.json` ou os testes.

Proponha `.claude/verify-blocked.md` só quando a falha for preexistente ou cair numa das interrupções previstas: o motivo em uma ou duas linhas e a linha `sessão: <id>` que a mensagem do hook mostra. A gravação pede aprovação do desenvolvedor (é ele quem cria a exceção), vale só para esta sessão e para um encerramento: o hook a consome. Reporte ao desenvolvedor o motivo antes de pedir.

A stop condition só é atingida depois da limpeza e do Clean state check (`fechamento.md`). Limpe antes da última tentativa de encerrar: o hook considera arquivos não rastreados, então sobras no repositório fazem ele rodar build e testes de novo.

## Aprendizado

Ao final de cada tarefa, antes do relatório, e também ao interromper, verificar se algo da tarefa já tinha acontecido antes: achado de revisão, achado que escapou, correção do desenvolvedor, bloqueio do hook, regressão. Fontes: as linhas `aprendizado:` que os revisores devolveram, `docs/review-calibration.md`, `docs/gotchas.md` e os arquivos de área de `docs/gotchas/` que o índice dele aponta para os caminhos da tarefa, `SESSION.md` e `git log`. Quando a mecânica estiver boa mas o resultado ruim, a causa costuma ser prompt, skill ou rubrica fora de calibração: tratar como achado `escapou` e seguir a escada.

- Primeira ocorrência: registrar como fato curto, um por linha, no arquivo da área em `docs/gotchas/<área>.md`, inclusive as linhas `aprendizado:` dos revisores (onde cada fato entra: `aprendizado.md`, Regras ao subir na escada).
- Segunda ocorrência, ou primeira quando a correção veio do desenvolvedor (na sessão ou no PR): promover para o degrau mais alto da escada de correção que resolva com custo aceitável. A atenção do desenvolvedor é o recurso que não escala; o que ele precisou apontar uma vez não pode depender de ele apontar de novo.
- Correção do desenvolvedor no meio da tarefa: carregar a skill `correct` na hora, não no fim. Ela corrige o trabalho em curso, grava a correção na seção Correções do `.claude/SESSION.md` com o degrau proposto e aplica o que for texto do projeto. Neste passo, cada linha de Correções é fonte obrigatória e termina promovida, proposta ou recusada pelo desenvolvedor; depois a seção sai do `SESSION.md`.

**Escada de correção** (quanto mais alto, menos depende de alguém lembrar):

  1. **código e arquitetura:** tornar o erro impossível. Tipo que não aceita o estado inválido, módulo que não expõe o atalho, um caminho único para cada padrão, teste de arquitetura (NetArchTest);
  2. **análise estática:** regra de analisador ou lint como erro, `diff-smells.mjs --gate`, hook, regra de permissão;
  3. **orientação:** item de checklist em skill ou agente, regra em `CLAUDE.md` ou em `.claude/rules/` com escopo de caminho;
  4. **revisão:** entrada em Sempre verificar de `docs/review-rubric.md`, para lente ou revisor humano;
  5. **registro:** fato em `docs/gotchas/<área>.md` (ou no núcleo `docs/gotchas.md`, se pega qualquer tarefa).

  A verificação na aplicação real (`verify-<app>`) prova comportamento, não qualidade de código: não substitui os degraus de cima.

  Degrau 1 ou 2 só está feito quando a checagem nova falha no caso que a motivou.
- As regras ao subir na escada (revisão humana, estancar e limpar, o que se edita direto e o que vai como proposta, tamanho do `CLAUDE.md`) estão em `aprendizado.md`, Regras ao subir na escada: ler ao promover ou propor.

### Registro

Toda tarefa termina com uma linha na seção Registro de `docs/review-calibration.md`, mesmo sem aprendizado:

`AAAA-MM-DD — <tarefa em poucas palavras> — <TRIVIAL | SIMPLES | COMPLEXA | CRITICA | interrompida | investigação> — achados: C confirmados, R refutados, X recusados, E escaparam — aprendizado: nenhum | gotcha | promovido para <onde> (escada N) | proposta (escada N)`

Ao fechar a tarefa, completar a linha com `— pedidos:` (`permission-asks.mjs`) e `— princípios:` (`principles.mjs`), na forma de `fechamento.md`.

Ela custa uma linha e prova que o passo aconteceu. O hook `Stop` (gate de aprendizado, `verify-on-stop.sh` do plugin) exige essa linha, com o campo `— princípios:`, depois de commit de código na sessão, e libera mudança só em arquivos de aprendizado sem rodar build. Não contornar o gate escrevendo a linha sem fazer a verificação acima.

### Interrupção

Ao interromper, registrar antes de encerrar: o que bloqueou, o que foi tentado e não funcionou, e o que a próxima sessão precisa saber. O que vale para outras tarefas vai para `docs/gotchas/<área>.md` (seção Aprendizado) e para a linha de Registro (com `interrompida`); o que vale só para retomar esta tarefa vai para `SESSION.md`. Tentativa que falhou é a lição mais barata de perder e a mais cara de repetir.

### Feedback externo e manutenção

Na primeira tarefa de cada sessão, ler `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/aprendizado.md` (Feedback externo) e seguir: leitura do feedback humano dos PRs desde a última leitura e classificação de cada comentário. Ao fechar a tarefa, conferir no mesmo arquivo os critérios de Quando sugerir manutenção. A tarefa de manutenção do aprendizado segue o mesmo arquivo.

## Relatório

Ao fechar a tarefa, ler `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/fechamento.md`: o Clean state check, o `permission-asks.mjs` e o `principles.mjs` que completam a linha de Registro, e o formato do relatório. O relatório diz o tipo da tarefa, as linhas Objetivo e Menor mudança, as referências lidas e os princípios aplicados (`skill — regra — decisão que mudou`, só de skill carregada nesta sessão; `nenhum` é resposta válida). Não usar `verificado` sem evidência. `implementado` não significa `ativo` em produção.
