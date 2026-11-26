# Limpeza

Lido pelo `lead` antes de criar recurso fora do diff (pasta temporária, worktree, container, saída de build) e antes de declarar a entrega ou interromper. O inventário do estado inicial é feito no Início (núcleo da skill).

Os scripts aparecem como `<plugin>/scripts/<nome>`: `<plugin>` é a pasta do plugin que o núcleo da skill dá na seção Scripts do plugin (o Read não troca variável neste arquivo). Chamar pelo caminho inteiro, como o núcleo manda.

Resto deixado por agente se acumula rápido, ocupa disco e confunde o desenvolvedor sobre o que é dele. A regra é: devolver o ambiente como encontrou, menos o que vai para o commit.

## Estado inicial

Antes de criar qualquer coisa, registrar o que já existe, para depois saber o que é seu:

- `git status --porcelain` (não rastreados e modificados);
- `git worktree list`, `git branch --list` e `git stash list`;
- `docker ps --format '{{.Names}}'`, quando o projeto usa Docker.

Guardar esse inventário no contexto da tarefa e copiá-lo para `.claude/SESSION.md` se houver handoff; sem ele, a sessão seguinte não sabe distinguir o que é do agente.

## Durante a tarefa

- **Pasta temporária da sessão**: criar uma só, fora do repositório, com `mktemp -d "${TMPDIR:-/tmp}/claude-<projeto>-XXXX"` (no Git Bash do Windows isso cai em `%TEMP%`). PDF e DOCX de conferência, binlogs, `TestResults/` redirecionados (`--results-directory`), screenshots, dumps de log e scripts avulsos vão para lá. O prefixo `claude-` permite achar sobras de sessões antigas.
- Se a ferramenta só gerar dentro do repositório (por exemplo `TestResults/` ou `StrykerOutput/`), anotar o caminho como criado por você e apagar ao terminar, salvo se já existia no estado inicial.
- **Builds**: não fazer publish de teste, cópia de `bin/` ou build de conferência no repositório; se precisar, usar `-o <pasta temporária>`. Não rodar `dotnet clean` nem apagar `bin/`, `obj/`, `node_modules/` ou equivalentes do desenvolvedor sem pedir.
- **Containers**: se o desenvolvedor já tem a stack rodando (estado inicial), usar a dele e não derrubá-la. Containers que um orquestrador local iniciou por você (Aspire, compose do projeto) são encerrados parando o orquestrador pela forma que a skill `verify-<app>` do projeto documenta (o AppHost do Aspire em segundo plano ignora SIGINT e precisa de `kill -TERM` no PID dele); Testcontainers se removem sozinhos (Ryuk) — conferir sobras em `docker ps`. Se precisar subir compose próprio, usar `docker compose -p claude-<tarefa> up -d`; imagens que você construir levam tag com o mesmo prefixo.
- **Redirecionamento**: no Bash, `/dev/null`; no PowerShell, `$null`. Nunca `> nul` no Git Bash: cria um arquivo `nul` na raiz que o Windows mal consegue apagar.

## Antes de declarar a entrega

Rodar `git status` e `git worktree list`, comparar com o estado inicial e:

1. **Worktrees** criadas por você (em `.claude/worktrees/`, `%TEMP%` ou outro lugar), **exceto a worktree de uma atividade do Modo paralelo assistido** (`nova-atividade.sh` ou `claude -w`), que é a casa de outra sessão até o merge: `git worktree remove <caminho>` (sem `--force`, que é `deny`) e depois `git worktree prune`; essas formas não estão em `allow` e passam pelo classificador do modo automático. Branch local temporária não integrada, worktree com trabalho não commitado e qualquer coisa que só saia com `--force` ou `-D` (também `-d -f`) **não são removidas pelo agente**: liste caminho, motivo e o comando no relatório para o desenvolvedor executar. A exceção é a branch mesclada (abaixo).
2. **Saídas e scripts** que você gerou no repositório e não vão para o commit: apagar.
3. **Containers**: `docker compose -p claude-<tarefa> down` (sem `-v`: apagar volume é `deny`, assim como `docker volume rm`); os volumes que você criou ficam **listados no relatório, com o comando**, para o desenvolvedor remover (volume de devcontainer ou de cache é dele); remover as imagens com o seu prefixo (`claude-*`); parar o orquestrador que você iniciou. Se o cache de build do Docker estiver grande (`docker system df`), sugerir `docker builder prune` ao desenvolvedor, sem rodar.
4. **Pasta temporária da sessão**: apagar, salvo arquivos que o desenvolvedor precise conferir; nesse caso informar o caminho. Ela inclui as pastas de protótipo (`playbooks/prototipo.md`) e a instrumentação temporária do diagnóstico de runtime (`playbooks/diagnostico-runtime.md`): protótipo e instrumentação nunca ficam no repositório nem no branch da feature; se algum foi parar lá, sai aqui.
5. **Arquivo `nul`** na raiz, se você o criou: remover com `rm ./nul`.

Só apague o que você criou nesta sessão. Arquivos não rastreados, stashes, branches, worktrees, containers e volumes que já existiam no estado inicial são do desenvolvedor: liste no relatório e pergunte antes de remover qualquer um. Na dúvida sobre a origem, trate como do desenvolvedor.

Fazer a limpeza também ao interromper por bloqueio, preservando apenas o que for necessário para retomar (e dizendo o que ficou).

## Branch mesclada

Quando o desenvolvedor avisa o merge do PR, ou no Início, `bash <plugin>/scripts/prune-merged.sh <branch>` (ou `--all`) apaga a branch local sem pedir: só apaga quando o GitHub mostra um PR mesclado da branch cujo commit recebido é a ponta local, e mantém a main e a branch em uso em qualquer worktree, inclusive em rebase ou bisect (troque para a `main` atualizada antes). Branch que ele mantém continua sendo do desenvolvedor; `git branch -D` segue no `deny`.
