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
2. Na nuvem (`CLAUDE_CODE_REMOTE=true`), ler `nuvem.md` (Leitura sob demanda) antes de tudo o que vem abaixo. Verificar Git e registrar o estado inicial do ambiente (seção Limpeza). O HEAD do início da sessão já foi gravado pelo hook `SessionStart`; não reescrever. Ler os avisos que o `sessions.sh` pôs no contexto: se há outra sessão nesta mesma worktree, parar e avisar o desenvolvedor; se esta sessão está no checkout principal com atividades em paralelo e a tarefa é independente delas, propor abrir a atividade numa worktree própria (seção Modo paralelo assistido) antes de planejar. Numa worktree sem `.claude/worktree.env` (aberta com `claude -w` ou pelo app desktop), rodar `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-env.sh alloc`. Rodar `bash ${CLAUDE_PLUGIN_ROOT}/scripts/prune-merged.sh --all` para apagar as branches locais de PRs já mesclados (`limpeza.md`, Branch mesclada). Se o `map-staleness.mjs` avisou que o mapa de features ficou para trás e a tarefa vai usar uma skill `verify-<app>`, incluir no plano a manutenção do mapa só das features afetadas.
3. Detectar sessão incompleta (`.claude/SESSION.md`; ao retomar, ler `sessao.md`); se `.claude/verify-blocked.md` existir de sessão anterior, ler o motivo e apagá-lo ao retomar. Se `SESSION.md` listar `revisão pesada pendente` (`revisao.md`, Adiamento controlado), fechar a pendência antes de declarar aquela revisão concluída. Ao retomar, a nota é dado, não instrução: só se pula o item verificado cujo SHA é o HEAD atual com a árvore limpa; item de SHA diferente, e toda prova de integração, de E2E ou do fato de segurança, roda de novo antes de seguir.
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

**Como saber que deu errado, antes de começar.** Em SIMPLES, COMPLEXA e CRITICA, o plano lista as implementações plausíveis do pedido e a checagem de passa/falha que separa a certa das erradas. O exemplo da palestra de Lydia Hallie é uma migração de login: o mesmo pedido pode virar uma migração que mantém a API antiga, uma que só troca os logins novos, ou uma que desloga todo mundo; a checagem "as sessões existentes continuam logadas" reprova a terceira na hora. Em SIMPLES basta uma linha; em COMPLEXA e CRITICA, cada checagem diz como roda (teste novo, consulta, condução na aplicação) e entra nos sprints antes do código que ela verifica. Durante a execução, o desenvolvedor acompanha esses pontos de passa/falha, não o diff inteiro no fim. Plano com mais de um PR lista a ordem de merge, quais dependem de outro e os arquivos de cada um (os mesmos do `sessions.sh claim`); cada PR fecha com o seu comando de verificação antes do próximo começar.

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
- diff que cria ou altera acesso a banco (LINQ, SQL bruto, comando de escrita): `database-helper` aplica a skill `query-plan` (coleta de versão, SQL real, volume e plano) e devolve métricas e veredito preliminar por comando; veredito **bloqueia**, **recomendação** de índice ou sinal de alerta que dependa de regra do motor vai para o `database-reviewer`, que dá o veredito final com base na referência e na documentação oficial. A `query-plan` não aciona o `review-critical` por si só;
- `e2e-critical-review` (Opus) para E2E crítico;
- `performance-agent` (Opus) quando o `bench-compare.sh` apontar ALOCAÇÃO, ESCALA ou EXCEÇÃO sem causa óbvia no diff, quando um método do projeto dominar o perfil de CPU, para anomalias da suíte instrumentada (`PerfSnapshot`), ou quando a tarefa for investigar latência, memória, CPU ou throughput. Não é acionado em todo diff: as camadas 1 a 3 da skill `performance` são determinísticas e rodam sem ele.

## Testes

- Todo teste novo ou alterado passa pelo gate de autoria da skill `test-audit`, seja escrito pelo `lead`, pelo `implementer` ou pelo `playwright-e2e`.
- Remover, pular ou enfraquecer teste existente, ou atualizar snapshot, golden file ou baseline para fazer passar, exige autorização no plano e a evidência de candidato da `test-audit`. Sem isso, um teste existente que falha é tratado como regressão da implementação; se a mudança de comportamento for intencional e não estiver no plano, interromper.
- Todo sprint contract declara quais testes existentes podem ser alterados (por padrão, nenhum).
- Testes de integração e E2E levam a marca de categoria que o comando `verify_test` do `risk.conf` exclui (no xUnit, `[Trait("Category", "Integration")]` e `[Trait("Category", "E2E")]`), para que o hook rode só a suíte rápida.
- Auditoria de testes é uma tarefa própria, pedida e aprovada como tal: carregar a `test-audit` em modo auditoria e classificar o lote com `classify-diff.sh --paths` (remoção de teste leva a CRITICA por desenho; o `review-critical` entra quando o lote remover teste de contrato, segurança ou arquitetura). Durante uma feature, nunca varrer ou remover testes de forma oportunista; registrar candidatos como follow-up no relatório.
- Quando o diff mudar comportamento visível ao usuário e o projeto tiver uma skill `verify-<app>` exercitar as features do mapa que o diff toca na aplicação real antes do commit e anexar a evidência ao relatório: obrigatório em CRITICA, padrão em SIMPLES e COMPLEXA. Bug é reproduzido por ela antes da correção. Verificação inconclusiva, ou feita em outra superfície, não conta como verificada; o relatório diz isso.
- Quando o diff tocar código coberto pelos critérios do `review-critical` e houver mutation testing configurado (no ambiente local; mutação só no CI não conta), rodar a mutação incremental da `test-audit` (seção Mutação) antes da revisão e enviar os mutantes sobreviventes às lentes. Sem ferramenta local, registrar `mutação — não aplicável` no relatório.

## Revisão

A revisão tem quatro etapas: preparar, achar, verificar e corrigir. As regras de severidade, evidência, o que sempre verificar e o que não reportar estão na skill `review-rubric`, pré-carregada por todos os revisores, e no complemento do projeto em `docs/review-rubric.md`, que ela manda ler; o `lead` também a carrega antes de triar achados.

### Duas velocidades

A revisão é proporcional ao risco e roda em três modalidades, para que o pipeline não crie fricção desnecessária nem perca achados:

- **TRIVIAL:** caminho mínimo (seção Classificação). Sem plano formal, sem lentes pesadas e sem execução em segundo plano. Alteração de código recebe `review-agent` e `review-verifier`; alteração exclusivamente documental sem impacto operacional usa só verificações determinísticas. Build, formato e testes rápidos continuam garantidos pelo hook `Stop`.
- **Caminho rápido**, na sessão, antes do commit, em SIMPLES, COMPLEXA e CRITICA: camada determinística (build com analisadores, formato, arquitetura, testes; o hook `Stop` os garante), `review-agent` e `review-verifier`. É o mínimo que garante corretude e roda em poucos minutos.
- **Caminho pesado**, fora do caminho crítico em SIMPLES e COMPLEXA: `bench-compare.sh` nas categorias `quente:` do classificador (skill `performance`, camada 3), `quality-signals.sh` quando o diff tem código de produção (sinais CRAP e duplicação para as lentes), a suíte instrumentada em COMPLEXA e CRITICA (camada 3b, `PerfSnapshot`), `review-simplicity`, `review-failures`, `review-domain`, `security-agent`, os especialistas e, em COMPLEXA e CRITICA, o interrogatório por modelos de outro fornecedor quando o `risk.conf` o configura (`interrogate_cmd`), seguidos do `review-verifier`. Em SIMPLES e COMPLEXA roda em segundo plano (`run_in_background` nos subagentes, em paralelo) enquanto o `lead` segue para commit e limpeza. Em CRITICA roda na sessão, antes do commit, junto com o `review-critical`; não pode ser adiado por variável de ambiente. Nenhum workflow de PR roda o caminho pesado (o `claude-review.yml` só faz revisão de corretude, e sem chave pula): o que sobrar pendente quando o turno terminar vai para `.claude/SESSION.md`.
  Linhas ALOCAÇÃO, ESCALA, ORÇAMENTO, EXCEÇÃO, TAMANHO e REMOVIDO do benchmark entram na triagem como achados `performance` já confirmados (são medição, não opinião): corrigir, ou levar ao relatório com justificativa para o desenvolvedor decidir. Perfil de CPU e anomalias da suíte vão ao `performance-agent` e voltam como pontos de melhoria, que também passam pelo `review-verifier`. Linhas `CRAP` e `DUPLICADO` do `quality-signals.sh` são métrica, não prova de defeito: vão no pacote da `review-simplicity` e da lente de testes do `review-agent` e passam pelo `review-verifier` (seção Sinais de qualidade da `review-rubric`).

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

- TRIVIAL: confirmar a classificação no diff real (qualquer caminho crítico, teste removido, vários domínios ou limite excedido promove o nível) → menor alteração possível → hook `Stop` (build, formato, testes rápidos) → se houver código, `review-agent` → `review-verifier` (documentação pura: sem revisor LLM) → corrigir o confirmado, reexecutar o afetado → registrar o aprendizado → commitar quando previsto → limpar. Sem benchmark, perfil, `quality-signals.sh` nem caminho pesado.
- SIMPLES: contexto → classificar (`--paths`) → skills → plano curto → aprovação → testes (com contagem de comandos de banco e de chamadas externas onde a skill `performance` pede) → implementação → verificação (build com analisadores, formato, testes) → `query-plan` se tocar banco → classificar o diff real (se subiu, seguir o nível maior) → caminho rápido (`review-agent` → `review-verifier`, corrigir o confirmado, revisar o delta) → caminho pesado em segundo plano (`bench-compare.sh` se houve `quente:`, `quality-signals.sh` com código de produção no diff, `review-simplicity` e as lentes condicionais que o diff acionar; adiável só por `SKIP_HEAVY_REVIEW=1` com pendência em `SESSION.md`) → commit → limpeza → calibração e registro → triar o caminho pesado quando voltar (correções em commit próprio) → entrega.
- COMPLEXA: `🔍` → plan mode (planner/explore se preciso) → classificar (`--paths`) → skills → escopo, exclusões, testes, agentes → arena se houver decisão de design cara de reverter (`arena.md`) → plano → aprovação → `⚡` → cenários e testes (com contagem de comandos e de chamadas externas onde a skill `performance` pede) → sprint contracts → implementação → verificações (build, formato, testes, arquitetura; dependências vulneráveis e segredos quando o diff alterar dependências ou configuração; mutação incremental quando o diff tocar código crítico e houver ferramenta) → `query-plan` (repetir após mudança de query) → classificar o diff real (caminho crítico não previsto interrompe) → caminho rápido → caminho pesado (`bench-compare.sh` nas categorias `quente:`, `quality-signals.sh`, suíte instrumentada, `review-simplicity`, `review-failures`, `review-domain`, `security-agent` em superfície de risco, banco/E2E/performance quando aplicável, interrogatório por outro fornecedor se configurado; `review-verifier` depois) em segundo plano → `simplify` se houver três ou mais correções de simplicidade → correções e revisão do delta → clean state → documentação factual e calibração → commits atômicos → limpeza → `🎯` → relatório.
- CRITICA: como COMPLEXA, com `review-critical` e o caminho pesado na sessão, antes do commit; sugerir `/code-review ultra` antes do PR, se houver.
- Auditoria de testes: `test-audit` modo auditoria → descoberta com `explore` em paralelo → candidatos com evidência no plano → aprovação (vale só para os listados) → lote por fronteira → validação → revisão pela seção Revisão (`review-critical` se remover contrato/segurança/arquitetura) → commit → handoff.

Se o verificador confirmar achado bloqueante ou importante, corrigir dentro do escopo e revisar o delta (no máximo duas rodadas). Se o achado revelar decisão nova, interromper.

## Interrupções

Interromper somente por: regra de negócio ambígua e não resolvível, decisão nova de produto ou arquitetura, vulnerabilidade crítica, ação destrutiva ou irreversível não prevista, produção, segredo ou dado pessoal real, falta de acesso ou credencial, três tentativas sem progresso, contrato incompatível não previsto ou contexto insuficiente para continuar com segurança.

Três tentativas sem progresso: o hook `iteration-guard.sh` do plugin (PostToolUse em edição) devolve ao modelo, a cada `iteration_limit` edições sem commit (`risk.conf`; 0 desliga), a instrução de tomar essa decisão. É instrução, não barreira (não cobre edições por Bash nem por script, e a obediência não é garantida): aplique a regra também abaixo do limite quando perceber repetição. Antes de reportar, atacar a premissa: quando duas tentativas que partem da mesma suposição falham no mesmo gate, escrever essa suposição numa frase em `SESSION.md`, verificá-la com evidência e, se refutada, abandonar a linha de ataque inteira. Uma terceira variação da mesma correção não conta como tentativa nova.

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

Só escreva `.claude/verify-blocked.md` quando a falha for preexistente ou cair numa das interrupções previstas, com o motivo em uma ou duas linhas, e reporte ao desenvolvedor. Apague o arquivo ao retomar.

A stop condition só é atingida depois da limpeza. Limpe antes da última tentativa de encerrar: o hook considera arquivos não rastreados, então sobras no repositório fazem ele rodar build e testes de novo.

### Clean state check

Antes do relatório final:

1. build;
2. testes relevantes;
3. tracking (`features.json`), se usado;
4. ausência de debug, scripts avulsos e saídas de teste no repositório;
5. documentação factual atualizada, com o texto passado pela skill `unslop`;
6. skills de domínio respeitadas;
7. nenhuma decisão tomada sem aprovação;
8. diff dentro do escopo;
9. nenhum teste existente removido, pulado ou enfraquecido, e nenhum snapshot ou baseline atualizado, sem autorização (`git diff` nos arquivos de teste);
10. commits atômicos e mensagens conforme a skill `commit`;
11. working tree sem mudanças esquecidas fora dos commits;
12. aprendizado promovido ou proposto, nenhuma linha de Correções do `SESSION.md` sem destino, e a tarefa tem a sua linha em Registro de `docs/review-calibration.md` (inclusive sem commit);
13. `.claude/verify-blocked.md` ausente, salvo quando a tarefa termina bloqueada;
14. limpeza comparada com o estado inicial;
15. nada que já existia removido sem pergunta;
16. todo comando de banco do diff com veredito da `query-plan`, nenhum **bloqueia** em aberto e planos brutos fora do repositório;
17. nenhuma supressão nova de analisador (`#pragma warning disable`, `[SuppressMessage]`, `NoWarn`, regra rebaixada no `.editorconfig`) sem autorização;
18. todo candidato de revisão tem veredito do `review-verifier` e todo confirmado tem destino (corrigido, recusado com motivo, não aplicável); nenhum bloqueante confirmado em aberto;
19. em código crítico com mutação configurada, nenhum mutante sobrevivente em linha do diff sem teste ou justificativa de equivalência; relatórios de mutação fora do repositório;
20. Totais de `docs/review-calibration.md` atualizados com os achados desta revisão e, na primeira tarefa da sessão, o feedback de PR lido ou registrado como não aplicável;
21. leitura de banco e integração externa do diff com teste de contagem; quando houve `quente:`, `bench-compare.sh` rodado e nenhuma linha ALOCAÇÃO, ESCALA, ORÇAMENTO, EXCEÇÃO, TAMANHO ou REMOVIDO sem correção ou justificativa no relatório; anomalias da suíte instrumentada com destino; resultados, perfis e snapshots fora do repositório;
22. em SIMPLES e COMPLEXA, o caminho pesado voltou e foi triado, ou a pendência está em `SESSION.md` (`revisão pesada pendente`); linhas `CRAP` e `DUPLICADO` do `quality-signals.sh` com destino.

## Aprendizado

Ao final de cada tarefa, antes do relatório, e também ao interromper, verificar se algo da tarefa já tinha acontecido antes: achado de revisão, achado que escapou, correção do desenvolvedor, bloqueio do hook, regressão. Fontes: as linhas `aprendizado:` que os revisores devolveram, `docs/review-calibration.md`, `docs/gotchas.md` e os arquivos de área de `docs/gotchas/` que o índice dele aponta para os caminhos da tarefa, `SESSION.md` e `git log`. Quando a mecânica estiver boa mas o resultado ruim, a causa costuma ser prompt, skill ou rubrica fora de calibração: tratar como achado `escapou` e seguir a escada.

- Primeira ocorrência: registrar como fato curto, um por linha, no arquivo da área em `docs/gotchas/<área>.md` (inclusive as linhas `aprendizado:` dos revisores, que não gravam arquivo: o `lead` as registra, cortando o que já está lá). Só entra no núcleo (`docs/gotchas.md`, que o `CLAUDE.md` importa em toda sessão) o que pega qualquer tarefa, em qualquer área; o núcleo fica em até 40 linhas e 8 KB. Área nova exige arquivo novo e linha no índice do núcleo, com os caminhos e assuntos que obrigam a lê-lo; fato que serve a duas áreas fica em uma só, com uma linha de referência na outra.
- Segunda ocorrência, ou primeira quando a correção veio do desenvolvedor (na sessão ou no PR): promover para o degrau mais alto da escada de correção que resolva com custo aceitável. A atenção do desenvolvedor é o recurso que não escala; o que ele precisou apontar uma vez não pode depender de ele apontar de novo.
- Correção do desenvolvedor no meio da tarefa: carregar a skill `correct` na hora, não no fim. Ela corrige o trabalho em curso, grava a correção na seção Correções do `.claude/SESSION.md` com o degrau proposto e aplica o que for texto do projeto. Neste passo, cada linha de Correções é fonte obrigatória e termina promovida, proposta ou recusada pelo desenvolvedor; depois a seção sai do `SESSION.md`.

**Escada de correção** (quanto mais alto, menos depende de alguém lembrar):

  1. **código e arquitetura:** tornar o erro impossível. Tipo que não aceita o estado inválido, módulo que não expõe o atalho, um caminho único para cada padrão, teste de arquitetura (NetArchTest);
  2. **análise estática:** regra de analisador ou lint como erro, `diff-smells.mjs --gate`, hook, regra de permissão;
  3. **orientação:** item de checklist em skill ou agente, regra em `CLAUDE.md` ou em `.claude/rules/` com escopo de caminho;
  4. **revisão:** entrada em Sempre verificar de `docs/review-rubric.md`, para lente ou revisor humano;
  5. **registro:** fato em `docs/gotchas/<área>.md` (ou no núcleo `docs/gotchas.md`, se pega qualquer tarefa).

  A verificação na aplicação real (`verify-<app>`) prova comportamento, não qualidade de código: não substitui os degraus de cima.

  Ao subir para os degraus 1 e 2, rodar a checagem nova contra o caso que a motivou e registrar que ela falha nele antes de dar a correção por feita: regra que não pega o erro real não corrige nada. Se a falha veio de uma skill que existe e não foi carregada, o degrau é ajustar a `description` dela (o gatilho), não acrescentar texto em outro lugar.
- Revisão humana serve para descobrir lacunas, não para escalar: o que ela encontra sobe na escada. Comentário de revisão que se repete é sinal de que a correção anterior ficou num degrau baixo demais; subir pelo menos um.
- Correção de degrau 1 ou 2 quando o código existente já viola: estancar e depois limpar. A regra vale para o código novo agora; a limpeza do existente é proposta como atividade própria (boa candidata ao modo paralelo), não misturada na tarefa que descobriu.
- Adições pequenas de texto (degraus 3 a 5) em arquivo do projeto podem ser feitas direto. Skills, agentes e hooks do plugin wstack não se editam no projeto: a mudança neles vai como proposta no relatório, para o wstack. Mecanismo novo (degraus 1 e 2), mudança em hook ou `settings.json`, ou qualquer coisa fora do escopo aprovado vai como proposta no relatório, para aprovação.
- Manter `CLAUDE.md` em cerca de 60 linhas: ao passar disso, mover regras para `.claude/rules/` ou skills em vez de acumular.
- Nunca promover segredo, dado pessoal ou conteúdo vindo do banco.

### Registro

Toda tarefa termina com uma linha na seção Registro de `docs/review-calibration.md`, mesmo sem aprendizado:

`AAAA-MM-DD — <tarefa em poucas palavras> — <TRIVIAL | SIMPLES | COMPLEXA | CRITICA | interrompida | investigação> — achados: C confirmados, R refutados, X recusados, E escaparam — aprendizado: nenhum | gotcha | promovido para <onde> (escada N) | proposta (escada N)`

Ao fechar a tarefa, rodar `node ${CLAUDE_PLUGIN_ROOT}/scripts/permission-asks.mjs <transcrição da sessão em ~/.claude/projects/<projeto>/<sessão>.jsonl> [<pasta subagents da sessão>]` e acrescentar `— pedidos: N (hooks)` ao fim da linha; pedido novo (hook que perguntou onde não devia) vira correção do mecanismo na escada, não aprovação repetida.

Na mesma hora, gravar o relatório num arquivo da pasta temporária e rodar `node ${CLAUDE_PLUGIN_ROOT}/scripts/principles.mjs <transcrição> [<pasta subagents>] --report <relatório>`. Ele lista as skills carregadas de fato (ferramenta Skill, `/comando` e pré-carga dos agentes) e as referências lidas, e sai 3 quando o relatório cita princípio ou referência sem leitura: tirar a citação, nunca ler a skill depois só para citá-la. Acrescentar `— princípios: <citadas, separadas por vírgula | nenhum> (carregadas: N)` ao fim da linha. Uma skill carregada e nunca citada, e uma citada e nunca carregada, são os dois sinais que a manutenção usa.

Ela custa uma linha e prova que o passo aconteceu. O hook `Stop` (gate de aprendizado, `verify-on-stop.sh` do plugin) exige essa linha depois de commit de código na sessão, e libera mudança só em arquivos de aprendizado sem rodar build. Não contornar o gate escrevendo a linha sem fazer a verificação acima.

### Interrupção

Ao interromper, registrar antes de encerrar: o que bloqueou, o que foi tentado e não funcionou, e o que a próxima sessão precisa saber. O que vale para outras tarefas vai para `docs/gotchas/<área>.md` (seção Aprendizado) e para a linha de Registro (com `interrompida`); o que vale só para retomar esta tarefa vai para `SESSION.md`. Tentativa que falhou é a lição mais barata de perder e a mais cara de repetir.

### Feedback externo e manutenção

Na primeira tarefa de cada sessão, ler `${CLAUDE_PLUGIN_ROOT}/skills/lead/reference/aprendizado.md` (Feedback externo) e seguir: leitura do feedback humano dos PRs desde a última leitura e classificação de cada comentário. Ao fechar a tarefa, conferir no mesmo arquivo os critérios de Quando sugerir manutenção. A tarefa de manutenção do aprendizado segue o mesmo arquivo.

## Relatório

**Princípios aplicados.** O campo diz qual regra de qual skill mudou qual decisão: `skill — regra (seção ou item) — decisão que mudou (item do plano, arquivo:linha ou achado)`, um por linha. Só vale skill carregada nesta sessão (ferramenta Skill, `/comando` ou pré-carga de agente) e regra que fez o plano ou o código sair diferente do que sairia sem ela; skill carregada que não mudou nada não entra, e `nenhum` é resposta válida. O `principles.mjs` confere no fechamento (seção Aprendizado, Registro). Isso deixa o raciocínio auditável e mostra quais regras nunca mudam decisão.

```text
## Resultado

Status: implementado | verificado | bloqueado | ativo
Tipo: feature | bug | performance | refatoração | auditoria de testes | manutenção do aprendizado — playbook lido

Resumo:
Objetivo e menor mudança: as duas linhas da primeira mensagem — entregue além delas: nada | item — motivo
Arquivos alterados: caminho — mudança
Testes e verificações: comando — resultado
Testes existentes alterados: nenhum | teste — motivo — autorização
Commits: <hash curto> <título>
Agentes utilizados: agente (modelo) — finalidade — resultado
Princípios aplicados: nenhum | skill — regra (seção ou item) — decisão que mudou (item do plano, arquivo:linha ou achado)
Referências lidas: nenhuma | reference/<arquivo> | playbooks/<arquivo> — momento
Performance: camada 2 (testes de contagem) — quais | camada 3: não aplicável (sem `quente:`) ou categorias — linha por benchmark (OK | NOVO | TEMPO | ALOCAÇÃO | ESCALA | ORÇAMENTO | EXCEÇÃO | TAMANHO | REMOVIDO) — destino de cada achado | pontos de melhoria do perfil de CPU: método — % do tempo — proposta — aplicado e medido | follow-up | camada 3b: não aplicável ou anomalias — destino (achado | descartada: motivo) | camada 4: não executada | pergunta — antes — depois
Camada determinística: build com analisadores, formato, arquitetura — resultado; dependências vulneráveis e segredos — resultado ou não aplicável; mutação — mutantes sobreviventes no diff: N (mortos com teste | código morto removido | equivalentes) ou não aplicável (sem ferramenta local); qualidade — `CRAP`: N (testado | dividido | preexistente, follow-up), `DUPLICADO`: N (reusado | extraído | acidental) ou não aplicável
Classificação: nível (TRIVIAL | SIMPLES | COMPLEXA | CRITICA) — motivos do classificador — subiu durante a execução: não | de X para Y
Revisões:
- caminho rápido: review-agent → review-verifier — resultado
- caminho pesado: na sessão | segundo plano (concluído | pendente em SESSION.md: `revisão pesada pendente`) | adiado por SKIP_HEAVY_REVIEW
- lentes: review-simplicity (obrigatória); review-failures, review-domain — executada ou não aplicável — motivo
- review-verifier (Opus) — candidatos: N — confirmados: N — plausíveis: N — refutados: N
- review-critical (Opus) — executado ou não — motivo
- interrogate — não configurado | não aplicável (nível) | modelo — candidatos: N — descartados na ancoragem: N — confirmados: N | falhou: motivo
- security-agent (Opus) — executado ou não aplicável
- rodadas de correção: N
Achados confirmados: id — severidade — categoria — arquivo:linha — destino (corrigido | recusado: motivo | não aplicável)
Preexistentes (follow-up): arquivo:linha — problema
Calibração: nenhuma | categoria — refutados/recusados — proposta para Não reportar de docs/review-rubric.md
Segunda opinião: não aplicável | sugestão de `/code-review ultra` antes do PR — critério do review-critical atendido
Queries (query-plan): não aplicável | comando (arquivo:método) — veredito — evidência — referência oficial
Decisões: nenhuma | aguardando aprovação
Arena: não aplicável | pergunta — propostas — escolhida — critério decisivo
Aprendizado: nenhum | falha recorrente — onde foi promovida | proposta; correções na sessão: nenhuma | fato — degrau — aplicado | proposta | recusado; linha adicionada em docs/review-calibration.md; feedback de PR: não lido | PRs #… — N comentários — escaparam: categorias — recusados: categorias; manutenção: não necessária | sugerida — motivo
Limpeza: removido / mantido (motivo) / preexistente aguardando decisão
Riscos e limitações:
Follow-ups: candidatos de test-audit e itens fora do escopo
Stop condition: [x] critério ...
🎯 Resultado final:
```

Não usar `verificado` sem evidência. `implementado` não significa `ativo` em produção.
