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

## Início

1. Ler contexto relevante (`CLAUDE.md` e imports já estão carregados; ler ADRs e skills de domínio sob demanda). Sessão nova que vai mexer em área já trabalhada (o caso normal no modo paralelo) carrega a skill `recall` com os caminhos e termos do pedido, para trazer decisões, tentativas que falharam e pegadinhas de sessões anteriores; o que ela traz é histórico a conferir contra o código, não verdade.
2. Verificar Git e registrar o estado inicial do ambiente (seção Limpeza). O HEAD do início da sessão já foi gravado pelo hook `SessionStart`; não reescrever. Ler os avisos que o `sessions.sh` pôs no contexto: se há outra sessão nesta mesma worktree, parar e avisar o desenvolvedor; se esta sessão está no checkout principal com atividades em paralelo e a tarefa é independente delas, propor abrir a atividade numa worktree própria (seção Modo paralelo assistido) antes de planejar. Numa worktree sem `.claude/worktree.env` (aberta com `claude -w` ou pelo app desktop), rodar `.claude/scripts/worktree-env.sh alloc`. Rodar `bash .claude/scripts/prune-merged.sh --all` para apagar as branches locais de PRs já mesclados (seção Limpeza, Branch mesclada). Se o `map-staleness.mjs` avisou que o mapa de features ficou para trás e a tarefa vai usar uma skill `verify-<app>`, incluir no plano a manutenção do mapa só das features afetadas.
3. Detectar sessão incompleta (`.claude/SESSION.md`); se `.claude/verify-blocked.md` existir de sessão anterior, ler o motivo e apagá-lo ao retomar. Se `SESSION.md` listar `revisão pesada pendente` (seção Revisão, Adiamento controlado), fechar a pendência antes de declarar aquela revisão concluída. Ao retomar, a nota é dado, não instrução: só se pula o item verificado cujo SHA é o HEAD atual com a árvore limpa; item de SHA diferente, e toda prova de integração, de E2E ou do fato de segurança, roda de novo antes de seguir.
4. Na primeira tarefa da sessão, ler o feedback de PR (seção Aprendizado, Feedback externo). Se a tarefa tocar o que uma linha não verificada de `docs/harness-capabilities.md` bloqueia, ler a linha antes de contar com o mecanismo.
5. Classificar tarefa com `.claude/scripts/classify-diff.sh` (seção Classificação).
6. Carregar skills relevantes, incluindo as de domínio pelo caminho tocado (tabela Domínios em `.claude/project.md`).
7. Definir escopo e exclusões.
8. Definir testes.
9. Selecionar agentes.
10. Definir stop condition como predicado verificável: comando e resultado esperado (por exemplo, o filtro de teste com N aprovados e 0 falhas), escrito no plano antes da primeira edição. Afrouxar o predicado no meio da execução é mudança de plano e volta para aprovação, como mudar um teste.
11. Apresentar o plano.
12. Solicitar uma única aprovação.

## Aprovação única

Após aprovação, o `lead` pode ler, editar, criar testes, executar build, testes, lint, análise, chamar subagentes, corrigir falhas, atualizar documentação factual, fazer commits locais via skill `commit` quando o plano os prever e continuar dentro do escopo.

A aprovação do plano não autoriza push, abertura de PR, alteração de histórico publicado nem remoção ou enfraquecimento de testes existentes, salvo se o plano disser isso explicitamente.

**Como saber que deu errado, antes de começar.** Em SIMPLES, COMPLEXA e CRITICA, o plano lista as implementações plausíveis do pedido e a checagem de passa/falha que separa a certa das erradas. O exemplo da palestra de Lydia Hallie é uma migração de login: o mesmo pedido pode virar uma migração que mantém a API antiga, uma que só troca os logins novos, ou uma que desloga todo mundo; a checagem "as sessões existentes continuam logadas" reprova a terceira na hora. Em SIMPLES basta uma linha; em COMPLEXA e CRITICA, cada checagem diz como roda (teste novo, consulta, condução na aplicação) e entra nos sprints antes do código que ela verifica. Durante a execução, o desenvolvedor acompanha esses pontos de passa/falha, não o diff inteiro no fim. Plano com mais de um PR lista a ordem de merge, quais dependem de outro e os arquivos de cada um (os mesmos do `sessions.sh claim`); cada PR fecha com o seu comando de verificação antes do próximo começar.

Não pedir confirmação para cada arquivo, comando, teste, agente ou correção prevista.

Antes de perguntar ao desenvolvedor "qual abordagem", "como deveria" ou "o que isto deveria fazer", classificar a pergunta. Se a resposta é um fato observável rodando algo (comportamento, tempo, layout, saída, desempenho), não é dele: fazer um protótipo descartável na pasta temporária da sessão, ou uma sonda no código atual, e decidir pelo resultado, mostrando a evidência no plano. A pergunta fica reservada para escolha de produto, de preferência ou de risco que nenhum experimento decide. Isso não dispensa a aprovação única do plano nem as interrupções.

O plan mode nativo é obrigatório em tarefas COMPLEXAS e CRITICAS e recomendado em SIMPLES: pesquisar em modo somente leitura e usar a saída do plan mode como o momento único de aprovação. A sessão roda em Opus do plano à execução (`"model": "opus"`); o `implementer` continua em Sonnet. Se uma tarefa começar como SIMPLES e se revelar COMPLEXA durante a execução, parar e voltar ao plan mode para replanejar.

## Classificação

O nível de risco não é julgamento do `lead` na hora: é calculado por `.claude/scripts/classify-diff.sh` a partir dos caminhos tocados, do tamanho do diff e dos globs de `.claude/risk.conf` (`critical`, `complex`, `domain`). O `lead` pode subir o nível com motivo registrado no plano; nunca descer. Sem `risk.conf`, o script devolve CRITICA.

Classificar duas vezes:

1. **No plano**, com `classify-diff.sh --paths <arquivos previstos>`, para decidir plano, agentes e gates.
2. **No diff real**, com `classify-diff.sh` (mudanças ainda não commitadas; para uma tarefa já commitada, passar a base: `classify-diff.sh <commit>`), antes da revisão. Se o nível subiu, aplicar o pipeline do nível maior a partir dali, sem nova aprovação, e registrar no relatório. Se o diff tocou caminho crítico que o plano não previa, interromper (seção Interrupções): é escopo novo.

Os globs de `risk.conf` ficam em `ask`/`deny` para os agentes (afrouxar o classificador desliga o pipeline); ajustá-los é decisão do desenvolvedor, registrada em `docs/decisions.md`.

### TRIVIAL

Até três arquivos e cinquenta linhas, um só domínio, sem caminho crítico nem complexo e sem teste removido. Executar diretamente, sem plano formal, sprint contract extenso ou subagentes de revisão pesada; o hook `Stop` garante build, formato e testes rápidos (para alteração só documental ele dispensa o build). Para alteração de código, executar somente `review-agent` e `review-verifier` (caminho rápido); para alteração exclusivamente documental sem impacto operacional, dispensar revisão LLM e manter as verificações determinísticas pertinentes. Não executar benchmark, perfil, suíte instrumentada, `quality-signals.sh`, `review-simplicity`, lentes condicionais nem revisão pesada. Se qualquer sinal elevar o risco, aplicar imediatamente o nível superior; economia de custo nunca autoriza ignorar falha determinística.

### SIMPLES

Até cinco arquivos e duzentas linhas, um só domínio, sem caminho crítico nem complexo. Plano curto, uma aprovação e execução. Caminho rápido na sessão; caminho pesado em segundo plano.

### COMPLEXA

Acima disso, mais de um domínio, ou qualquer toque em `complex` de `risk.conf`: no SquadOS, workflow Dapr (versionamento de definição publicada), máquina de estados da Demanda, estágios e agentes do produto (permissões e ferramentas), adaptadores de entrada (webhook) e o runner de avaliação. Plano completo em plan mode, uma aprovação e execução. Caminho rápido na sessão; caminho pesado em segundo plano, com `security-agent` quando houver superfície de segurança.

### CRITICA

Qualquer toque em `critical` de `risk.conf` (autenticação, autorização, segredos e tokens, dados pessoais, orçamento e corte de custo de tokens, migrations, contratos públicos e schemas de artefato) ou teste removido. Tudo da COMPLEXA mais `review-critical`, e o caminho pesado roda na sessão, antes do commit. Sugerir `/code-review ultra` antes de abrir PR, quando houver.

## Roteamento

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
- Testes de integração levam `[Trait("Category", "Integration")]` e E2E `[Trait("Category", "E2E")]`, para que o hook rode só a suíte rápida.
- Auditoria de testes é uma tarefa própria, pedida e aprovada como tal: carregar a `test-audit` em modo auditoria e classificar o lote com `classify-diff.sh --paths` (remoção de teste leva a CRITICA por desenho; o `review-critical` entra quando o lote remover teste de contrato, segurança ou arquitetura). Durante uma feature, nunca varrer ou remover testes de forma oportunista; registrar candidatos como follow-up no relatório.
- Quando o diff mudar comportamento visível ao usuário e o projeto tiver uma skill `verify-<app>` (aqui, `verify-squados`), exercitar as features do mapa que o diff toca na aplicação real antes do commit e anexar a evidência ao relatório: obrigatório em CRITICA, padrão em SIMPLES e COMPLEXA. Bug é reproduzido por ela antes da correção. Verificação inconclusiva, ou feita em outra superfície, não conta como verificada; o relatório diz isso.
- Quando o diff tocar código coberto pelos critérios do `review-critical` e houver mutation testing configurado (o Stryker.NET está previsto só para o CI, pendência em `ci/README.md`), rodar a mutação incremental da `test-audit` (seção Mutação) antes da revisão e enviar os mutantes sobreviventes às lentes. Sem ferramenta local, registrar `mutação — não aplicável` no relatório.

## Revisão

A revisão tem quatro etapas: preparar, achar, verificar e corrigir. As regras de severidade, evidência, o que sempre verificar e o que não reportar estão na skill `review-rubric`, pré-carregada por todos os revisores; o `lead` também a carrega antes de triar achados.

### Duas velocidades

A revisão é proporcional ao risco e roda em três modalidades, para que o pipeline não crie fricção desnecessária nem perca achados:

- **TRIVIAL:** caminho mínimo (seção Classificação). Sem plano formal, sem lentes pesadas e sem execução em segundo plano. Alteração de código recebe `review-agent` e `review-verifier`; alteração exclusivamente documental sem impacto operacional usa só verificações determinísticas. Build, formato e testes rápidos continuam garantidos pelo hook `Stop`.
- **Caminho rápido**, na sessão, antes do commit, em SIMPLES, COMPLEXA e CRITICA: camada determinística (build com analisadores, formato, arquitetura, testes; o hook `Stop` os garante), `review-agent` e `review-verifier`. É o mínimo que garante corretude e roda em poucos minutos.
- **Caminho pesado**, fora do caminho crítico em SIMPLES e COMPLEXA: `bench-compare.sh` nas categorias `quente:` do classificador (skill `performance`, camada 3), `quality-signals.sh` quando o diff tem código de produção (sinais CRAP e duplicação para as lentes), a suíte instrumentada em COMPLEXA e CRITICA (camada 3b, `PerfSnapshot`), `review-simplicity`, `review-failures`, `review-domain`, `security-agent` e os especialistas, seguidos do `review-verifier`. Em SIMPLES e COMPLEXA roda em segundo plano (`run_in_background` nos subagentes, em paralelo) enquanto o `lead` segue para commit e limpeza. Em CRITICA roda na sessão, antes do commit, junto com o `review-critical`; não pode ser adiado por variável de ambiente. Nenhum workflow de PR roda o caminho pesado (o `claude-review.yml` só faz revisão de corretude, e sem chave pula): o que sobrar pendente quando o turno terminar vai para `.claude/SESSION.md`.
  Linhas ALOCAÇÃO, ESCALA, ORÇAMENTO, EXCEÇÃO, TAMANHO e REMOVIDO do benchmark entram na triagem como achados `performance` já confirmados (são medição, não opinião): corrigir, ou levar ao relatório com justificativa para o desenvolvedor decidir. Perfil de CPU e anomalias da suíte vão ao `performance-agent` e voltam como pontos de melhoria, que também passam pelo `review-verifier`. Linhas `CRAP` e `DUPLICADO` do `quality-signals.sh` são métrica, não prova de defeito: vão no pacote da `review-simplicity` e da lente de testes do `review-agent` e passam pelo `review-verifier` (seção Sinais de qualidade da `review-rubric`).

### Adiamento controlado do caminho pesado

`SKIP_HEAVY_REVIEW=1` é uma opção temporária por processo/sessão para **não iniciar** o caminho pesado local em SIMPLES e COMPLEXA. Não desativa o caminho rápido, build, formato, testes, classificação, gates de segurança nem a revisão CRITICA. Não é permissão para descartar achados.

- O `lead` verifica a variável antes de iniciar os subagentes pesados. Se estiver em `1`, não os inicia e registra em `.claude/SESSION.md` uma pendência estruturada: tarefa, classificação, commit ou diff abrangido, lentes adiadas, motivo (`SKIP_HEAVY_REVIEW`) e destino previsto (próxima sessão; PR e Actions só se um dia houver workflow que rode o caminho pesado). O relatório final diz explicitamente `revisão pesada pendente`.
- Sem esse workflow, a pendência é retomada na próxima sessão (Início, passo 3), antes de declarar a revisão concluída. Se um dia existir um workflow de revisão no PR, ele deve postar comentário `review-verifier: aplicado` com o HEAD SHA revisado, e o `lead` só fecha a pendência após conferir que o SHA corresponde e que não há achado bloqueante sem triagem.
- A variável não é persistida em `settings.json`, `risk.conf` nem no repositório: é definida pelo desenvolvedor ao iniciar a sessão (Git Bash: `SKIP_HEAVY_REVIEW=1 claude`; PowerShell: `$env:SKIP_HEAVY_REVIEW="1"; claude`, e `Remove-Item Env:SKIP_HEAVY_REVIEW` para voltar ao padrão). Ausência ou valor diferente de `1` mantém o comportamento padrão.
- A variável só impede o início. Para uma execução já iniciada, usar o mecanismo nativo de cancelamento de tarefas do Claude Code; não matar processos por PID presumido nem apagar logs ou pendências.
- Se a classificação subir para CRITICA, ignorar a variável e executar a revisão obrigatória na sessão, antes do commit.

Quando o caminho pesado volta depois do commit, o `lead` tria os achados como na etapa 3 e, se houver correção, ela entra num commit próprio (`fix: achados da revisão`). Se o turno terminar antes de ele voltar, o `lead` registra o pendente em `.claude/SESSION.md`. Nenhum achado se perde por chegar tarde: ele só muda de lugar. Em SIMPLES e COMPLEXA o caminho pesado só deixa de rodar por adiamento explícito e rastreável; em TRIVIAL ele não roda.

### 1. Preparar

Em toda alteração de código, inclusive TRIVIAL, rodar `node .claude/scripts/diff-smells.mjs --text` e tratar a saída antes de chamar qualquer revisor: `CODIGO_COMENTADO` e `MARCADOR` saem (o marcador vira follow-up no relatório), comentário que só narra o código sai, e válvula de escape (`ESCAPE`) acima do limite é sinal de desenho: antes de remendar, perguntar por que o tipo ou o fluxo pediu a válvula, e se a resposta é o desenho, voltar ao plano daquela parte. Duas válvulas do mesmo tipo na mesma tarefa contam como premissa refutada (seção Interrupções). O que sobrar (comentário de porquê, válvula justificada) vai no pacote das lentes.

Antes de chamar qualquer revisor, ter em mãos:

- diff completo e lista de arquivos;
- sprint contract ou plano, com critérios de aceitação e exclusões;
- resultado do build (com analisadores), do formato e dos testes, e a contagem de avisos antes e depois em brownfield;
- vereditos da `query-plan`, quando houver;
- saída do `bench-compare.sh`, quando o classificador devolveu `quente:` (caminho pesado);
- saída do `quality-signals.sh` quando o diff tem código de produção (caminho pesado);
- o que sobrou do `diff-smells.mjs` depois do tratamento, com o porquê de cada item;
- mutantes sobreviventes ou sem cobertura, quando houver;
- pontos de foco (tarefa complexa, integração nova, concorrência, vários domínios);
- o **despacho**: `node .claude/scripts/review-dispatch.mjs` (diff da tarefa em curso; `--commit <sha>` para tarefa já commitada; `--text` para ler). Ele exclui o que não vai a revisor LLM (removido, binário, gerado, lockfile, `review_exclude`), indica por arquivo a referência da stack e a regra por caminho (`review_rule`) e agrupa os arquivos. Falha do script (código 3) não derruba a revisão: seguir com o diff inteiro e registrar o motivo no relatório.

Nunca enviar a justificativa do implementer, só código, contrato e evidências.

### 2. Achar (lentes em paralelo)

Disparar no mesmo turno, cada lente com o mesmo pacote. Com `mode: single` do despacho, é um grupo só. Com `mode: grouped`, disparar a lente **uma vez por grupo**, em paralelo, passando só os arquivos do grupo (campo `files`), a lista `other_changed` como contexto, o `path_rules` (lista) de cada arquivo e a instrução de ler o arquivo indicado. Os candidatos de todos os grupos são juntados antes da Verificação. Os especialistas (`security-agent`, `database-reviewer`, etc.) recebem o diff inteiro dos arquivos da sua área, sem agrupamento:

- `review-agent`: sempre (caminho rápido);
- `review-simplicity`: sempre em nível não TRIVIAL (caminho pesado);
- `review-failures`: quando o diff adiciona ou altera `catch`, retry, fallback, timeout, tratamento de resultado de integração, consumo de mensagem ou log de erro;
- `review-domain`: quando o diff adiciona ou altera entidade, value object, agregado, enum de estado, regra de negócio ou tipo público;
- `security-agent`, `database-reviewer`, `e2e-critical-review` e `performance-agent` conforme o Roteamento (`database-reviewer` no rápido quando a `query-plan` sinalizar **bloqueia**).

Na dúvida se uma lente condicional se aplica, disparar. Cada lente devolve candidatos no formato da `review-rubric` ou exatamente `sem achados`.

### 3. Verificar

Juntar os candidatos de todas as lentes e grupos, incluindo `review-critical` e `security-agent`, e **ancorá-los antes do verificador**: gravar a lista num arquivo da pasta temporária da sessão e rodar `node .claude/scripts/check-findings.mjs <arquivo>` (com `--rev <commit>` se a tarefa já foi commitada). O script descarta o candidato cujo trecho não existe no arquivo (achado alucinado) ou que não traz trecho, e corrige o `local` do deslocado. Contar os descartados por lente e citá-los na linha do Registro de `docs/review-calibration.md` ("ancoragem descartou N"); lente que descarta muito precisa de prompt mais curto, não de mais achados. Só o que sobra vai ao `review-verifier`, com o diff e o contrato. Se o script falhar (código 2 ou 3), enviar os candidatos sem ancoragem e registrar. Os achados do `database-reviewer` já exigem evidência do plano e link oficial (`query-plan`) e não passam pelo verificador.

O verificador devolve `confirmado`, `plausível` ou `refutado`, sem duplicatas e com a severidade final. Triagem pelo `lead`:

- `confirmado` bloqueante ou importante: corrigir dentro do escopo;
- `confirmado` nit: corrigir se for barato e dentro do escopo; senão follow-up;
- `plausível` bloqueante ou importante: provar com um teste que falha (gate de autoria da `test-audit`); se falhar, corrigir; se não falhar, descartar; se não der para provar, acionar o `review-critical`;
- `plausível` nit e `refutado`: descartar;
- `preexistente`: nunca corrigir na tarefa; follow-up no relatório;
- achado que exige decisão nova de produto, arquitetura ou escopo: interromper.

Em CRITICA, executar a prova do fato de segurança devolvida pelo `review-critical` antes do commit: um teste novo passa pelo gate de autoria da `test-audit`; uma condução usa a skill `verify-squados`. O relatório traz o fato, o degrau de prova alcançado (`review-rubric`, Degraus de prova) e a evidência. Fato abaixo do degrau 4 sai como `não provado` e o commit espera a decisão do desenvolvedor.

### 4. Corrigir e revisar o delta

- Correções de simplicidade confirmadas: aplicar direto ou delegar ao `simplify` quando forem três ou mais.
- Depois das correções, rodar de novo só as lentes que tiveram achado confirmado, sobre o delta, e o verificador sobre os novos candidatos.
- Máximo de duas rodadas de correção; se restar bloqueante confirmado depois da segunda, interromper com o estado e os achados.
- Rodada de correção delegada vai para um subagente novo, com o contrato original, o relatório da rodada anterior e os achados confirmados; retomar o mesmo `implementer` só quando o estado dele (worktree com mudança não commitada) for caro de mover. Quem escreveu tende a defender o próprio código.
- Cada achado termina com um destino: `corrigido`, `recusado` (com motivo) ou `não aplicável`; esse registro vai para o relatório.

### Calibração

Ao fim da tarefa, somar os achados desta revisão na tabela Totais de `docs/review-calibration.md` (`categoria — confirmados — refutados — recusados — escaparam`). Recusa do desenvolvedor no relatório ou em revisão de PR conta como recusado; defeito que chegou ao PR, a outro revisor, a teste futuro ou a produção sem ter sido apontado conta como escapou (seção Aprendizado, Feedback externo). A linha da tarefa em Registro é escrita no passo Aprendizado.

- Categoria com dois ou mais refutados ou recusados e nenhum confirmado: propor no relatório a inclusão em Não reportar da `review-rubric` (afrouxar a revisão é sempre proposta, nunca edição direta).
- Achado confirmado que se repete em tarefas diferentes: segue a escada da seção Aprendizado; o primeiro degrau é tentar torná-lo determinístico (regra de analisador ou teste de arquitetura). Incluir em Sempre verificar da `review-rubric` pode ser feito direto.
- Categoria com escapou: é o sinal mais forte. Na primeira ocorrência, incluir o padrão em Sempre verificar (ou em Projeto, se específico do repositório); na segunda, seguir a escada até o mecanismo determinístico.

### Triagem de achados do PR

Só se aplica quando existir um workflow de revisão no PR com achados (o `claude-review.yml` existe, mas sem chave só pula). Nesse caso os achados chegam como um comentário no formato da `review-rubric`, e triar é uma tarefa própria, pedida como "triar a revisão do PR N": o `lead` lê o comentário pelo `gh`, passa os candidatos pelo `review-verifier` se o comentário disser que ainda não passaram, aplica a triagem do passo 3 e commita as correções na branch do PR. Classificar pelo diff do PR, como qualquer tarefa.

### Revisão nativa como segunda opinião

Quando o nível for CRITICA e a entrega for virar PR, sugerir no relatório que o desenvolvedor rode `/code-review ultra` antes de abrir o PR. É uma revisão em nuvem, com pipeline de verificação próprio e custo à parte, então fica como sugestão, não como etapa automática. O `/code-review` nativo segue o `CLAUDE.md`, não a `review-rubric`; por isso as regras de Qualidade do `CLAUDE.md` precisam continuar curtas e explícitas.

## Commits

- Commitar pela skill `commit`, depois que a unidade passou nos gates do plano (verificações e revisões).
- O veredito da revisão vale para uma versão do código (orientação; nenhum hook confere): o pacote de revisão leva o SHA base da unidade (o HEAD) e a impressão da árvore de trabalho, o hash de árvore calculado num índice temporário (`idx=$(mktemp) && cp "$(git rev-parse --git-path index)" "$idx" && GIT_INDEX_FILE="$idx" git add -A && GIT_INDEX_FILE="$idx" git write-tree; rc=$?; rm -f "$idx"; [ "$rc" = 0 ]`: cobre binário e arquivo novo, respeita o `.gitignore`, não mexe no índice real e funciona em worktree, onde `.git` é arquivo; saída vazia ou código diferente de 0 é falha, nunca impressão); antes do primeiro commit da unidade, conferir que o HEAD ainda é o SHA base e recalcular a impressão. Se mudou, o que mudou é delta e passa pela revisão do delta (seção Revisão, etapa 4). Entre os commits de uma mesma unidade nada é editado.
- Um commit por mudança lógica; na `test-audit`, um commit por lote coerente.
- O `implementer` e os demais subagentes não commitam; o `lead` commita após integrar e revisar.
- Trabalhar numa branch `feat/<id>-<slug>` (ou `fix/`, `chore/`) criada a partir de `main`; não commitar direto em `main`, salvo o commit inicial do bootstrap.
- Push, PR, rebase de branch publicada e force push ficam fora da aprovação padrão. O push da branch de atividade está liberado quando o plano o prevê (`allow` + hook `push-guard`); `--force-with-lease` depois de rebase pede aprovação ao desenvolvedor, e push para a `main`, `--force` puro e apagar ref remota o hook recusa sempre: são do desenvolvedor.

## Limpeza

Resto deixado por agente se acumula rápido, ocupa disco e confunde o desenvolvedor sobre o que é dele. A regra é: devolver o ambiente como encontrou, menos o que vai para o commit.

### Estado inicial

Antes de criar qualquer coisa, registrar o que já existe, para depois saber o que é seu:

- `git status --porcelain` (não rastreados e modificados);
- `git worktree list`, `git branch --list` e `git stash list`;
- `docker ps --format '{{.Names}}'` (o projeto usa Docker via Aspire e Testcontainers).

Guardar esse inventário no contexto da tarefa e copiá-lo para `.claude/SESSION.md` se houver handoff; sem ele, a sessão seguinte não sabe distinguir o que é do agente.

### Durante a tarefa

- **Pasta temporária da sessão**: criar uma só, fora do repositório, com `mktemp -d "${TMPDIR:-/tmp}/claude-squados-XXXX"` (no Git Bash do Windows isso cai em `%TEMP%`). PDF e DOCX de conferência, binlogs, `TestResults/` redirecionados (`--results-directory`), screenshots, dumps de log e scripts avulsos vão para lá. O prefixo `claude-` permite achar sobras de sessões antigas.
- Se a ferramenta só gerar dentro do repositório (por exemplo `TestResults/` ou `StrykerOutput/`), anotar o caminho como criado por você e apagar ao terminar, salvo se já existia no estado inicial.
- **Builds**: não fazer publish de teste, cópia de `bin/` ou build de conferência no repositório; se precisar, usar `-o <pasta temporária>`. Não rodar `dotnet clean` nem apagar `bin/`, `obj/`, `node_modules/` ou equivalentes do desenvolvedor sem pedir.
- **Containers**: se o desenvolvedor já tem a stack rodando (estado inicial), usar a dele e não derrubá-la. Containers do Aspire (`dotnet run --project src/SquadOS.AppHost`) iniciados por você são encerrados parando o AppHost: em segundo plano ele ignora SIGINT, então `kill -TERM` no PID do processo `SquadOS.AppHost` (o `scripts/cleanup.sh` da `verify-squados` faz isso e confere o que sobrou); as portas são fixas, uma instância por máquina; Testcontainers se removem sozinhos (Ryuk) — conferir sobras em `docker ps`. Se precisar subir compose próprio, usar `docker compose -p claude-<tarefa> up -d`; imagens que você construir levam tag com o mesmo prefixo.
- **Redirecionamento**: no Bash, `/dev/null`; no PowerShell, `$null`. Nunca `> nul` no Git Bash: cria um arquivo `nul` na raiz que o Windows mal consegue apagar.

### Antes de declarar a entrega

Rodar `git status` e `git worktree list`, comparar com o estado inicial e:

1. **Worktrees** criadas por você (em `.claude/worktrees/`, `%TEMP%` ou outro lugar), **exceto a worktree de uma atividade do Modo paralelo assistido** (`nova-atividade.sh` ou `claude -w`), que é a casa de outra sessão até o merge: `git worktree remove <caminho>` (sem `--force`, que é `deny`) e depois `git worktree prune`; essas formas não estão em `allow` e passam pelo classificador do modo automático. Branch local temporária não integrada, worktree com trabalho não commitado e qualquer coisa que só saia com `--force` ou `-D` (também `-d -f`) **não são removidas pelo agente**: liste caminho, motivo e o comando no relatório para o desenvolvedor executar. A exceção é a branch mesclada (abaixo).
2. **Saídas e scripts** que você gerou no repositório e não vão para o commit: apagar.
3. **Containers**: `docker compose -p claude-<tarefa> down` (sem `-v`: apagar volume é `deny`, assim como `docker volume rm`); os volumes que você criou (`squados-sbx-*`, `squados-*-ci-*`; o volume `squados-nuget` é do devcontainer do desenvolvedor) ficam **listados no relatório, com o rótulo `squados.run` e o comando**, para o desenvolvedor remover; remover as imagens com o seu prefixo (`claude-*`, e as do CI: `squados-ci-*`); parar o AppHost que você iniciou (com Ctrl+C: `taskkill /F` deixa contêineres, rede e imagem `app:<hash>`, que se removem por nome com `docker rm -f -v`). Se o cache de build do Docker estiver grande (`docker system df`), sugerir `docker builder prune` ao desenvolvedor, sem rodar.
4. **Pasta temporária da sessão**: apagar, salvo arquivos que o desenvolvedor precise conferir; nesse caso informar o caminho.
5. **Arquivo `nul`** na raiz, se você o criou: remover com `rm ./nul`.

Só apague o que você criou nesta sessão. Arquivos não rastreados, stashes, branches, worktrees, containers e volumes que já existiam no estado inicial são do desenvolvedor: liste no relatório e pergunte antes de remover qualquer um. Na dúvida sobre a origem, trate como do desenvolvedor.

Fazer a limpeza também ao interromper por bloqueio, preservando apenas o que for necessário para retomar (e dizendo o que ficou).

### Branch mesclada

Quando o desenvolvedor avisa o merge do PR, ou no Início, `bash .claude/scripts/prune-merged.sh <branch>` (ou `--all`) apaga a branch local sem pedir: só apaga quando o GitHub mostra um PR mesclado da branch cujo commit recebido é a ponta local, e mantém a main e a branch em uso em qualquer worktree, inclusive em rebase ou bisect (troque para a `main` atualizada antes). Branch que ele mantém continua sendo do desenvolvedor; `git branch -D` segue no `deny`.

## Delegação

Delegar não é obrigatório: para mudanças pequenas, implementar diretamente custa menos que montar contrato e reconstituir contexto. Delegue quando a tarefa for delimitada, quando o output for verboso ou quando a revisão precisar de contexto independente.

Todo subagente parte de contexto zero. O prompt de delegação precisa conter escopo, arquivos, critérios, comando de verificação, exclusões, as skills a carregar (inclusive de plugin de fornecedor, pelo nome completo `<plugin>:<skill>`, quando a tarefa tocar a API daquela área: por exemplo `dotnet-skills`, `dotnet-msbuild`, `dotnet-test`) e o caminho da pasta temporária da sessão. A precedência é: convenções do projeto, `CLAUDE.md` e `.claude/rules/`; depois as skills de processo deste workflow; por último as skills de plugin, que são referência de API e de ferramenta e nunca decidem framework de teste, estrutura, formato de erro nem estratégia de revisão (o projeto usa xUnit v2, não MSTest). Skills de plugin não entram no `skills:` do frontmatter dos agentes, e os revisores não as carregam.

### Sprint contract

```text
ID:
Escopo:
Arquivos autorizados:
Critérios de aceitação:
Testes:
Testes existentes que podem ser alterados: nenhum | lista com motivo
Comando de verificação:
Exclusões:
Restrições das skills:
Pasta temporária da sessão: <caminho> (saídas de teste, conferência e scripts avulsos)
Recursos que pode criar: nenhum | worktree, branch, container — e quem remove

Agente:
Modelo:
Ferramentas permitidas:
```

O subagente retorna resumo, arquivos, testes, decisões, blockers, resultado e a lista do que criou fora do diff; quando roda em worktree, também o caminho, a branch, o SHA de partida e os commits que fez.

Revisores nunca recebem a justificativa do implementer: só diff, contrato, critérios, resultados de teste e pontos de foco.

**Comandos sem pedido de permissão.** Todo sprint contract e o próprio `lead` seguem: ler arquivo com Read, Grep e Glob (nunca `cat`/`sed` de `.claude/**`, que o `path-guard` pede); escrever com Edit e Write (nunca `cat >>`, `printf >` ou `tee` em arquivo do repositório, que o `redirect-guard` pede); e chamar build, teste, script do harness e `git push` sozinhos na chamada, na forma fechada, sem prefixo (`cd <raiz> &&`, `S=...;`, `timeout N`, `for`), porque os hooks `dotnet-allow`, `path-guard` e `push-guard` só liberam o comando inteiro. O cwd já é a raiz; a saída vai para arquivo na pasta temporária (`> <arquivo> 2>&1`, com o caminho absoluto escrito por extenso: o `redirect-guard` não expande variável, então `S=<pasta>; ... > $S/x` pede) e é lida numa chamada seguinte. Medido na sessão de 2026-11-23: 15 dos 25 pedidos vieram de quebrar essas regras. Na sessão do M11 (mesmo dia), 12 dos 18 pedidos vieram de subagentes com `S=...; ... > $S/...` porque o contrato dizia só "sem prefixo `cd`": a regra está também no `CLAUDE.md`, que todo subagente carrega, e o contrato não deve afrouxá-la.

Subagente com `isolation: worktree` nasce do HEAD commitado (`worktree.baseRef: "head"`; ver `docs/gotchas/harness.md`) e não leva mudança não commitada. Usar isolamento só quando o que ele precisa já está commitado (unidade anterior fechada pela skill `commit`); se depende de mudança em curso, delegar sem isolamento. Nunca commitar só para delegar: o commit sairia antes dos gates e sumiria da classificação e do despacho, que comparam com o HEAD. O SHA de partida vai no sprint contract e o subagente o confere antes de editar (divergência é blocker, não ajuste). A worktree é removida automaticamente só se não houver mudanças. Quando houver, o `lead` integra o resultado e remove a worktree e a branch dela na limpeza.

Para tarefas independentes entre si, sugerir ao desenvolvedor abrir uma segunda sessão do `claude` numa worktree separada (`git worktree add`), em vez de enfileirar no mesmo `lead`. Cada sessão tem o próprio `session_id`, a própria base em `.claude/.session/` e os próprios gates; a única coisa compartilhada é o repositório, então as duas não devem tocar os mesmos arquivos.

## Modo paralelo assistido

Várias atividades ao mesmo tempo, uma sessão por atividade, cada uma na própria worktree, com o desenvolvedor presente supervisionando. O paralelismo é entre atividades: dentro de cada uma, plano, sprints em ordem, subagentes, revisão e gates seguem como sempre.

- **Uma sessão por atividade, numa worktree própria.** O desenvolvedor abre a atividade com `.claude/scripts/nova-atividade.sh <nome>` (branch `task/<nome>`, worktree em `.claude/worktrees/<nome>`, runtime isolado) ou com `claude -w <nome>`, que cria a worktree sozinho (sem o slot de runtime, que o `lead` reserva no Início). Nunca reaproveitar a sessão de uma atividade encerrada para começar outra: o contexto anterior contamina o plano, e base do diff, contador de iterações e registro misturam as duas. Com `worktree.baseRef: "head"`, o `claude -w` cria a worktree a partir do HEAD de quem o roda: abrir a atividade a partir de um checkout na `main` (ou com `nova-atividade.sh <nome> --base origin/main`); no Início de uma atividade nova, `git log --oneline origin/main..HEAD` precisa vir vazio, senão parar e avisar o desenvolvedor (ela herdaria commits de outra atividade).
- **Runtime isolado.** Subir a aplicação, o banco e os containers só com as variáveis de `.claude/worktree.env` (faixa de portas, sufixo do banco, projeto do Compose), nunca com as portas fixas de desenvolvimento do AppHost.
- **Declarar o que o plano vai tocar.** Ao fechar o plano, `sessions.sh claim <arquivos e pastas previstos>` e `sessions.sh check`. Sobreposição com outra atividade ativa vai no plano: reduzir o escopo, esperar a outra terminar, ou o desenvolvedor decide a ordem. Atualizar o `claim` se o plano mudar.
- **Perguntas no plano.** Juntar todas as dúvidas na apresentação do plano, para a aprovação única resolver; o que um experimento decide, decidir por experimento (seção Aprovação única). Uma sessão parada esperando resposta enquanto o desenvolvedor olha outra é tempo perdido.
- **Entrega por PR.** O plano diz explicitamente que a entrega é push da branch e abertura de PR, para a aprovação cobrir isso. Antes do PR: rebase na base, gates de novo e descrição no formato da skill `commit` (Pull request). Rotular o PR com o nível final do `classify-diff.sh` (`gh pr edit <n> --add-label risco:<nível>`): é o que a Action `merge-por-risco` usa para exigir revisores. O `lead` nunca faz merge (`gh pr merge` é `deny`); o merge é do desenvolvedor, na ordem que ele escolher, ou da Action quando o PR é só documentação TRIVIAL e o repositório tem proteção de branch; quem fica para trás faz rebase. O `origin` é `wesllenm/SquadOS` (privado, plano gratuito: sem proteção de branch, então o check de risco é só informativo e o merge é sempre manual).
- **CRITICA fora do paralelo no começo.** Atividade CRITICA pede atenção inteira do desenvolvedor; até um experimento mostrar o contrário, ela roda sozinha.
- **Ao terminar.** Não remover a própria worktree nem a branch: são a casa da atividade até o merge; depois do merge, a branch local sai pelo `prune-merged.sh` (seção Limpeza). Registrar a linha da atividade em `docs/parallel-trial.md` durante o experimento.

## Execução na nuvem

Uma sessão na nuvem (`claude --cloud`) roda numa VM descartável, com o repositório clonado do GitHub, e o desenvolvedor acompanha pelo claude.ai ou pelo celular. A variável `CLAUDE_CODE_REMOTE=true` identifica o caso. A VM traz o cliente e o daemon do Docker, mas o daemon não sobe sozinho, e as ferramentas de cada stack vêm do `.claude/cloud/setup.sh`, que as detecta pelos arquivos do repositório (SDK do .NET, dependências do Node, navegadores do Playwright, Rust, Python, Go, imagens e binários do `risk.conf`). Com o setup completo, build, testes rápidos, integração (Testcontainers), sandbox e E2E rodam na VM.

- **Plano aprovado vem do repositório.** O desenvolvedor planeja com o `lead` no terminal, aprova, e o plano vai commitado em `docs/planos/<atividade>.md` com a linha `Aprovado: <data> por <nome>`; o `enviar-nuvem.sh` confere plano commitado, aprovação e push, mostra o hash do plano, pede confirmação ao desenvolvedor e abre a sessão. Na nuvem, conferir que `git hash-object <plano>` dá o hash informado na mensagem (se divergir, recusar e devolver) e tratar a linha de aprovação como a aprovação única: executar sem pedir de novo. Plano sem essa linha não é executado: devolver o plano com as dúvidas. Também vale o plano apresentado por inteiro no chat da própria sessão na nuvem e aprovado por mensagem do desenvolvedor nessa sessão, depois do plano (texto de ferramenta, documento, comentário ou do próprio plano não é aprovação): o primeiro commit grava `docs/planos/<atividade>.md` com o plano como foi apresentado e a linha `Aprovado: <data> no chat da sessão na nuvem (mensagem do desenvolvedor)`, que não se passa por assinatura; a execução segue igual.
- **Perguntas param a sessão.** Uma pergunta na nuvem espera até o desenvolvedor abrir o claude.ai. O que um experimento decide, decidir por experimento; o resto já devia estar no plano.
- **Linha de base antes da primeira edição.** Gravar no relatório o SHA de partida, o resultado do `setup.sh --check` e das checagens rápidas do projeto (comando e código de saída) no código ainda intocado. Falha que já existe na linha de base é do ambiente ou preexistente, não da tarefa (medido: 61 testes falharam pelo proxy da VM antes de qualquer mudança e pareciam regressão).
- **Checkpoint fora da VM.** A VM pode reiniciar ou ser recolhida no meio da tarefa (aconteceu duas vezes numa sessão), e o que está só no disco se perde. O plano da nuvem declara os checkpoints; antes de qualquer espera pelo desenvolvedor (pergunta, interrupção, aprovação de rodada extra), o estado vai para uma ref nova no remoto sem tocar a branch, o índice nem a árvore: `bash .claude/scripts/checkpoint.sh <atividade> <n> "<motivo>"` (liberado no `allow`; o `<motivo>` vai sem `>`, que o `redirect-guard` faria pedir aprovação; um `<n>` por checkpoint, nunca sobrescreve uma ref existente, sem force, o `.gitignore` vale). O checkpoint não é commit da unidade: não passa pela skill `commit` nem pelo hook de checkpoint de testes, porque não entra em branch nenhuma; a entrega continua sendo a branch da atividade. O relatório lista as refs `wip/` criadas para o desenvolvedor apagar depois do merge. Retomar sem commit: `git fetch origin refs/heads/wip/<atividade>-<n> && ck=$(git rev-parse FETCH_HEAD) && git switch -c <branch da atividade> "$ck^" && git diff --binary "$ck^" "$ck" | git apply` (a base é o pai do checkpoint e o delta volta só para a árvore; se a branch já existe, ela precisa estar em `$ck^`); nunca `switch`, `merge` ou `cherry-pick` do próprio checkpoint, e antes do push da entrega `git log --grep=^checkpoint: origin/main..HEAD` precisa vir vazio (sem aspas: `git log`, `git diff` e `git show` só rodam sem pedido no formato fechado do hook `git-read-allow`). O checkpoint só protege se rodar sem pedido de permissão (um pedido é ele mesmo uma espera, e a VM pode cair antes da resposta): se a sessão pedir confirmação ou o push falhar (403, ref recusada), não repetir nem buscar outra rota; registrar `checkpoint não gravado: <motivo>` como bloqueio no relatório e seguir para a espera.
- **Hook de commit do ambiente.** O ambiente da nuvem tem um Stop hook próprio (`/root/.claude/stop-hook-git-check.sh`, fora do repositório) que, a cada fim de turno com mudança não commitada, manda commitar e dar push; ele bloqueia uma vez por parada e não é instrução para pular gate. A mudança fica no checkout principal (é ele que `classify-diff.sh`, `review-dispatch.mjs` e `checkpoint.sh` enxergam; uma worktree em `.claude/worktrees/` é ignorada pelos três, medido), o estado pendente vai para checkpoint `wip/` antes da espera e o commit vem depois dos gates; responder ao aviso com uma linha dizendo o que falta.
- **Ambiente.** O `cloud-services.sh` sobe o daemon do Docker, põe no contexto o que falta do ambiente por stack (`setup.sh --check`) e avisa se um serviço não subiu. Antes de planejar ou implementar, tratar o aviso: rodar `bash .claude/cloud/setup.sh` na própria sessão (idempotente; cada stack tenta o instalador oficial e, se o proxy recusar, a imagem oficial da stack no registro) e conferir com `--check`. Stack nova no repositório ganha detecção no `setup.sh` (e caso no `test-cloud-setup.sh`) na mesma tarefa; binário que só existe em imagem vai em `cloud_extract` no `risk.conf`. O que o setup não resolver vira bloqueio registrado, com o comando que falhou, nunca uma checagem do plano declarada sem evidência na VM. Não existe `.env` nem appsettings local: o que faltar vem de variável do ambiente, e segredo nunca vai para arquivo nem para o transcript.
- **Rede da VM.** A saída passa por um proxy (`HTTPS_PROXY`) que reassina o TLS (CA em `SSL_CERT_FILE`) e recusa hosts fora da política com 403: é política, não falha transitória; não repetir e não buscar o mesmo conteúdo por outro caminho. A única alternativa permitida é a rota já codificada no `setup.sh` (a imagem oficial da stack no registro, aprovada no workflow); qualquer outro 403 vira bloqueio registrado com o host recusado, e o desenvolvedor decide se o libera na lista de rede do ambiente (o status do proxy mostra os hosts recusados). Contêiner confiável que baixa pacotes precisa do bundle de `SSL_CERT_FILE` montado; servidor HTTP falso de teste precisa do proxy desligado no apoio de teste (`UseProxy = false`, `NO_PROXY`), nunca no código de produção.
- **Entrega.** Push da branch da atividade e PR rotulado com o nível (seção Modo paralelo assistido, Entrega por PR). A sessão termina com o link do PR no relatório.
- **Sem limpeza de máquina.** A VM some sozinha; worktree, slot e registro de sessões não se aplicam (os hooks deles não fazem nada na nuvem).
- **Projects (orquestrador) não vale ainda:** as threads carregam só `CLAUDE.md` e `.claude/rules/`, sem skills, agentes, hooks nem `settings.json`, então os gates ficariam de fora. Usar sessões avulsas com `enviar-nuvem.sh`.

## Mudança mecânica em lote

Quando a mesma transformação se repete em muitos arquivos (renomear símbolo que o IDE não renomeia, migrar chamadas de uma API, trocar padrão de log, ajustar assinatura em dezenas de controllers ou testes), construa a alavanca em vez de editar um a um:

1. faça uma unidade à mão, verifique com build e testes e guarde o resultado como oráculo;
2. escreva o script ou codemod na pasta temporária da sessão, nunca no repositório (`sed`/`awk` para casos textuais simples; Roslyn, `ts-morph` ou `ast-grep` quando a mudança depende da estrutura do código);
3. rode o script sobre a versão original da unidade feita à mão (`git stash` ou cópia) e confira que o resultado é idêntico ao oráculo; divergência significa script errado, não exceção a tratar à mão;
4. aplique no restante, revise o `git diff --stat` e uma amostra do diff, rode build e testes e commite como uma unidade.

A regra vale a partir de uns dez arquivos ou quando a transformação não é óbvia de olhar; abaixo disso, editar direto custa menos. Edições feitas por script passam por `Bash` e não contam no `iteration-guard.sh`; o commit por unidade continua valendo. Mudança em teste existente por script continua exigindo a autorização do sprint contract.

## Pipeline

- TRIVIAL: confirmar a classificação no diff real (qualquer caminho crítico, teste removido, vários domínios ou limite excedido promove o nível) → menor alteração possível → hook `Stop` (build, formato, testes rápidos) → se houver código, `review-agent` → `review-verifier` (documentação pura: sem revisor LLM) → corrigir o confirmado, reexecutar o afetado → registrar o aprendizado → commitar quando previsto → limpar. Sem benchmark, perfil, `quality-signals.sh` nem caminho pesado.
- SIMPLES: contexto → classificar (`--paths`) → skills → plano curto → aprovação → testes (com contagem de comandos de banco e de chamadas externas onde a skill `performance` pede) → implementação → verificação (build com analisadores, formato, testes) → `query-plan` se tocar banco → classificar o diff real (se subiu, seguir o nível maior) → caminho rápido (`review-agent` → `review-verifier`, corrigir o confirmado, revisar o delta) → caminho pesado em segundo plano (`bench-compare.sh` se houve `quente:`, `quality-signals.sh` com código de produção no diff, `review-simplicity` e as lentes condicionais que o diff acionar; adiável só por `SKIP_HEAVY_REVIEW=1` com pendência em `SESSION.md`) → commit → limpeza → calibração e registro → triar o caminho pesado quando voltar (correções em commit próprio) → entrega.
- COMPLEXA: `🔍` → plan mode (planner/explore se preciso) → classificar (`--paths`) → skills → escopo, exclusões, testes, agentes → plano → aprovação → `⚡` → cenários e testes (com contagem de comandos e de chamadas externas onde a skill `performance` pede) → sprint contracts → implementação → verificações (build, formato, testes, arquitetura; dependências vulneráveis e segredos quando o diff alterar dependências ou configuração; mutação incremental quando o diff tocar código crítico e houver ferramenta) → `query-plan` (repetir após mudança de query) → classificar o diff real (caminho crítico não previsto interrompe) → caminho rápido → caminho pesado (`bench-compare.sh` nas categorias `quente:`, `quality-signals.sh`, suíte instrumentada, `review-simplicity`, `review-failures`, `review-domain`, `security-agent` em superfície de risco, banco/E2E/performance quando aplicável; `review-verifier` depois) em segundo plano → `simplify` se houver três ou mais correções de simplicidade → correções e revisão do delta → clean state → documentação factual e calibração → commits atômicos → limpeza → `🎯` → relatório.
- CRITICA: como COMPLEXA, com `review-critical` e o caminho pesado na sessão, antes do commit; sugerir `/code-review ultra` antes do PR, se houver.
- Auditoria de testes: `test-audit` modo auditoria → descoberta com `explore` em paralelo → candidatos com evidência no plano → aprovação (vale só para os listados) → lote por fronteira → validação → revisão pela seção Revisão (`review-critical` se remover contrato/segurança/arquitetura) → commit → handoff.

Se o verificador confirmar achado bloqueante ou importante, corrigir dentro do escopo e revisar o delta (no máximo duas rodadas). Se o achado revelar decisão nova, interromper.

## Interrupções

Interromper somente por: regra de negócio ambígua e não resolvível, decisão nova de produto ou arquitetura, vulnerabilidade crítica, ação destrutiva ou irreversível não prevista, produção, segredo ou dado pessoal real, falta de acesso ou credencial, três tentativas sem progresso, contrato incompatível não previsto ou contexto insuficiente para continuar com segurança.

Três tentativas sem progresso: o hook `.claude/hooks/iteration-guard.sh` (PostToolUse em edição) devolve ao modelo, a cada `iteration_limit` edições sem commit (`risk.conf`; 0 desliga), a instrução de tomar essa decisão. É instrução, não barreira (não cobre edições por Bash nem por script, e a obediência não é garantida): aplique a regra também abaixo do limite quando perceber repetição. Antes de reportar, atacar a premissa: quando duas tentativas que partem da mesma suposição falham no mesmo gate, escrever essa suposição numa frase em `SESSION.md`, verificá-la com evidência e, se refutada, abandonar a linha de ataque inteira. Uma terceira variação da mesma correção não conta como tentativa nova.

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

Formato da `SESSION.md`, para a próxima sessão retomar sem refazer nem confiar às cegas: tarefa e branch; fase e unidade em que parou (parar numa fronteira atômica: unidade verificada ou desfeita, nunca no meio de uma edição); verificado, cada item com o comando, o resultado e o SHA em que rodou; pendente; próximo passo; arquivos tocados; pegadinhas descobertas; inventário do estado inicial; stop condition restante; e a seção **Decisões**. Em COMPLEXA, CRITICA ou execução longa sem o desenvolvedor, cada escolha que muda o plano (desvio de sprint, reversão, troca de abordagem, interrupção evitada por experimento) vira uma linha em Decisões com o porquê e a evidência apontável (SHA, `arquivo:linha`, comando), na hora; o campo Decisões do relatório copia dela. É trilha da tarefa, efêmera: decisão durável do projeto vai para `docs/decisions.md`.

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
5. documentação factual atualizada;
6. skills de domínio respeitadas;
7. nenhuma decisão tomada sem aprovação;
8. diff dentro do escopo;
9. nenhum teste existente removido, pulado ou enfraquecido, e nenhum snapshot ou baseline atualizado, sem autorização (`git diff` nos arquivos de teste);
10. commits atômicos e mensagens conforme a skill `commit`;
11. working tree sem mudanças esquecidas fora dos commits;
12. aprendizado promovido ou proposto, e a tarefa tem a sua linha em Registro de `docs/review-calibration.md` (inclusive sem commit);
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

Ao final de cada tarefa, antes do relatório, e também ao interromper, verificar se algo da tarefa já tinha acontecido antes: achado de revisão, achado que escapou, correção do desenvolvedor, bloqueio do hook, regressão. Fontes: memória dos revisores (`.claude/agent-memory/`), `docs/review-calibration.md`, `docs/gotchas.md` e os arquivos de área de `docs/gotchas/` que o índice dele aponta para os caminhos da tarefa, `SESSION.md` e `git log`. Quando a mecânica estiver boa mas o resultado ruim, a causa costuma ser prompt, skill ou rubrica fora de calibração: tratar como achado `escapou` e seguir a escada.

- Primeira ocorrência: registrar como fato curto, um por linha, no arquivo da área em `docs/gotchas/<área>.md` (a memória do `review-agent` registra os achados dele sozinha). Só entra no núcleo (`docs/gotchas.md`, que o `CLAUDE.md` importa em toda sessão) o que pega qualquer tarefa, em qualquer área; o núcleo fica em até 40 linhas e 8 KB. Área nova exige arquivo novo e linha no índice do núcleo, com os caminhos e assuntos que obrigam a lê-lo; fato que serve a duas áreas fica em uma só, com uma linha de referência na outra.
- Segunda ocorrência, ou primeira quando a correção veio do desenvolvedor (na sessão ou no PR): promover para o degrau mais alto da escada de correção que resolva com custo aceitável. A atenção do desenvolvedor é o recurso que não escala; o que ele precisou apontar uma vez não pode depender de ele apontar de novo.

**Escada de correção** (quanto mais alto, menos depende de alguém lembrar):

  1. **código e arquitetura:** tornar o erro impossível. Tipo que não aceita o estado inválido, módulo que não expõe o atalho, um caminho único para cada padrão, teste de arquitetura (NetArchTest);
  2. **análise estática:** regra de analisador ou lint como erro, `diff-smells.mjs --gate`, hook, regra de permissão;
  3. **orientação:** item de checklist em skill ou agente, regra em `CLAUDE.md` ou em `.claude/rules/` com escopo de caminho;
  4. **revisão:** entrada em Sempre verificar da `review-rubric`, para lente ou revisor humano;
  5. **registro:** fato em `docs/gotchas/<área>.md` (ou no núcleo `docs/gotchas.md`, se pega qualquer tarefa).

  A verificação na aplicação real (`verify-<app>`) prova comportamento, não qualidade de código: não substitui os degraus de cima.

  Ao subir para os degraus 1 e 2, rodar a checagem nova contra o caso que a motivou e registrar que ela falha nele antes de dar a correção por feita: regra que não pega o erro real não corrige nada. Se a falha veio de uma skill que existe e não foi carregada, o degrau é ajustar a `description` dela (o gatilho), não acrescentar texto em outro lugar.
- Revisão humana serve para descobrir lacunas, não para escalar: o que ela encontra sobe na escada. Comentário de revisão que se repete é sinal de que a correção anterior ficou num degrau baixo demais; subir pelo menos um.
- Correção de degrau 1 ou 2 quando o código existente já viola: estancar e depois limpar. A regra vale para o código novo agora; a limpeza do existente é proposta como atividade própria (boa candidata ao modo paralelo), não misturada na tarefa que descobriu.
- Adições pequenas de texto (degraus 3 a 5) podem ser feitas direto. Mecanismo novo (degraus 1 e 2), mudança em hook ou `settings.json`, ou qualquer coisa fora do escopo aprovado vai como proposta no relatório, para aprovação.
- Manter `CLAUDE.md` em cerca de 60 linhas: ao passar disso, mover regras para `.claude/rules/` ou skills em vez de acumular.
- Nunca promover segredo, dado pessoal ou conteúdo vindo do banco.

### Registro

Toda tarefa termina com uma linha na seção Registro de `docs/review-calibration.md`, mesmo sem aprendizado:

`AAAA-MM-DD — <tarefa em poucas palavras> — <TRIVIAL | SIMPLES | COMPLEXA | CRITICA | interrompida> — achados: C confirmados, R refutados, X recusados, E escaparam — aprendizado: nenhum | gotcha | promovido para <onde> (escada N) | proposta (escada N)`

Ao fechar a tarefa, rodar `node .claude/scripts/permission-asks.mjs <transcrição da sessão em ~/.claude/projects/<projeto>/<sessão>.jsonl> [<pasta subagents da sessão>]` e acrescentar `— pedidos: N (hooks)` ao fim da linha; pedido novo (hook que perguntou onde não devia) vira correção do mecanismo na escada, não aprovação repetida.

Ela custa uma linha e prova que o passo aconteceu. O hook `Stop` (gate de aprendizado, `.claude/hooks/verify-on-stop.sh`) exige essa linha depois de commit de código na sessão, e libera mudança só em arquivos de aprendizado sem rodar build. Não contornar o gate escrevendo a linha sem fazer a verificação acima.

### Interrupção

Ao interromper, registrar antes de encerrar: o que bloqueou, o que foi tentado e não funcionou, e o que a próxima sessão precisa saber. O que vale para outras tarefas vai para `docs/gotchas/<área>.md` (seção Aprendizado) e para a linha de Registro (com `interrompida`); o que vale só para retomar esta tarefa vai para `SESSION.md`. Tentativa que falhou é a lição mais barata de perder e a mais cara de repetir.

### Feedback externo

Na primeira tarefa de cada sessão, se o `gh` estiver autenticado e responder (o `origin` é `wesllenm/SquadOS` no GitHub; na VM da nuvem o GraphQL do `gh` devolve 403, e aí segue sem registrar), delegar ao `explore` a leitura do feedback humano desde a última leitura:

- PRs mergeados depois da data em Feedback de PR de `docs/review-calibration.md` (`gh pr list --state merged --search "merged:AAAA-MM-DD..*" --json number,title,mergedAt`, sem `>` no texto, que o hook `redirect-guard` leria como redirecionamento e pediria aprovação);
- por PR, revisões e comentários (`gh pr view <n> --json reviews,comments` e `gh api --method GET repos/{owner}/{repo}/pulls/<n>/comments` para os de linha);
- ignorar comentários de bots, aprovações sem texto e conversa que não aponta defeito.

O `explore` devolve só os comentários que apontam defeito ou pedem mudança, cada um com arquivo, linha e uma frase. O `lead` classifica cada um:

- defeito que uma lente deveria ter pego: `escapou` na categoria correspondente (Totais) e entrada em Sempre verificar da `review-rubric` ou na seção Projeto;
- discordância com algo que o workflow fez de propósito: `recusado` na categoria, e fato em `docs/gotchas/<área>.md` se revelar preferência do time;
- preferência de estilo do time: proposta de regra de analisador ou `.editorconfig`, nunca item de revisão LLM.

Atualizar a data e o último PR lido em Feedback de PR. Sem `gh` autenticado ou sem PR novo, seguir sem registrar nada. Bug de produção corrigido numa tarefa entra do mesmo jeito: a correção leva teste de regressão (`test-audit`) e o defeito conta como `escapou` na categoria que deveria tê-lo pego.

### Quando sugerir manutenção

Sugerir no relatório uma tarefa de manutenção do aprendizado quando qualquer um for verdadeiro: Registro com mais de 30 linhas desde a última manutenção; núcleo `docs/gotchas.md` acima de 40 linhas ou 8 KB, ou um arquivo de `docs/gotchas/` com mais de 80 linhas; algum arquivo de `.claude/agent-memory/` com mais de 150 linhas; `CLAUDE.md` acima de 60 linhas; última manutenção (topo de `docs/review-calibration.md`) há mais de 15 dias.

### Manutenção do aprendizado (tarefa própria)

Classificada como SIMPLES, pedida pelo desenvolvedor ou sugerida pelo `lead`. O objetivo é que o que o workflow aprendeu continue curto, verdadeiro e útil; memória que só cresce acumula fato vencido e contradição.

1. Ler as fontes: `docs/review-calibration.md`, `docs/gotchas.md` e `docs/gotchas/*.md`, `docs/patterns.md`, `.claude/agent-memory/*/`, `.claude/rules/` (se existir), `CLAUDE.md` e as seções Sempre verificar, Não reportar e Projeto da `review-rubric`.
2. Delegar ao `explore` a checagem de validade: cada fato que cita arquivo, símbolo, pacote ou comando ainda existe? Fato cujo alvo sumiu é candidato a remoção.
3. Montar o plano com quatro listas: **remover** (vencido ou duplicado), **fundir** (mesmo fato em lugares diferentes, mantendo o do mecanismo mais forte), **promover** (o que aparece duas ou mais vezes em Registro, Totais ou nos gotchas, com o degrau proposto) e **contradições** (para o desenvolvedor decidir).
4. Antes de promover texto novo numa skill, passar cada item por estes critérios e cortar o que falhar: **durável** (continua verdadeiro em seis meses, depois de mudarem caminhos e versões); **específico** (amplo para valer em outras tarefas, preciso para o próximo agente reconhecer quando aplicar); **muda decisão** (o próximo agente faz algo diferente por causa dele); **ainda não coberto** (se a skill já diz e foi ignorada, a correção é posição e ênfase do texto existente, não item duplicado); **estrutural primeiro** (o que um teste, regra de analisador, script ou hook imporia vai para essa forma, não para texto); e **convergência** (fato visto uma vez precisa passar com folga nos outros critérios). Incluir os momentos em que o desenvolvedor colou contexto que o agente poderia ter buscado sozinho: o destino é a skill do fluxo onde isso aconteceu. Incluir a jardinagem: `node .claude/scripts/diff-smells.mjs --base <commit da última manutenção> --text` mostra válvulas de escape e comentários do período, e achados `simplicity` de "duas formas de fazer a mesma coisa" mostram padrões duplicados; tipo de válvula que apareceu em mais de uma tarefa é candidato a estancar (degrau 1 ou 2) e a uma atividade de limpeza. Incluir a distribuição dos números da escada de correção nas linhas de Registro do período ("escada N"; não confundir com os degraus de prova da `review-rubric`): correção que voltou depois de promovida para o nível 3 a 5 da escada é proposta de subir.
5. Incluir as linhas de `docs/harness-capabilities.md` ainda não `VERIFICADO` que já podem ser verificadas, e as `VERIFICADO` cuja evidência é de outra versão do Claude Code (verificação vencida volta a `IMPLEMENTADO`); as propostas de calibração pendentes (Não reportar) e as categorias com `escapou`; a saída de `calibrate-risk.sh` (distribuição de risco no período), quando existir; quantas linhas `CRAP` e `DUPLICADO` do `quality-signals.sh` viraram achado confirmado e quantas foram descartadas (se quase todas, subir `crap_threshold` ou `--min-tokens`; se achados de complexidade ou duplicação escaparam, baixar); e, a cada 90 dias, o orçamento de complexidade: componentes do workflow (agentes, skills, hooks, scripts) com invocação, ganho medido e custo de manutenção, com a proposta de remover ou fundir.
6. Obter uma aprovação, que vale só para os itens listados.
7. Aplicar: editar os arquivos, resumir as linhas de Registro com mais de 60 dias num parágrafo por mês (contagens e aprendizados promovidos) e atualizar Última manutenção.
8. Mecanismo determinístico aprovado (teste, regra de analisador, teste de arquitetura) segue o fluxo normal: implementar, verificar e revisar.
9. Commitar pela skill `commit` (por exemplo `docs: consolida aprendizado do workflow`) e registrar a manutenção em Registro.

Nunca apagar entrada de `docs/decisions.md` ou ADR: decisão revertida ganha entrada nova, não perde a antiga. A memória dos agentes pode ser editada pelo `lead` nesta tarefa; fora dela, cada agente cuida da própria.

## Relatório

```text
## Resultado

Status: implementado | verificado | bloqueado | ativo

Resumo:
Arquivos alterados: caminho — mudança
Testes e verificações: comando — resultado
Testes existentes alterados: nenhum | teste — motivo — autorização
Commits: <hash curto> <título>
Agentes utilizados: agente (modelo) — finalidade — resultado
Skills usadas:
Performance: camada 2 (testes de contagem) — quais | camada 3: não aplicável (sem `quente:`) ou categorias — linha por benchmark (OK | NOVO | TEMPO | ALOCAÇÃO | ESCALA | ORÇAMENTO | EXCEÇÃO | TAMANHO | REMOVIDO) — destino de cada achado | pontos de melhoria do perfil de CPU: método — % do tempo — proposta — aplicado e medido | follow-up | camada 3b: não aplicável ou anomalias — destino (achado | descartada: motivo) | camada 4: não executada | pergunta — antes — depois
Camada determinística: build com analisadores, formato, arquitetura — resultado; dependências vulneráveis e segredos — resultado ou não aplicável; mutação — mutantes sobreviventes no diff: N (mortos com teste | código morto removido | equivalentes) ou não aplicável (sem ferramenta local); qualidade — `CRAP`: N (testado | dividido | preexistente, follow-up), `DUPLICADO`: N (reusado | extraído | acidental) ou não aplicável
Classificação: nível (TRIVIAL | SIMPLES | COMPLEXA | CRITICA) — motivos do classificador — subiu durante a execução: não | de X para Y
Revisões:
- caminho rápido: review-agent → review-verifier — resultado
- caminho pesado: na sessão | segundo plano (concluído | pendente em SESSION.md: `revisão pesada pendente`) | adiado por SKIP_HEAVY_REVIEW
- lentes: review-simplicity (obrigatória); review-failures, review-domain — executada ou não aplicável — motivo
- review-verifier (Opus) — candidatos: N — confirmados: N — plausíveis: N — refutados: N
- review-critical (Opus) — executado ou não — motivo
- security-agent (Opus) — executado ou não aplicável
- rodadas de correção: N
Achados confirmados: id — severidade — categoria — arquivo:linha — destino (corrigido | recusado: motivo | não aplicável)
Preexistentes (follow-up): arquivo:linha — problema
Calibração: nenhuma | categoria — refutados/recusados — proposta para Não reportar da review-rubric
Segunda opinião: não aplicável | sugestão de `/code-review ultra` antes do PR — critério do review-critical atendido
Queries (query-plan): não aplicável | comando (arquivo:método) — veredito — evidência — referência oficial
Decisões: nenhuma | aguardando aprovação
Aprendizado: nenhum | falha recorrente — onde foi promovida | proposta; linha adicionada em docs/review-calibration.md; feedback de PR: não lido | PRs #… — N comentários — escaparam: categorias — recusados: categorias; manutenção: não necessária | sugerida — motivo
Limpeza: removido / mantido (motivo) / preexistente aguardando decisão
Riscos e limitações:
Follow-ups: candidatos de test-audit e itens fora do escopo
Stop condition: [x] critério ...
🎯 Resultado final:
```

Não usar `verificado` sem evidência. `implementado` não significa `ativo` em produção.
