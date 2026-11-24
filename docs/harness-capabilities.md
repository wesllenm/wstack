# Matriz de garantias do harness

O que cada mecanismo do plugin garante, o que não garante e o que prova isso. Estado: **VERIFICADO** (um teste do
wstack mostra o caso positivo e o negativo), **IMPLEMENTADO** (existe e roda, sem teste que mostre os dois lados),
**NÃO VERIFICADO** (depende do Claude Code real e não foi medido nesta versão). Os testes estão em `plugin/tests/` e
rodam no CI (`.github/workflows/ci.yml`); as provas `prove-*.sh` usam o Claude Code real e rodam à mão.

Versão 0.0.4: hooks e scripts. Skills, agentes e o bootstrap entram nas próximas versões.

| Mecanismo | Ativação | Garante | Não garante | Estado | Evidência |
|---|---|---|---|---|---|
| `write-guard.sh` | `PreToolUse` em Edit, Write, MultiEdit, NotebookEdit | a ferramenta de escrita não grava em `.git`, nas pastas git do projeto, na config do git nem na pasta do plugin (por qualquer caminho, link simbólico incluído) | escrita por Bash (é do path-guard e do redirect-guard) | VERIFICADO | `test-write-guard.sh`; `test-hook-commands.sh` (ausente, recusa) |
| `push-guard.sh` | `PreToolUse` em Bash | push só na forma exata, para branch de atividade do `risk.conf` (ou `ccr-`/`wip/`), nunca na branch padrão; pede aprovação se o push publica caminho protegido | push feito por script ou programa que não aparece no texto do comando | VERIFICADO | `test-push-guard.sh` |
| `checkpoint.sh` | skill lead (nuvem) | o checkpoint não publica caminho protegido, segredo nem ref existente | o gitleaks do CI (é uma rede grossa) | VERIFICADO | `test-push-guard.sh` |
| `path-guard.sh` | `PreToolUse` em Bash | pede aprovação para comando que cita trava (a pasta do plugin, pelo caminho dela, onde quer que esteja; `~/.claude/plugins`; `settings.json`, `risk.conf`, `.git`, `.gitignore`, workflows, `.mcp.json`) ou segredo, e para config que executa programa | comando que monta o caminho para esconder (ver Riscos aceitos); na nuvem, citação de trava é livre de propósito | VERIFICADO | `test-path-guard.sh` (inclui cada glob de Edit do `settings.json` modelo) |
| `redirect-guard.sh` | `PreToolUse` em Bash | pede aprovação para `>` em arquivo fora das formas fechadas | gravação sem redirecionamento (é do path-guard) | VERIFICADO | `test-redirect-guard.sh` |
| `git-read-allow.sh` | `PreToolUse` em Bash | aprova `git log/diff/show` só na forma fechada (sem `--output`) | — | VERIFICADO | `test-git-read-allow.sh` |
| `script-allow.sh` | `PreToolUse` em Bash | aprova os scripts do plugin só na forma fechada (interpretador, pasta real do plugin, argumentos de alfabeto fechado, raiz do projeto) | que o script chamado faça só o que deve (é do próprio script) | VERIFICADO | `test-script-allow.sh` (inclui a pasta do plugin por link simbólico, pela `CLAUDE_PLUGIN_ROOT`) |
| `dotnet-allow.mjs` | importado pelo path-guard com `allow_module = dotnet` | `dotnet build/test/restore/format/ef` livres só na forma fechada | — | VERIFICADO | `test-dotnet-allow.sh`; `test-path-guard.sh` (módulo ausente ou quebrado faz tudo pedir) |
| `risk-conf.mjs` | push-guard, protected-paths, path-guard (e `checkpoint.sh`, por eles) | o `risk.conf` lido é o do projeto (`$CLAUDE_PROJECT_DIR` ou raiz git), nunca um da pasta do plugin; sem ele, falha fechada onde ele afrouxaria | os outros hooks e scripts leem o arquivo por conta própria (sempre do projeto, `$CLAUDE_PROJECT_DIR` ou raiz git), sem teste que cubra cada um | VERIFICADO | `test-risk-conf.sh`; `test-push-guard.sh` |
| `verify-on-stop.sh` | `Stop` | não encerra com build, formato ou teste vermelho (comandos `verify_*` do `risk.conf`); com o arquivo de calibração, não encerra sem registro depois de commit de código | correção do código; que o Claude Code repita o Stop indefinidamente (o limite de bloqueios seguidos é dele) | VERIFICADO | `test-verify-on-stop.sh` |
| `checkpoint-tests.sh` | `PreToolUse` em `git commit`, `TaskCompleted` | commit não acontece com teste da área falhando | área sem regra `checkpoint`; commit escrito de forma que o padrão não reconhece | IMPLEMENTADO | `test-hook-commands.sh` (só ausente e presente sem commit) |
| `edit-check.sh` | `PostToolUse` em edição | lint e formatação do arquivo devolvidos ao Claude na hora | que a edição seja desfeita (o `PostToolUse` não bloqueia) | IMPLEMENTADO | — |
| `iteration-guard.sh` | `PostToolUse` em edição | entrega ao modelo a regra das três tentativas a cada N edições sem commit | obediência; edições por Bash e scripts | IMPLEMENTADO | — |
| `session-start.sh` | `SessionStart` | diz a versão do plugin em uso | — | VERIFICADO | `test-hook-commands.sh` |
| `session-start.sh` (registro) | `SessionStart` | registra o HEAD do início da sessão para o gate de aprendizado | — | IMPLEMENTADO | `test-verify-on-stop.sh` usa o arquivo, mas o cria à mão |
| `cloud/setup.sh` e `cloud-services.sh` | setup do ambiente; `SessionStart` na nuvem | ferramentas por stack detectada; nenhum texto do repositório vira comando nem chega ao contexto | o que o setup não detecta | VERIFICADO | `test-cloud-setup.sh` (modos sem rede) |
| `classify-diff.sh` | skills lead e commit | nível de risco pelos arquivos, tamanho e `risk.conf`; sem configuração, CRITICA | sinais fora de convenção de pasta e nome | VERIFICADO | `test-classify.sh` |
| `prune-merged.sh` | skill lead | apaga a branch local só quando o PR mesclado tem exatamente a ponta dela | — | VERIFICADO | `test-prune-merged.sh` |
| `permission-asks.mjs` | skill lead | conta os pedidos `ask` de hook de uma sessão | formato da transcrição (interno do Claude Code) | VERIFICADO | `test-permission-asks.sh` |
| ligação dos hooks | `plugin/hooks/hooks.json` | todo arquivo rodado existe; guarda ausente faz todo Bash pedir aprovação | — | VERIFICADO | `test-hook-commands.sh`; `test-plugin-paths.sh` (nada roda de `.claude/` do projeto) |
| Edit `ask` não vale para terminal | Claude Code nos modos automático e "Accept edits" | (fato do Claude Code que os guardas de Bash cobrem) | — | NÃO VERIFICADO | `prove-write-matrix.sh`, `prove-redirect-guard.sh` (à mão) |
| demais scripts (`review-dispatch`, `check-findings`, `diff-smells`, `quality-*`, `bench-*`, `sessions`, `nova-atividade`, `worktree-env`, `recall`, `map-staleness`, `summarize-runs`, `otlp-sink`, `enviar-nuvem`, `pr-risk-gate`, conversores) | skills e hooks | o que o cabeçalho de cada um descreve | — | IMPLEMENTADO | sem teste no wstack ainda |

## Riscos aceitos

- **Caminho montado para esconder.** Os guardas de Bash leem o texto do comando: um caminho montado em variável,
  quebrado por aspas no meio do nome ou gerado por outro programa não aparece como trava. O hook é cinto de
  segurança, não fronteira (`docs/decisions.md`, trava mínima nos comandos); a fronteira é o PR, o isolamento e o
  `deny`.
- **Comando que troca a árvore inteira sem citar a trava** (`git checkout <ref> -- .`, extração de arquivo
  compactado na raiz): muda arquivos protegidos sem citá-los. O push-guard e o `checkpoint.sh` conferem o que sai da
  máquina.
- **Repositório sem bootstrap.** O plugin instalado no escopo do usuário roda em todo repositório; o comportamento ali
  está pendente para a 2.4 (`docs/decisions.md`, gates do Stop configurados pelo projeto).
