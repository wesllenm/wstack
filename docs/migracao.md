# Migração do harness para o plugin

Inventário da unidade 2.1: para onde vai cada arquivo do harness genérico (121 arquivos). Nada foi movido ainda; as
unidades 2.2 a 2.4 fazem a mudança e esta tabela é a lista de conferência delas.

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
| `.claude/hooks/dotnet-allow.sh` | mirror | plugin | PreToolUse Bash, se registrado | hook próprio (o teste e a skill lead o tratam assim), mas não registrado no `settings.json` de origem; a 2.2 decide se entra no `hooks.json` |
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
versão genérica. A conferir na 2.3: o Claude Code pode ignorar campos do frontmatter em agentes de plugin
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
