# Migração do harness para o plugin

Inventário da unidade 2.1: para onde vai cada arquivo do harness genérico (documento de bootstrap v2.16, 121 blocos
`<!-- arquivo: <caminho> -->`). Nada foi movido ainda; as unidades 2.2 a 2.4 fazem a mudança e esta tabela é a lista
de conferência delas.

Destinos:
- **plugin:** vai para `plugin/<pasta>/` e é igual em todo projeto. Hooks entram em `plugin/hooks/hooks.json`; scripts
  são chamados pelo caminho do plugin e aprovados pelo hook aprovador (`docs/decisions.md`, 2026-11-24, scripts no
  plugin).
- **modelo do projeto:** vira modelo em `plugin/templates/`, e o `/wstack:bootstrap` gera a cópia no projeto, que o
  projeto mantém.
- **fora:** não vai para o wstack.

Classe é a do harness de origem: `mirror` (o bloco é o arquivo), `template` (o bloco é a versão genérica de um arquivo
que tem dados do projeto de origem) ou `seed` (o projeto cria e mantém).

## Hooks

Todos para `plugin/hooks/`, na unidade 2.2. Os que hoje leem `"$CLAUDE_PROJECT_DIR"/.claude/...` para achar a si mesmos
ou a outro hook passam a usar a pasta do plugin; o que é do projeto (risk.conf, git, arquivos protegidos) continua vindo
de `$CLAUDE_PROJECT_DIR`.

| Arquivo | Classe | Destino | Evento | Ajuste |
|---|---|---|---|---|
| `.claude/hooks/checkpoint-tests.sh` | mirror | plugin | PreToolUse Bash, TaskCompleted | lê `checkpoint` do risk.conf do projeto |
| `.claude/hooks/closed-forms.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/cloud-services.sh` | mirror | plugin | SessionStart | lê `cloud_service`/`cloud_ready` do risk.conf do projeto |
| `.claude/hooks/dotnet-allow.mjs` | mirror | plugin | módulo | módulo de stack .NET, carregado por `allow_module = dotnet` |
| `.claude/hooks/dotnet-allow.sh` | mirror | plugin | (via path-guard) | idem |
| `.claude/hooks/edit-check.sh` | mirror | plugin | PostToolUse edição | lê as regras do risk.conf do projeto |
| `.claude/hooks/git-read-allow.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/git-read-allow.sh` | mirror | plugin | PreToolUse Bash | |
| `.claude/hooks/git-repo.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/iteration-guard.sh` | mirror | plugin | PostToolUse edição | |
| `.claude/hooks/notify.sh` | mirror | plugin | Notification | renomear as variáveis de ambiente que levam o nome do projeto de origem |
| `.claude/hooks/path-guard.mjs` | mirror | plugin | módulo | proteção revista: os hooks e scripts saem do projeto; protege o `settings.json` (com a versão fixada do plugin) e o `risk.conf` do projeto |
| `.claude/hooks/path-guard.sh` | mirror | plugin | PreToolUse Bash | idem |
| `.claude/hooks/protected-paths.mjs` | mirror | plugin | módulo | lista de caminhos protegidos revista como no path-guard |
| `.claude/hooks/push-guard.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/push-guard.sh` | mirror | plugin | PreToolUse Bash | |
| `.claude/hooks/redirect-guard.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/redirect-guard.sh` | mirror | plugin | PreToolUse Bash | |
| `.claude/hooks/risk-conf.mjs` | mirror | plugin | módulo | lê `$CLAUDE_PROJECT_DIR/.claude/risk.conf`, não a pasta `.claude` onde o arquivo está |
| `.claude/hooks/session-start.sh` | mirror | plugin | SessionStart | |
| `.claude/hooks/verify-on-stop.sh` | template | plugin | Stop | `SOLUTION`, `BUILD_CMD`, `LINT_CMD` e `TEST_CMD` saem do arquivo e viram chaves do risk.conf |
| `.claude/hooks/write-guard.mjs` | mirror | plugin | módulo | |
| `.claude/hooks/write-guard.sh` | mirror | plugin | PreToolUse edição | |
| `.claude/hooks/write-rule.mjs` | mirror | plugin | módulo | |

Novo na 2.2, sem bloco de origem: o hook aprovador dos scripts do plugin (PreToolUse Bash), com a lista de formas
exatas.

## Scripts

Para `plugin/scripts/`, na unidade 2.2, salvo os de teste (`plugin/tests/`) e os indicados. "Chamado por" diz onde o
caminho muda.

| Arquivo | Classe | Destino | Chamado por | Ajuste |
|---|---|---|---|---|
| `.claude/scripts/bdn-to-tsv.cs` | mirror | plugin | comando de desempenho do risk.conf | módulo de stack .NET |
| `.claude/scripts/bench-compare.sh` | mirror | plugin | skills lead, performance, review-rubric; agente performance-agent | |
| `.claude/scripts/bundle-size.sh` | mirror | plugin | comando de desempenho do risk.conf | módulo de frontend |
| `.claude/scripts/calibrate-risk.sh` | mirror | plugin | skill lead | |
| `.claude/scripts/check-findings.mjs` | mirror | plugin | skills lead, review-rubric; agentes de revisão | |
| `.claude/scripts/check-trajectory.mjs` | mirror | fora | só a matriz de garantias | avaliação comportamental do workflow; volta se ela for portada |
| `.claude/scripts/checkpoint.sh` | mirror | plugin | skill lead; path-guard, protected-paths, redirect-guard | |
| `.claude/scripts/classify-diff.sh` | mirror | plugin | skills lead, commit; agente lead; pr-risk-gate | |
| `.claude/scripts/compare-bench.sh` | mirror | plugin | bench-compare | |
| `.claude/scripts/compare-results.mjs` | mirror | fora | só a matriz de garantias | idem check-trajectory |
| `.claude/scripts/criterion-to-tsv.sh` | seed | modelo do projeto | comando de desempenho do risk.conf | ver pendência 3 |
| `.claude/scripts/diff-smells.mjs` | mirror | plugin | skills lead, clean-code; workflow gates | ver pendência 1 |
| `.claude/scripts/enviar-nuvem.sh` | mirror | plugin | skill lead | |
| `.claude/scripts/folded-top.sh` | seed | modelo do projeto | comando de desempenho do risk.conf | ver pendência 3 |
| `.claude/scripts/hot-methods.cs` | mirror | plugin | comando de desempenho do risk.conf | módulo de stack .NET |
| `.claude/scripts/map-staleness.mjs` | mirror | plugin | SessionStart | vira hook do plugin |
| `.claude/scripts/nova-atividade.sh` | mirror | plugin | skill lead | |
| `.claude/scripts/otlp-sink.mjs` | mirror | plugin | session-start, summarize-runs | |
| `.claude/scripts/permission-asks.mjs` | mirror | plugin | skill lead | |
| `.claude/scripts/pr-risk-gate.mjs` | mirror | plugin | workflow merge-por-risco | ver pendência 1 |
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
| `.claude/scripts/test-push-guard.sh` | template | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/test-redirect-guard.sh` | mirror | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/test-write-guard.sh` | mirror | plugin (`tests/`) | CI do wstack | |
| `.claude/scripts/validate-result.mjs` | mirror | fora | nenhum | idem check-trajectory |
| `.claude/scripts/worktree-env.sh` | mirror | plugin | skill lead; nova-atividade | |

## Nuvem

| Arquivo | Classe | Destino | Unidade | Ajuste |
|---|---|---|---|---|
| `.claude/cloud/setup.sh` | mirror | plugin | 2.2 | passa a instalar o plugin com `autoUpdate` (`docs/decisions.md`, 2026-11-24, plugin atualizado); trocar o exemplo de imagem que leva nome da stack do projeto de origem |
| `.claude/cloud/hosts.conf` | template | modelo do projeto | 2.4 | |

## Agentes

Todos para `plugin/agents/`, na unidade 2.3, com os caminhos de script trocados pelos do plugin. Os `template` vão na
versão genérica do bloco.

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
| `.claude/settings.json` | template | modelo do projeto | 2.4 | fica só com as permissões e o plugin fixado numa versão; a seção `hooks` vai para `plugin/hooks/hooks.json` (2.2) e as regras `allow` de `.claude/scripts/...` saem (o hook aprovador as substitui) |
| `.claude/risk.conf` | template | modelo do projeto | 2.4 | ganha as chaves de build, formato e teste do verify-on-stop |
| `CLAUDE.md` | template | modelo do projeto | 2.4 | |
| `.github/workflows/claude-review.yml` | template | modelo do projeto | ver pendência 2 | |
| `.github/workflows/gates.yml` | template | modelo do projeto | ver pendência 2 | roda o diff-smells (pendência 1) |
| `.github/workflows/merge-por-risco.yml` | mirror | modelo do projeto | ver pendência 2 | roda o pr-risk-gate (pendência 1) |
| `.mcp.json` | seed | modelo do projeto | ver pendência 2 | só para projeto com banco |
| `.claude/toolbox/tools.yaml` | seed | modelo do projeto | ver pendência 2 | idem |
| `docs/review-calibration.md` | seed | modelo do projeto | ver pendência 2 | é o arquivo de aprendizado que o verify-on-stop exige |
| `docs/harness-capabilities.md` | seed | modelo do projeto | ver pendência 4 | |

## Ajustes em todos os arquivos (2.2 e 2.3)

- **Caminhos:** `"$CLAUDE_PROJECT_DIR"/.claude/hooks/...` e `.claude/scripts/...` viram caminhos do plugin. No texto de
  skill e agente, `${CLAUDE_PLUGIN_ROOT}` (o Claude Code troca pelo caminho); nos hooks, a pasta do próprio arquivo.
- **Referências ao documento de origem:** 39 arquivos citam seções "§" do documento de bootstrap, que não vem para o
  wstack. Cada citação vira o trecho que importa ou uma referência a documento do wstack.
- **Decisões e gotchas datados:** 4 arquivos citam decisões datadas do projeto de origem (`redirect-guard.mjs`,
  `protected-paths.mjs`, `path-guard.mjs`, `merge-por-risco.yml`) e 11 citam o arquivo de gotchas dele. O porquê que
  sustenta uma trava vira decisão nova em `docs/decisions.md` deste repositório, com a evidência; a citação sai.
- **Nomes do projeto de origem:** além dos três arquivos marcados acima, a conferência final é o grep da condição de
  parada.
- **Sondas:** as peças das sondas 1 e 2 (skills `sonda` e `sonda-caminhos`, `sonda-*` em hooks e scripts, as regras
  `allow` de teste do `.claude/settings.json` deste repositório) saem quando os hooks reais entrarem.

## Pendências (decisão do desenvolvedor)

1. **Scripts que o GitHub Actions do projeto roda** (`pr-risk-gate.mjs`, `diff-smells.mjs`): o runner do CI não tem o
   plugin. Opções: o workflow baixa o wstack na versão fixada no `settings.json` do projeto; ou o bootstrap copia
   esses dois scripts para o projeto (exceção à decisão de scripts no plugin).
2. **Modelos fora da lista da 2.4:** a 2.4 cita risk.conf, CLAUDE.md, hosts.conf, settings.json e verify-<app>. Os
   três workflows, `.mcp.json`, `tools.yaml` e `docs/review-calibration.md` também são do projeto: entram na 2.4
   (perguntados pelo bootstrap quando não detectados) ou ficam para depois da 0.1.0.
3. **Seeds que são conversores de stack** (`criterion-to-tsv.sh`, `folded-top.sh`): pela regra, seed vira modelo do
   projeto; mas não têm dado do projeto, como os conversores .NET que vão para o plugin. Proposta: plugin.
4. **`docs/harness-capabilities.md`:** é a matriz de garantias dos hooks, que agora são do plugin. Proposta: documento
   do wstack (`docs/`), não modelo do projeto.
5. **Avaliação comportamental** (`check-trajectory.mjs`, `compare-results.mjs`, `validate-result.mjs`): marcada fora
   porque nada no fluxo os chama e os dados da avaliação não estão no documento. Volta se a avaliação for portada.
