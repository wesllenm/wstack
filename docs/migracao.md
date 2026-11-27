# Migração do harness para o plugin

Inventário da unidade 2.1: para onde vai cada arquivo do harness genérico (121 arquivos). As unidades 2.2 a 2.4 fizeram
a mudança (ver o Estado de cada uma) e esta tabela é a lista de conferência delas.

Destinos:
- **plugin:** vai para `plugin/<pasta>/` e é igual em todo projeto. Hooks entram em `plugin/hooks/hooks.json`; scripts
  são chamados pelo caminho do plugin e aprovados pelo hook aprovador (`docs/decisions.md`, 2026-11-24, scripts no
  plugin).
- **modelo do projeto:** vira modelo em `plugin/templates/`, e o `/wstack:bootstrap` gera a cópia no projeto, que o
  projeto mantém.
- **depois da 0.1.0:** modelo do projeto que fica fora da 2.4 (`docs/decisions.md`, 2026-11-24, destinos do
  inventário).
- **docs do wstack:** documento deste repositório, fora do plugin.
- **fora:** não vai para o wstack.

Classe: `mirror` (o arquivo é igual em todo projeto), `template` (versão genérica de um arquivo que cada projeto
preenche) ou `seed` (o projeto cria e mantém).

## Estado da 2.2

Feita (versão 0.0.4). Hooks em `plugin/hooks/` (ligados em `hooks.json`), scripts em `plugin/scripts/`, setup da
nuvem em `plugin/cloud/`, testes e provas em `plugin/tests/` (CI em `.github/workflows/ci.yml`), matriz de garantias em
`docs/harness-capabilities.md`. Diferenças em relação à tabela abaixo:
- `dotnet-allow.sh` não entrou no `hooks.json` na 2.2: o path-guard importa o `.mjs` quando o `risk.conf` declara
  `allow_module = dotnet`. Entrou na 0.0.40 (ver Depois da 2.4).
- O `cloud/setup.sh` ainda não instala o plugin: a instalação depende da versão fixada pelo projeto, que é da 2.4.
- As chaves do `verify-on-stop` ficaram `verify_solution`, `verify_build`, `verify_lint` e `verify_test`.
- Até a 2.4 criar os modelos, os testes usam fixtures em `plugin/tests/fixtures/` no lugar deles (`risk.conf`,
  `settings.json` com as regras de Edit, `hosts.conf`). Dois casos ficam fracos até a troca: "regra de .gitignore no
  allow" (`test-hook-commands.sh`) passa trivialmente, porque a fixture não tem `allow`; e a classificação de
  `.claude/cloud/` como CRITICA (`test-cloud-setup.sh`) usa uma fixture que já declara esse `critical`. A 2.4 troca as
  fixtures pelos modelos.
- O write-guard recusa a pasta do plugin carregado, salvo quando ela fica dentro do projeto: rodando o plugin direto
  do checkout do wstack, o próprio código-fonte é editável, e o script-allow só aprova com `plugin/` igual à
  `origin/main` (`docs/decisions.md`, edição do plugin no próprio wstack).
- Novo, sem arquivo de origem: `script-allow` (hook aprovador) e os testes `test-risk-conf`, `test-script-allow`,
  `test-verify-on-stop` e `test-plugin-paths`.
- As provas `prove-*.sh` foram adaptadas, mas não rodaram (custam modelo).

## Estado da 2.3

Feita (versão 0.0.10). Skills em `plugin/skills/` (`/wstack:<nome>`) e agentes em `plugin/agents/`, copiados da origem
num commit sem mudança e adaptados nos seguintes; conferência estática em `plugin/tests/test-skills-agents.sh`.
Diferenças em relação às tabelas abaixo:
- Vieram também os 14 `reference/*.md` das skills `performance`, `query-plan` e `review-rubric` (55 arquivos ao todo).
  Ficaram fora a `verify-<app>` (2.4) e as quatro skills do produto de origem (`agent-stage-contract`, `dapr-workflow`,
  `demand-lifecycle`, `source-adapters`), que não são do harness.
- Os comandos de script usam `${CLAUDE_PLUGIN_ROOT}/scripts/`, com o interpretador que o `script-allow` aceita; a skill
  lead tem a seção "Scripts do plugin". Os `reference/*.md` são lidos pelo Read, onde a variável não é trocada: citam o
  script pelo nome.
- Agentes chamados e listados em `Agent(...)` como `wstack:<nome>`, e skills carregadas como `wstack:<nome>`; `skills:`
  do frontmatter fica no nome curto (sonda 3, B e C).
- Sem `memory:` (`docs/decisions.md`, agentes do plugin sem `memory:`): `review-agent`, `review-simplicity` e
  `review-verifier` devolvem uma linha `aprendizado:`, que o lead grava em `docs/gotchas/`; o verificador não tem Write,
  então nem podia gravar arquivo. `TodoWrite` virou `TaskCreate`, `TaskUpdate` e `TaskList`.
- `mcpServers` saiu dos agentes de banco (agente de plugin ignora o campo, pela documentação de subagentes), e o
  `tools:` passou de `mcp__database`, que não casa ferramenta nenhuma, para `mcp__database__*`. O servidor vem da
  configuração de MCP do projeto (depois da 0.1.0).
- A `review-rubric` é do plugin; o que é de cada repositório (Sempre verificar, Não reportar e Projeto) vai para
  `docs/review-rubric.md` do projeto, modelo da 2.4 (`docs/decisions.md`, complemento da rubrica no projeto). Mudança em
  skill, agente ou hook do plugin vira proposta no wstack, não edição no projeto.
- O `worktree.baseRef` virou decisão do wstack; a skill lead não cita mais o arquivo de gotchas da origem.
- Os nomes e fatos do projeto de origem saíram; as referências de stack ficaram como módulos, com exemplos genéricos.
- Saíram as peças da sonda 3 (agentes e skills `sonda-*`).
- Não conferido no Claude Code real: uma sessão com `"agent": "wstack:lead"` (é da 2.4, com o `settings.json` modelo)
  delegando aos agentes reais.

## Estado da 2.4

Feita (versão 0.0.11). Modelos do projeto em `plugin/templates/` (a pasta espelha o destino no projeto), copiados por
`plugin/scripts/bootstrap.sh` e preenchidos pela skill `/wstack:bootstrap`; testes em `test-bootstrap.sh` e
`test-inert.sh`. Decisões em `docs/decisions.md` (2026-11-25: plugin inerte sem risk.conf, versão fixada por tag,
modelos e bootstrap determinístico). Diferenças em relação às tabelas abaixo:
- Entraram como modelo, sem estar no inventário: `.claude/project.md` e `.claude/architecture.md` (a skill lead e o
  planner os citam), `docs/gotchas.md` (o `CLAUDE.md` o importa) e `docs/decisions.md`.
- `settings.json`: `agent` `wstack:lead`, marketplace fixado por `ref` e `enabledPlugins`; saíram as regras de
  `.claude/scripts/` e as de stack (a skill põe as da stack do projeto); `TodoWrite` virou `TaskCreate`, `TaskUpdate`
  e `TaskList`. As regras de `Edit` são as da fixture da 2.2, que o `test-path-guard.sh` confere contra o hook.
- `risk.conf`: chaves `verify_*`; o `critical` de `.claude/hooks`, `.claude/scripts` e da rubrica antiga virou
  `.github/workflows/*` e `docs/review-rubric.md`; as `review_rule` apontam para checklist do projeto (follow-up para
  citar os do plugin). A linha `default_branch = main` é literal (os testes copiam o modelo); o script troca pela
  branch detectada.
- `hosts.conf` ganhou a stack `wstack` (`github.com`, de onde o `claude plugin` clona o marketplace).
- A `verify-<app>` é esqueleto em `templates/verify-app/`, criada só com `--app`; a receita e a prova são da skill.
- As fixtures `risk.conf`, `settings.json` e `hosts.conf` saíram; os testes leem os modelos. Os dois casos fracos da
  2.2 deixaram de ser triviais: o modelo tem `allow`, e a classificação de `.claude/cloud/` vem do `risk.conf` modelo.
- O `setup.sh` instala o plugin na ref do `.claude/settings.json` do projeto e o `--check` acusa versão diferente.
- O gate de aprendizado do Stop passou a contar `docs/gotchas/` e `docs/review-rubric.md` como aprendizado.
- Não conferido no Claude Code real: uma sessão num projeto que passou pelo bootstrap, com `"agent": "wstack:lead"`
  delegando aos agentes; e a tag `v0.0.11`, que só existe depois do merge (publicada depois, no commit do merge).

## Depois da 2.4

- 0.0.12: o projeto nasce na nuvem. No projeto que ainda não cita o plugin, o `setup.sh` instala a maior tag
  `v<versão>` publicada, e o `session-start` do projeto sem `risk.conf` indica o `/wstack:bootstrap`
  (`docs/decisions.md`, plugin antes do bootstrap na nuvem). Antes disso, adotar exigia um passo no Claude Code local.
- 0.0.13: a skill lead vira núcleo com leitura sob demanda (`reference/`) e playbooks por tipo de tarefa; entram as
  skills `correct`, `how`, `why` e `unslop`, a revisão por outro fornecedor (`interrogate.mjs`), a arena de design e os
  princípios citados no relatório (`principles.mjs`).
- 0.0.14: o núcleo da skill lead cai de 6.926 para 4.939 palavras (`pipeline.md` e `fechamento.md` novos); o `Stop`
  exige o campo `princípios:` na linha de Registro; o bootstrap pergunta se o projeto liga a revisão por outro
  fornecedor; `interrogate.mjs` e `principles.mjs` ficam robustos ao texto de modelo (acentos, prosa, pontuação,
  chamada que falhou).
- 0.0.15: o `Stop` confere os campos `princípios:` e `pedidos:` da linha de Registro contra a transcrição da sessão
  (`principles.mjs --cited` e `permission-asks.mjs`); o `interrogate.mjs` grava `falhou: ...` e sai 4 quando nenhum
  modelo responde, e na CRITICA isso segura o commit.
- 0.0.16: a conferência do Registro no `Stop` falha fechada: script de conferência que não roda ou sai com código
  inesperado bloqueia ("não consegui verificar"), e só a transcrição ausente fica como aviso; o `principles.mjs` não
  conta Skill ou Read sem resultado na transcrição.
- 0.0.17: no `Stop`, não conseguir ler o `transcript_path` (node ausente, entrada que não é JSON) bloqueia em vez de
  cair no aviso; a chamada dos scripts de conferência funciona no bash 3.2 do macOS.
- 0.0.18: o `Stop` deixa de pular a verificação por falta de ferramenta: a impressão digital vem do `git hash-object`
  (sem `sha1sum` nem `xargs` GNU, que o macOS padrão não tem), aviso do node não vira caminho de transcrição, e entrada
  sem `session_id` bloqueia o gate de aprendizado.
- 0.0.19: no `Stop`, o `.claude/verify-blocked.md` libera o que o ambiente impediu de conferir (sem `session_id`,
  script ou node quebrados), com o motivo visível ao desenvolvedor; divergência de conteúdo no Registro continua
  bloqueando. Sem o HEAD do início da sessão, o gate de aprendizado avisa.
- 0.0.20: o `.claude/verify-blocked.md` só vale para a sessão que o gravou (linha `sessão: <id>`, ou `head: <SHA>` sem
  `session_id`); arquivo de outra sessão é ignorado com aviso, e o `SessionStart` avisa quando ele existe. O
  `session_id` só é aceito em `[A-Za-z0-9_-]`.
- 0.0.21: só o desenvolvedor cria a exceção de verificação: gravar `.claude/verify-blocked.md` pede aprovação
  (`write-guard` na ferramenta, também na nuvem; `path-guard` no Bash fora dela), e ela vale para um encerramento,
  porque o `Stop` a apaga ao usar.
- 0.0.22: turno encerrado pela exceção de verificação segura o push: o `Stop` grava `.claude/.session/unverified`, e o
  `push-guard` recusa o push de branch até um encerramento com todos os gates verdes (o checkpoint `wip/` segue).
- 0.0.23: o marcador de verificação pendente só sai quando o build e os testes rodaram e passaram cobrindo o HEAD
  gravado nele (árvore limpa não conta; com o marcador, o build roda sobre o commitado). Um marcador por sessão
  (`unverified-<sessão>`), e qualquer um segura o push; o `SessionStart` avisa do de outra sessão. Gravar em
  `.claude/.session/` é recusado pelo `write-guard` e pelo `path-guard`, também na nuvem, onde o `path-guard` recusa
  ainda comando que cita `.claude/verify-blocked.md`.
- 0.0.24: todo o estado dos hooks fica fora do alcance do agente, também na nuvem: o `path-guard` recusa comando que
  cita `.claude/.session/` (o `checkpoint-ok` incluído) ou `.claude/.verify-ok`, e o `write-guard` recusa gravá-los.
  O marcador de verificação pendente só sai com a árvore limpa (verde com conserto sem commit o mantém e pede o
  commit), e saída sem verificação com o marcador avisa que o push segue recusado. Mensagem de commit que cite esses
  caminhos vai por arquivo (`git commit -F`).
- 0.0.25: marcador de verificação preso (commit da exceção reescrito por amend ou rebase, sessão encerrada, formato
  antigo) diz como destravar: a recusa do `push-guard`, o aviso do `SessionStart` e o `systemMessage` do `Stop` trazem
  o `rm -f` dos marcadores, para o desenvolvedor rodar fora do agente.
- 0.0.26: o `rm -f` da recusa só lista nomes no formato que o `Stop` grava (arquivo `unverified*` com outro nome segura
  o push e é avisado); o aviso do `Stop` com o `risk.conf` incompleto traz o comando; sem `CLAUDE_PROJECT_DIR` e fora
  de repositório git, o `push-guard` recusa o push.
- 0.0.27: revisão com prova por execução, lacuna de lente e comentário de restrição (lote 1 do pstack). Candidato
  bloqueante ou importante de comportamento leva `prova: <comando> → <saída esperada>`; sem ela, o
  `check-findings.mjs` o marca `situação: a confirmar`, e o `review-verifier` roda a prova antes de confirmar. Cada
  lente termina com `status: achados | sem achados | falhou: <motivo>`, e o `check-findings.mjs` recebe um arquivo por
  lente: sem status é lacuna (código 4), nunca `sem achados`. O `diff-smells.mjs` separa o comentário de restrição
  (`RESTRICAO`). Lista de candidatos sem linha de status, que antes passava, agora sai 4.
- 0.0.28: verificação (lote 2 do pstack). O modelo da `verify-<app>` ganha as seções Regras e Manutenção
  (`/verify-<app> manutenção`) e o modelo das quatro seções de cada feature; o aviso do `map-staleness.mjs` cita o
  comando e o commit de partida. Skill nova `blast-radius`, no plano de CRITICA e de COMPLEXA com contrato público,
  migration ou mensageria. Os Degraus de prova da `review-rubric` viram a escada de evidência, com os rótulos medida,
  inferida e palpite no relatório. Projeto que já tem a `verify-<app>` copia as seções novas à mão: o bootstrap não
  sobrescreve o que existe.
- 0.0.29: aprendizado (lote 3 do pstack). **Exige ação no projeto:** `allow_module`, `review_exclude` e `smell_exclude`
  só valem com `| vence: AAAA-MM-DD | motivo: <texto>`; sem isso são ignorados (as formas do dotnet voltam a pedir, o
  arquivo excluído volta à revisão e ao `diff-smells`) e o `SessionStart` avisa a linha. Acrescentar a validade às
  linhas do `.claude/risk.conf` (a edição pede aprovação). Também: `/correct historico`; seção Regras e garantias no
  `CLAUDE.md` do modelo e Backlog de mecanismo no `docs/review-calibration.md` (projeto existente copia à mão); triagem
  das lições em aceitas, rejeitadas e backlog no campo `aprendizado:` do Registro; tipo de tarefa "sem playbook".
- 0.0.30: planejamento e playbooks (lote 4 do pstack). Esboço da fatia (uso e assinaturas) no sprint contract de
  COMPLEXA e CRITICA, com desvio sinalizado pelo `implementer`; checkpoint de paralelismo no plano; arena com `planner`
  juiz e pontuação independente do lead; skills `attack-the-premise`, `build-the-lever`, `separate-before-serializing` e
  `subtract-before-you-add`; playbooks `diagnostico-runtime.md` e `prototipo.md` e a subida iterativa no
  `performance.md`; pausa antes da compactação no `sessao.md`. O `iteration-guard` ignora `session_id` fora de
  `[A-Za-z0-9_-]`. Sem ação no projeto.
- 0.0.31: relatório e PR (lote 5 do pstack). Seção Decisões pendentes no fim do relatório (na nuvem, também no
  topo); `why` com hipóteses concorrentes, bloco Preservar / Mudar / Evitar / Risco e fontes puladas; corpo do PR nas
  seções Por quê, O que mudou, Escopo, Trade-offs, Raio de impacto e Verificação, conferido por `slop-check.mjs --pr`,
  e PR em draft com verificação pendente; `test-readme-counts.sh` no CI. Acompanhamento do PR (5.5) registrado como
  planejado para depois da 0.1.0. Sem ação no projeto.
- 0.0.32: candidato sem severidade ou com severidade fora da lista exige prova; a saída esperada vai no campo
  `esperado:` (`->` não separa mais); o verificador não grava arquivo e devolve `plausível — falta prova` para o lead
  pedir o teste ao `implementer`; Limites da prova na `review-rubric`; `RESTRICAO` fora do `--gate` do `diff-smells` e
  procurada também em `///`; escalas definidas na `blast-radius`; `slop-check --pr` aceita título sem acento. Sem ação
  no projeto.
- 0.0.33: `diff-smells.mjs` com a base ausente (clone raso) diz isso na saída e reprova o `--gate`, em vez de comparar
  só com o HEAD calado; prosa com cara de código deixa de ser `CODIGO_COMENTADO`; comentário `--` de SQL é lido;
  prefixo do diff fixo. `check-findings.mjs` não corta a `prova:` na seta quando há `esperado:`. Projeto com
  `diff-smells --gate` no CI e clone raso precisa buscar a base (`git fetch --depth=<n> origin <base>`) antes.
- 0.0.34: `check-findings.mjs` ancora o achado sobre código removido no ponto do corte (`ancoragem: removido`) e
  conta o trecho que só remove como linha alterada; lente com todos os candidatos descartados sai em `descartes:`.
  Diff lido pelas contagens do `@@` (`diff-parse.mjs`), no `check-findings` e no `diff-smells`. O `SessionStart` avisa
  chave desconhecida e linha malformada no `risk.conf`. README com o mapa do plugin em colunas por etapa. Sem ação
  no projeto.
- 0.0.35: `base =` vazio no `risk.conf` reprova o `diff-smells --gate`, como a base ausente; linha movida só conta
  dentro do mesmo arquivo; `check-findings` não usa diff parcial e separa lentes de mesmo nome pelo caminho; o
  `SessionStart` avisa valor vazio no `risk.conf`. Projeto com `base =` vazio passa a ter o gate reprovado até
  preencher a base.
- 0.0.36: hook `verifier-guard` nos comandos do `review-verifier`: nega rede e execução arbitrária, deixa passar as
  formas conhecidas de prova e pede aprovação para o resto (inclusive `node -e`). `check-findings` descarta candidato
  com chave repetida e avisa trecho cortado. Sem ação no projeto; prova que dependia de `node -e` passa a pedir
  aprovação.
- 0.0.37: prova `prove-verifier-guard.sh` com o Claude Code real (o `agent_type` chega como
  `wstack:review-verifier` na 2.1.332) e o risco aceito de rodar teste do projeto registrado no README. Sem ação no
  projeto.
- 0.0.38: `verifier-guard` pede aprovação a subagente sem `agent_type`; nega `sort -o`, `sort --compress-program`,
  `rg --pre` e `sed -i`; trata `&` como separador; libera `npx` só com `--no-install`, `git diff`/`show`/`log` só com
  `--no-ext-diff --no-textconv`, `git blame` só com `--no-textconv` e `sed -n` só com número de linha e `p`; segue
  symlink antes de liberar script do repositório. Sem ação no projeto; prova nas formas antigas (`npx vitest`,
  `git log` sem as opções) passa a pedir aprovação.
- 0.0.39: `verifier-guard` com lista fechada: no `review-verifier` só passam executor de teste, script do repositório e
  `git log`/`show`/`blame` com as flags listadas no hook. `grep`, `rg`, `cat`, `sed`, `sort`, `find`, `git diff`,
  `git grep` e pipe para filtro (`| tail`) passam a pedir aprovação; o verifier lê código com Read, Grep e Glob. Sem
  ação no projeto.
- 0.0.40: `dotnet-allow.sh` registrado no `hooks.json`: com `allow_module = dotnet` válido no `risk.conf`, as formas
  fechadas do `dotnet` passam sem pedido, sem regra exata no `allow` do `settings.json`. A `testing-strategy` volta a
  pedir avaliação a cada mudança de prompt, skill ou modelo. Projeto .NET com o `allow_module`: pode tirar do `allow`
  as regras exatas de `dotnet` que só existiam por falta do hook.
- 0.0.41: as skills `commit`, `lead` (aprendizado e paralelo), `why`, `recall`, `correct` e `unslop` abrem, leem e
  rotulam PR pela API REST (`gh api`), não pelo `gh pr`, que usa GraphQL e recebe 403 na nuvem. O `setup.sh --docker`
  apaga também o PID velho do `containerd` gerenciado. Sem ação no projeto; regra `allow` para `gh pr ...` no
  `settings.json` do projeto deixa de ser usada pelo plugin.
- 0.0.42: destinos de documento configuráveis pelas chaves `doc_decisions`, `doc_gotchas`, `doc_gotchas_dir`,
  `doc_calibration`, `doc_rubric` e `doc_state` do `risk.conf` (`doc-paths.mjs`); sem a chave, o caminho de antes. Com
  `doc_state`, a pendência e o "onde paramos" saem do `SESSION.md` para o arquivo versionado. Sem ação no projeto que
  usa os caminhos padrão; o projeto que já tem esses fatos em outro lugar aponta as chaves e confere o aviso do
  `SessionStart`.
- 0.0.43: chave `override` do `risk.conf` para as skills e agentes do plugin que o projeto substitui (`overrides.mjs`);
  a lista `Agent(...)` da `lead` traz os agentes do plugin também sem prefixo, e assim chama o agente do projeto de
  mesmo nome. Projeto com skill ou agente de mesmo nome de um do plugin: o `SessionStart` passa a avisar, e a troca
  (que o pré-carregamento já fazia) se declara com `override = <nome>`.
- 0.0.44: chave `companion` do `risk.conf` para os repositórios que mudam junto na mesma tarefa (`companions.mjs`):
  `classify-diff.sh --companions` dá o nível da tarefa, o `Stop` verifica cada companheiro com o `risk.conf` dele e o
  `checkpoint-tests` usa as áreas do repositório do commit. O timeout do `Stop` sobe de 900 s para 1800 s. Sem ação no
  projeto de um repositório só; o push do companheiro ainda pede aprovação (2ª parte).
- Sem origem no harness, e por isso fora das tabelas abaixo (`docs/decisions.md`, entradas de 2026-11-25): o núcleo da
  skill lead com `reference/` e `playbooks/`; as skills `correct`, `how`, `why` e `unslop`; os scripts
  `interrogate.mjs`, `principles.mjs` e `slop-check.mjs`, com os testes deles.

## Hooks

Todos para `plugin/hooks/`, na unidade 2.2. Os que hoje leem `"$CLAUDE_PROJECT_DIR"/.claude/...` para achar a si mesmos
ou a outro hook passam a usar a pasta do plugin; o que é do projeto (risk.conf, git, arquivos protegidos) continua vindo
de `$CLAUDE_PROJECT_DIR`.

| Arquivo | Classe | Destino | Evento | Ajuste |
|---|---|---|---|---|
| `.claude/hooks/checkpoint-tests.sh` | mirror | plugin | PreToolUse Bash, TaskCompleted | lê `checkpoint` do risk.conf do projeto |
| `.claude/hooks/closed-forms.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/cloud-services.sh` | mirror | plugin | SessionStart | lê `cloud_service`/`cloud_ready` do risk.conf do projeto; chama o `cloud/setup.sh` pelo caminho do projeto, que muda com ele |
| `.claude/hooks/dotnet-allow.mjs` | mirror | plugin | módulo | módulo de stack .NET: o path-guard o importa quando o risk.conf declara `allow_module = dotnet` |
| `.claude/hooks/dotnet-allow.sh` | mirror | plugin | PreToolUse Bash, se registrado | hook próprio (o teste e a skill lead o tratam assim); no inventário constava como não registrado na origem, mas o SquadOS o registrava desde 2026-11-19; entra no `hooks.json` na 0.0.40, condicionado ao `allow_module = dotnet` válido |
| `.claude/hooks/edit-check.sh` | mirror | plugin | PostToolUse edição | lê as regras do risk.conf do projeto |
| `.claude/hooks/git-read-allow.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/git-read-allow.sh` | mirror | plugin | PreToolUse Bash | |
| `.claude/hooks/git-repo.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/iteration-guard.sh` | mirror | plugin | PostToolUse edição | |
| `.claude/hooks/notify.sh` | mirror | plugin | Notification | renomear as variáveis de ambiente que levam o nome do projeto de origem |
| `.claude/hooks/path-guard.mjs` | mirror | plugin | módulo | proteção revista: os hooks e scripts saem do projeto; protege o `settings.json` (com a versão fixada do plugin) e o `risk.conf` do projeto, e cobre os caminhos do plugin (seu pedido vale sobre a aprovação do hook aprovador) |
| `.claude/hooks/path-guard.sh` | mirror | plugin | PreToolUse Bash | idem |
| `.claude/hooks/protected-paths.mjs` | mirror | plugin | módulo | lista de caminhos protegidos revista como no path-guard |
| `.claude/hooks/push-guard.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/push-guard.sh` | mirror | plugin | PreToolUse Bash | |
| `.claude/hooks/redirect-guard.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/redirect-guard.sh` | mirror | plugin | PreToolUse Bash | |
| `.claude/hooks/risk-conf.mjs` | mirror | plugin | módulo | lê `$CLAUDE_PROJECT_DIR/.claude/risk.conf`, não a pasta `.claude` onde o arquivo está |
| `.claude/hooks/session-start.sh` | mirror | plugin | SessionStart | o wstack já tem um `plugin/hooks/session-start.sh` (o da sonda); o que fica continua imprimindo `wstack <versão> carregado.`, que é como se confere a versão em uso |
| `.claude/hooks/verify-on-stop.sh` | template | plugin | Stop | `SOLUTION`, `BUILD_CMD`, `LINT_CMD` e `TEST_CMD` saem do arquivo e viram chaves do risk.conf; exige o arquivo de calibração, que o bootstrap cria (2.4) |
| `.claude/hooks/write-guard.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/write-guard.sh` | mirror | plugin | PreToolUse edição | |
| `.claude/hooks/write-rule.mjs` | mirror | plugin | módulo | |

Novo na 2.2, sem arquivo de origem: o hook aprovador dos scripts do plugin (PreToolUse Bash), com a forma fechada de
cada script e seus argumentos.

## Scripts

Para `plugin/scripts/`, na unidade 2.2, salvo os de teste (`plugin/tests/`) e os indicados. "Chamado por" diz onde o
caminho muda.

| Arquivo | Classe | Destino | Chamado por | Ajuste |
|---|---|---|---|---|
| `.claude/scripts/bdn-to-tsv.cs` | mirror | plugin | comando `bench` do risk.conf, por `$BENCH_SCRIPTS` | módulo de stack .NET |
| `.claude/scripts/bench-compare.sh` | mirror | plugin | skills lead, performance, review-rubric; agente performance-agent | exporta `BENCH_SCRIPTS` com a pasta de scripts do projeto: passa a ser a do plugin |
| `.claude/scripts/bundle-size.sh` | mirror | plugin | comando `bench` do risk.conf, por `$BENCH_SCRIPTS` | módulo de frontend; o risk.conf modelo traz o exemplo |
| `.claude/scripts/calibrate-risk.sh` | mirror | plugin | skill lead | chama o classify-diff pelo caminho do projeto |
| `.claude/scripts/check-findings.mjs` | mirror | plugin | skills lead, review-rubric; agentes de revisão | |
| `.claude/scripts/check-trajectory.mjs` | mirror | fora | só a matriz de garantias | ver pendência 5 |
| `.claude/scripts/checkpoint.sh` | mirror | plugin | skill lead | importa `../hooks/protected-paths.mjs`: depende de `scripts/` e `hooks/` lado a lado |
| `.claude/scripts/classify-diff.sh` | mirror | plugin | skills lead, commit; agente lead; calibrate-risk | o CLAUDE.md e o risk.conf modelo citam o caminho |
| `.claude/scripts/compare-bench.sh` | mirror | plugin | bench-compare, por `$BENCH_SCRIPTS` | |
| `.claude/scripts/compare-results.mjs` | mirror | fora | só a matriz de garantias | ver pendência 5 |
| `.claude/scripts/criterion-to-tsv.sh` | seed | plugin | comando `bench` do risk.conf, por `$BENCH_SCRIPTS` | módulo de stack Rust |
| `.claude/scripts/diff-smells.mjs` | mirror | plugin | skills lead, clean-code; workflow gates (depois da 0.1.0, baixando o wstack) | |
| `.claude/scripts/enviar-nuvem.sh` | mirror | plugin | skill lead | pede aprovação de propósito: fica fora do hook aprovador |
| `.claude/scripts/folded-top.sh` | seed | plugin | comando `profile` do risk.conf (opcional, sem exemplo no modelo) | módulo de perfil (Rust, C/C++, Go) |
| `.claude/scripts/hot-methods.cs` | mirror | plugin | comando `profile` do risk.conf (opcional, sem exemplo no modelo) | módulo de stack .NET; o uso no cabeçalho cita o caminho do projeto |
| `.claude/scripts/map-staleness.mjs` | mirror | plugin | SessionStart | vira hook do plugin |
| `.claude/scripts/nova-atividade.sh` | mirror | plugin | skill lead | |
| `.claude/scripts/otlp-sink.mjs` | mirror | plugin | session-start, summarize-runs | recebe a telemetria que o `env` do settings.json modelo aponta para ele |
| `.claude/scripts/permission-asks.mjs` | mirror | plugin | skill lead | |
| `.claude/scripts/pr-risk-gate.mjs` | mirror | plugin | workflow merge-por-risco (depois da 0.1.0, baixando o wstack) | |
| `.claude/scripts/prove-redirect-guard.sh` | template | plugin (`tests/`) | à mão, com `claude -p` | prova com o Claude Code real; fora do CI |
| `.claude/scripts/prove-write-matrix.sh` | template | plugin (`tests/`) | à mão, com `claude -p` | idem |
| `.claude/scripts/prune-merged.sh` | mirror | plugin | skill lead | |
| `.claude/scripts/quality-diff.mjs` | mirror | plugin | quality-signals | |
| `.claude/scripts/quality-signals.sh` | mirror | plugin | skills lead, review-rubric; agente review-simplicity | |
| `.claude/scripts/recall.mjs` | mirror | plugin | skill recall | |
| `.claude/scripts/review-dispatch.mjs` | mirror | plugin | skills lead, review-rubric | |
| `.claude/scripts/sessions.sh` | mirror | plugin | SessionStart, Stop, SessionEnd; skill lead | os três eventos viram hooks do plugin |
| `.claude/scripts/summarize-runs.mjs` | mirror | plugin | à mão | |
| `.claude/scripts/test-classify.sh` | mirror | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/test-cloud-setup.sh` | mirror | plugin (`tests/`) | CI do wstack | trocar o exemplo de imagem que leva nome da stack do projeto de origem |
| `.claude/scripts/test-dotnet-allow.sh` | template | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/test-git-read-allow.sh` | mirror | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/test-hook-commands.sh` | mirror | plugin (`tests/`) | CI do wstack | passa a testar os comandos de `plugin/hooks/hooks.json` |
| `.claude/scripts/test-path-guard.sh` | template | plugin (`tests/`) | CI do wstack | casos revistos com a proteção nova |
| `.claude/scripts/test-permission-asks.sh` | mirror | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/test-prune-merged.sh` | mirror | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/test-push-guard.sh` | template | plugin (`tests/`) | CI do wstack | um caso confere uma linha do arquivo de gotchas da origem: sai |
| `.claude/scripts/test-redirect-guard.sh` | mirror | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/test-write-guard.sh` | mirror | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/validate-result.mjs` | mirror | fora | nenhum | ver pendência 5 |
| `.claude/scripts/worktree-env.sh` | mirror | plugin | skill lead; nova-atividade | |

## Nuvem

| Arquivo | Classe | Destino | Unidade | Ajuste |
|---|---|---|---|---|
| `.claude/cloud/setup.sh` | mirror | plugin | 2.2 | chamado pelo cloud-services e pela skill lead pelo caminho do projeto, que muda; é também o texto colado no setup script do ambiente, que roda antes de o plugin existir na máquina, então precisa funcionar sozinho e instalar o plugin (ver pendência 2); trocar o exemplo de imagem que leva nome da stack do projeto de origem |
| `.claude/cloud/hosts.conf` | template | modelo do projeto | 2.4 | |

## Agentes

Todos para `plugin/agents/`, na unidade 2.3, com os caminhos de script trocados pelos do plugin. Os `template` vão na
versão genérica (feito; ver Estado da 2.3). Conferido na 2.3: o Claude Code pode ignorar campos do frontmatter em agentes de plugin
(`mcpServers`, `hooks`, `permissionMode`); `database-helper`, `database-reviewer` e `performance-agent` declaram
`mcpServers: [database]`, que também depende da configuração de MCP do projeto (depois da 0.1.0). Os `skills:` do
frontmatter citam skills sem o prefixo `wstack:`: conferir se resolvem dentro do plugin.

| Arquivo | Classe | Destino |
|---|---|---|
| `.claude/agents/ci-reviewer.md` | mirror | plugin |
| `.claude/agents/database-helper.md` | template | plugin |
| `.claude/agents/database-reviewer.md` | template | plugin |
| `.claude/agents/e2e-critical-review.md` | template | plugin |
| `.claude/agents/explore.md` | mirror | plugin |
| `.claude/agents/implementer.md` | mirror | plugin |
| `.claude/agents/lead.md` | template | plugin |
| `.claude/agents/performance-agent.md` | template | plugin |
| `.claude/agents/planner.md` | template | plugin |
| `.claude/agents/playwright-e2e.md` | template | plugin |
| `.claude/agents/review-agent.md` | template | plugin |
| `.claude/agents/review-critical.md` | template | plugin |
| `.claude/agents/review-domain.md` | template | plugin |
| `.claude/agents/review-failures.md` | template | plugin |
| `.claude/agents/review-simplicity.md` | mirror | plugin |
| `.claude/agents/review-verifier.md` | mirror | plugin |
| `.claude/agents/security-agent.md` | template | plugin |
| `.claude/agents/simplify.md` | mirror | plugin |

## Skills

Para `plugin/skills/`, na unidade 2.3 (ficam `/wstack:<nome>`), salvo a `verify-<app>`.

| Arquivo | Classe | Destino |
|---|---|---|
| `.claude/skills/api-design/SKILL.md` | template | plugin |
| `.claude/skills/clean-architecture/SKILL.md` | template | plugin |
| `.claude/skills/clean-code/SKILL.md` | template | plugin |
| `.claude/skills/commit/SKILL.md` | template | plugin |
| `.claude/skills/concurrency/SKILL.md` | template | plugin |
| `.claude/skills/continuous-delivery/SKILL.md` | template | plugin |
| `.claude/skills/db-evolution/SKILL.md` | template | plugin |
| `.claude/skills/domain-modeling/SKILL.md` | template | plugin |
| `.claude/skills/event-driven/SKILL.md` | template | plugin |
| `.claude/skills/frontend/SKILL.md` | template | plugin |
| `.claude/skills/lead/SKILL.md` | template | plugin |
| `.claude/skills/observability/SKILL.md` | template | plugin |
| `.claude/skills/performance/SKILL.md` | template | plugin |
| `.claude/skills/query-plan/SKILL.md` | template | plugin |
| `.claude/skills/recall/SKILL.md` | mirror | plugin |
| `.claude/skills/refactoring/SKILL.md` | template | plugin |
| `.claude/skills/resilience/SKILL.md` | template | plugin |
| `.claude/skills/review-rubric/SKILL.md` | template | plugin |
| `.claude/skills/security/SKILL.md` | template | plugin |
| `.claude/skills/tdd/SKILL.md` | template | plugin |
| `.claude/skills/test-audit/SKILL.md` | template | plugin |
| `.claude/skills/testing-strategy/SKILL.md` | template | plugin |
| `.claude/skills/ux/SKILL.md` | template | plugin |
| `.claude/skills/verify-<app>/SKILL.md` | seed | modelo do projeto (2.4) |
| `.claude/skills/vertical-slice/SKILL.md` | template | plugin |

## Configuração e arquivos do projeto

| Arquivo | Classe | Destino | Unidade | Ajuste |
|---|---|---|---|---|
| `.claude/settings.json` | template | modelo do projeto | 2.4 | a seção `hooks` vai para `plugin/hooks/hooks.json` (2.2); as regras de `.claude/scripts/...` saem (o hook aprovador as substitui, salvo o script que pede aprovação de propósito); ficam as permissões, `agent` (passa a `wstack:lead`), `worktree.baseRef` (a skill lead depende dele), o `env` da telemetria (o otlp-sink a recebe) e o plugin fixado numa versão (ver pendência 2) |
| `.claude/risk.conf` | template | modelo do projeto | 2.4 | ganha as chaves de build, formato e teste do verify-on-stop; os comentários que citam `.claude/scripts/` e `.claude/hooks/` passam a citar o plugin; as linhas `critical = .claude/hooks/*`, `.claude/scripts/*` e `.claude/cloud/*` apontam para pastas que deixam de existir no projeto |
| `CLAUDE.md` | template | modelo do projeto | 2.4 | cita `.claude/scripts/classify-diff.sh` (passa a citar o script do plugin) e importa `@docs/gotchas.md` (a 2.4 cria o arquivo ou tira o import) |
| `.github/workflows/claude-review.yml` | template | depois da 0.1.0 | | |
| `.github/workflows/gates.yml` | template | depois da 0.1.0 | | baixa o wstack na versão fixada e roda o diff-smells de lá |
| `.github/workflows/merge-por-risco.yml` | mirror | depois da 0.1.0 | | baixa o wstack na versão fixada e roda o pr-risk-gate de lá |
| `.mcp.json` | seed | depois da 0.1.0 | | só para projeto com banco |
| `.claude/toolbox/tools.yaml` | seed | depois da 0.1.0 | | idem |
| `docs/review-calibration.md` | seed | modelo do projeto | 2.4 | o verify-on-stop (2.2) exige este arquivo para o gate de aprendizado |
| `docs/review-rubric.md` | seed | modelo do projeto | 2.4 | novo na 2.3, sem arquivo de origem: as seções Sempre verificar, Não reportar e Projeto da rubrica do projeto, que a `review-rubric` do plugin manda ler |
| `docs/harness-capabilities.md` | seed | docs do wstack | 2.2 | a matriz descreve os hooks, que passam a ser do plugin |

## Ajustes em todos os arquivos (2.2 a 2.4)

- **Caminhos:** `"$CLAUDE_PROJECT_DIR"/.claude/hooks/...`, `.claude/scripts/...` e `.claude/cloud/...` viram caminhos
  do plugin, inclusive nos modelos do projeto (settings.json, risk.conf, CLAUDE.md). No texto de skill e agente,
  `${CLAUDE_PLUGIN_ROOT}` (o Claude Code troca pelo caminho); nos hooks e scripts, a pasta do próprio arquivo.
- **Referências ao documento de origem:** 39 arquivos citam seções "§" do documento de bootstrap, que não vem para o
  wstack. Cada citação vira o trecho que importa ou uma referência a documento do wstack.
- **Decisões datadas da origem:** 5 arquivos as citam (`session-start.sh`, `redirect-guard.mjs`,
  `protected-paths.mjs`, `path-guard.mjs`, `merge-por-risco.yml`). O porquê que sustenta uma trava vira decisão nova
  em `docs/decisions.md` deste repositório, com a evidência; a citação sai (senão apontaria para outra decisão do
  wstack).
- **Gotchas:** só a skill lead (o `worktree.baseRef`) e o `test-push-guard.sh` citam o arquivo de gotchas da origem;
  essas citações saem, e o porquê vira decisão do wstack quando sustentar uma trava. As outras citações de
  `docs/gotchas.md` (CLAUDE.md, verify-on-stop, pr-risk-gate, skills lead, refactoring, observability, concurrency,
  query-plan, security, recall) mandam o projeto escrever no próprio arquivo de gotchas: ficam.
- **Nomes do projeto de origem:** além dos três arquivos marcados acima, a conferência final é o grep da condição de
  parada.
- **Sondas:** as peças das sondas 1 e 2 (skills `sonda` e `sonda-caminhos`, `sonda-*` em hooks e scripts, o hook
  `session-start.sh` da sonda, as regras `allow` de teste do `.claude/settings.json` deste repositório) saem quando os
  hooks reais entrarem.

## Pendências

1. *(decidida: workflows baixam o wstack na versão fixada; ver `docs/decisions.md`)*
2. *(decidida: a versão fixada é a referência que o marketplace declara no `settings.json` do projeto; o
   `autoUpdate` atualiza dentro dela e o setup script da nuvem declara a mesma; conferir na 2.4)*
3. *(decidida: o arquivo de calibração entra na 2.4 como modelo do projeto)*
4. *(decididas: os conversores de stack vão para o plugin; a matriz de garantias vira docs do wstack; workflows e
   configuração de MCP ficam para depois da 0.1.0)*
5. *(decidida: a avaliação comportamental fica para depois da 0.1.0, no repositório wstack, entre portar estes
   scripts e usar o `claude plugin eval`)*

Todas as pendências estão decididas (`docs/decisions.md`, 2026-11-24, destinos do inventário).
