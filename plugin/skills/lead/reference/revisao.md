# Revisão: etapas, adiamento e calibração

Lido pelo `lead` antes de chamar o primeiro revisor de uma tarefa (inclusive TRIVIAL com código), ao triar achados e ao triar a revisão de um PR. Níveis, duas velocidades e critérios do `review-critical` ficam no núcleo da skill (`SKILL.md`, seções Classificação, Roteamento e Revisão).

Os scripts aparecem como `<plugin>/scripts/<nome>`: `<plugin>` é a pasta do plugin que o núcleo da skill dá na seção Scripts do plugin (o Read não troca variável neste arquivo). Chamar pelo caminho inteiro, como o núcleo manda.

## Adiamento controlado do caminho pesado

`SKIP_HEAVY_REVIEW=1` é uma opção temporária por processo/sessão para **não iniciar** o caminho pesado local em SIMPLES e COMPLEXA. Não desativa o caminho rápido, build, formato, testes, classificação, gates de segurança nem a revisão CRITICA. Não é permissão para descartar achados.

- O `lead` verifica a variável antes de iniciar os subagentes pesados. Se estiver em `1`, não os inicia e registra em `.claude/SESSION.md` uma pendência estruturada: tarefa, classificação, commit ou diff abrangido, lentes adiadas, motivo (`SKIP_HEAVY_REVIEW`) e destino previsto (próxima sessão; PR e Actions só se um dia houver workflow que rode o caminho pesado). O relatório final diz explicitamente `revisão pesada pendente`.
- Sem esse workflow, a pendência é retomada na próxima sessão (Início, passo 3), antes de declarar a revisão concluída. Se um dia existir um workflow de revisão no PR, ele deve postar comentário `review-verifier: aplicado` com o HEAD SHA revisado, e o `lead` só fecha a pendência após conferir que o SHA corresponde e que não há achado bloqueante sem triagem.
- A variável não é persistida em `settings.json`, `risk.conf` nem no repositório: é definida pelo desenvolvedor ao iniciar a sessão (Git Bash: `SKIP_HEAVY_REVIEW=1 claude`; PowerShell: `$env:SKIP_HEAVY_REVIEW="1"; claude`, e `Remove-Item Env:SKIP_HEAVY_REVIEW` para voltar ao padrão). Ausência ou valor diferente de `1` mantém o comportamento padrão.
- A variável só impede o início. Para uma execução já iniciada, usar o mecanismo nativo de cancelamento de tarefas do Claude Code; não matar processos por PID presumido nem apagar logs ou pendências.
- Se a classificação subir para CRITICA, ignorar a variável e executar a revisão obrigatória na sessão, antes do commit.

Quando o caminho pesado volta depois do commit, o `lead` tria os achados como na etapa 3 e, se houver correção, ela entra num commit próprio (`fix: achados da revisão`). Se o turno terminar antes de ele voltar, o `lead` registra o pendente em `.claude/SESSION.md`. Nenhum achado se perde por chegar tarde: ele só muda de lugar. Em SIMPLES e COMPLEXA o caminho pesado só deixa de rodar por adiamento explícito e rastreável; em TRIVIAL ele não roda.

## 1. Preparar

Em toda alteração de código, inclusive TRIVIAL, rodar `node <plugin>/scripts/diff-smells.mjs --text` e tratar a saída antes de chamar qualquer revisor: `CODIGO_COMENTADO` e `MARCADOR` saem (o marcador vira follow-up no relatório), comentário que só narra o código sai, e válvula de escape (`ESCAPE`) acima do limite é sinal de desenho: antes de remendar, perguntar por que o tipo ou o fluxo pediu a válvula, e se a resposta é o desenho, voltar ao plano daquela parte. Duas válvulas do mesmo tipo na mesma tarefa contam como premissa refutada (seção Interrupções do núcleo). O que sobrar (comentário de porquê, válvula justificada) vai no pacote das lentes.

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
- o **despacho**: `node <plugin>/scripts/review-dispatch.mjs` (diff da tarefa em curso; `--commit <sha>` para tarefa já commitada; `--text` para ler). Ele exclui o que não vai a revisor LLM (removido, binário, gerado, lockfile, `review_exclude`), indica por arquivo a referência da stack e a regra por caminho (`review_rule`) e agrupa os arquivos. Falha do script (código 3) não derruba a revisão: seguir com o diff inteiro e registrar o motivo no relatório.

Nunca enviar a justificativa do implementer, só código, contrato e evidências.

## 2. Achar (lentes em paralelo)

Disparar no mesmo turno, cada lente com o mesmo pacote. Com `mode: single` do despacho, é um grupo só. Com `mode: grouped`, disparar a lente **uma vez por grupo**, em paralelo, passando só os arquivos do grupo (campo `files`), a lista `other_changed` como contexto, o `path_rules` (lista) de cada arquivo e a instrução de ler o arquivo indicado. Os candidatos de todos os grupos são juntados antes da Verificação. Os especialistas (`security-agent`, `database-reviewer`, etc.) recebem o diff inteiro dos arquivos da sua área, sem agrupamento:

- `review-agent`: sempre (caminho rápido);
- `review-simplicity`: sempre em nível não TRIVIAL (caminho pesado);
- `review-failures`: quando o diff adiciona ou altera `catch`, retry, fallback, timeout, tratamento de resultado de integração, consumo de mensagem ou log de erro;
- `review-domain`: quando o diff adiciona ou altera entidade, value object, agregado, enum de estado, regra de negócio ou tipo público;
- `security-agent`, `database-reviewer`, `e2e-critical-review` e `performance-agent` conforme o Roteamento (`database-reviewer` no rápido quando a `query-plan` sinalizar **bloqueia**);
- **interrogatório por outro fornecedor**, em COMPLEXA e CRITICA, no caminho pesado (na CRITICA, na sessão), quando o `risk.conf` tiver `interrogate_cmd`: gravar o pacote (diff dos arquivos que o despacho manda a revisor, contrato e pontos de foco, sem a justificativa do implementer) num arquivo da pasta temporária e rodar `node <plugin>/scripts/interrogate.mjs <pacote> <saída>`. Cada modelo configurado tenta quebrar o diff e devolve candidatos no formato da `review-rubric`, com o id prefixado pelo nome dele; os candidatos entram na Verificação com os das lentes. Código 10 (não configurado): registrar `interrogate: não configurado` e seguir. Código 3: usar o que veio e registrar o modelo que falhou e o motivo (stderr). O pacote sai da máquina para o fornecedor: nunca incluir arquivo que o despacho excluiu.

Na dúvida se uma lente condicional se aplica, disparar. Cada lente devolve candidatos no formato da `review-rubric` ou exatamente `sem achados`.

## 3. Verificar

Juntar os candidatos de todas as lentes e grupos, incluindo `review-critical` e `security-agent`, e **ancorá-los antes do verificador**: gravar a lista num arquivo da pasta temporária da sessão e rodar `node <plugin>/scripts/check-findings.mjs <arquivo>` (com `--rev <commit>` se a tarefa já foi commitada). O script descarta o candidato cujo trecho não existe no arquivo (achado alucinado) ou que não traz trecho, e corrige o `local` do deslocado. Contar os descartados por lente (o interrogatório conta por modelo) e citá-los na linha do Registro de `docs/review-calibration.md` ("ancoragem descartou N"); lente que descarta muito precisa de prompt mais curto, não de mais achados. Só o que sobra vai ao `review-verifier`, com o diff e o contrato. Se o script falhar (código 2 ou 3), enviar os candidatos sem ancoragem e registrar. Os achados do `database-reviewer` já exigem evidência do plano e link oficial (`query-plan`) e não passam pelo verificador.

O verificador devolve `confirmado`, `plausível` ou `refutado`, sem duplicatas e com a severidade final. Triagem pelo `lead`:

- `confirmado` bloqueante ou importante: corrigir dentro do escopo;
- `confirmado` nit: corrigir se for barato e dentro do escopo; senão follow-up;
- `plausível` bloqueante ou importante: provar com um teste que falha (gate de autoria da `test-audit`); se falhar, corrigir; se não falhar, descartar; se não der para provar, acionar o `review-critical`;
- `plausível` nit e `refutado`: descartar;
- `preexistente`: nunca corrigir na tarefa; follow-up no relatório;
- achado que exige decisão nova de produto, arquitetura ou escopo: interromper.

Em CRITICA, executar a prova do fato de segurança devolvida pelo `review-critical` antes do commit: um teste novo passa pelo gate de autoria da `test-audit`; uma condução usa a skill `verify-<app>` do projeto. O relatório traz o fato, o degrau de prova alcançado (`review-rubric`, Degraus de prova) e a evidência. Fato abaixo do degrau 4 sai como `não provado` e o commit espera a decisão do desenvolvedor.

## 4. Corrigir e revisar o delta

- Correções de simplicidade confirmadas: aplicar direto ou delegar ao `simplify` quando forem três ou mais.
- Depois das correções, rodar de novo só as lentes que tiveram achado confirmado, sobre o delta, e o verificador sobre os novos candidatos.
- Máximo de duas rodadas de correção; se restar bloqueante confirmado depois da segunda, interromper com o estado e os achados.
- Rodada de correção delegada vai para um subagente novo, com o contrato original, o relatório da rodada anterior e os achados confirmados; retomar o mesmo `implementer` só quando o estado dele (worktree com mudança não commitada) for caro de mover. Quem escreveu tende a defender o próprio código.
- Cada achado termina com um destino: `corrigido`, `recusado` (com motivo) ou `não aplicável`; esse registro vai para o relatório.

## Calibração

Ao fim da tarefa, somar os achados desta revisão na tabela Totais de `docs/review-calibration.md` (`categoria — confirmados — refutados — recusados — escaparam`). Recusa do desenvolvedor no relatório ou em revisão de PR conta como recusado; defeito que chegou ao PR, a outro revisor, a teste futuro ou a produção sem ter sido apontado conta como escapou (`aprendizado.md`, Feedback externo). A linha da tarefa em Registro é escrita no passo Aprendizado.

- Categoria com dois ou mais refutados ou recusados e nenhum confirmado: propor no relatório a inclusão em Não reportar de `docs/review-rubric.md` (afrouxar a revisão é sempre proposta, nunca edição direta).
- Achado confirmado que se repete em tarefas diferentes: segue a escada da seção Aprendizado do núcleo; o primeiro degrau é tentar torná-lo determinístico (regra de analisador ou teste de arquitetura). Incluir em Sempre verificar de `docs/review-rubric.md` pode ser feito direto.
- Categoria com escapou: é o sinal mais forte. Na primeira ocorrência, incluir o padrão em Sempre verificar de `docs/review-rubric.md` (ou em Projeto, se específico do repositório); na segunda, seguir a escada até o mecanismo determinístico.

## Triagem de achados do PR

Só se aplica quando existir um workflow de revisão no PR com achados (como um workflow de revisão por Claude no GitHub Actions). Nesse caso os achados chegam como um comentário no formato da `review-rubric`, e triar é uma tarefa própria, pedida como "triar a revisão do PR N": o `lead` lê o comentário pelo `gh`, passa os candidatos pelo `review-verifier` se o comentário disser que ainda não passaram, aplica a triagem do passo 3 e commita as correções na branch do PR. Classificar pelo diff do PR, como qualquer tarefa.

## Revisão nativa como segunda opinião

Quando o nível for CRITICA e a entrega for virar PR, sugerir no relatório que o desenvolvedor rode `/code-review ultra` antes de abrir o PR. É uma revisão em nuvem, com pipeline de verificação próprio e custo à parte, então fica como sugestão, não como etapa automática. O `/code-review` nativo segue o `CLAUDE.md`, não a `review-rubric`; por isso as regras de Qualidade do `CLAUDE.md` precisam continuar curtas e explícitas.

## Versão revisada

O veredito da revisão vale para uma versão do código (orientação; nenhum hook confere): o pacote de revisão leva o SHA base da unidade (o HEAD) e a impressão da árvore de trabalho, o hash de árvore calculado num índice temporário (`idx=$(mktemp) && cp "$(git rev-parse --git-path index)" "$idx" && GIT_INDEX_FILE="$idx" git add -A && GIT_INDEX_FILE="$idx" git write-tree; rc=$?; rm -f "$idx"; [ "$rc" = 0 ]`: cobre binário e arquivo novo, respeita o `.gitignore`, não mexe no índice real e funciona em worktree, onde `.git` é arquivo; saída vazia ou código diferente de 0 é falha, nunca impressão); antes do primeiro commit da unidade, conferir que o HEAD ainda é o SHA base e recalcular a impressão. Se mudou, o que mudou é delta e passa pela revisão do delta (etapa 4 acima). Entre os commits de uma mesma unidade nada é editado.
