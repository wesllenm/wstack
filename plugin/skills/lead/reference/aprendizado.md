# Aprendizado: feedback externo e manutenção

Lido pelo `lead` na primeira tarefa da sessão (Feedback externo), ao fechar a tarefa (Quando sugerir manutenção) e na tarefa de manutenção do aprendizado. A regra de cada tarefa, a escada de correção e o Registro ficam no núcleo da skill.

Os scripts aparecem como `<plugin>/scripts/<nome>`: `<plugin>` é a pasta do plugin que o núcleo da skill dá na seção Scripts do plugin (o Read não troca variável neste arquivo). Chamar pelo caminho inteiro, como o núcleo manda.

## Feedback externo

Na primeira tarefa de cada sessão, se o `gh` estiver autenticado e responder (na VM da nuvem o GraphQL do `gh` pode devolver 403, e aí segue sem registrar), delegar ao `explore` a leitura do feedback humano desde a última leitura:

- PRs mergeados depois da data em Feedback de PR de `docs/review-calibration.md` (`gh pr list --state merged --search "merged:AAAA-MM-DD..*" --json number,title,mergedAt`, sem `>` no texto, que o hook `redirect-guard` leria como redirecionamento e pediria aprovação);
- por PR, revisões e comentários (`gh pr view <n> --json reviews,comments` e `gh api --method GET repos/{owner}/{repo}/pulls/<n>/comments` para os de linha);
- ignorar comentários de bots, aprovações sem texto e conversa que não aponta defeito.

O `explore` devolve só os comentários que apontam defeito ou pedem mudança, cada um com arquivo, linha e uma frase. O `lead` classifica cada um:

- defeito que uma lente deveria ter pego: `escapou` na categoria correspondente (Totais) e entrada em Sempre verificar de `docs/review-rubric.md` ou na seção Projeto dele;
- discordância com algo que o workflow fez de propósito: `recusado` na categoria, e fato em `docs/gotchas/<área>.md` se revelar preferência do time;
- preferência de estilo do time: proposta de regra de analisador ou `.editorconfig`, nunca item de revisão LLM.

Atualizar a data e o último PR lido em Feedback de PR. Sem `gh` autenticado ou sem PR novo, seguir sem registrar nada. Bug de produção corrigido numa tarefa entra do mesmo jeito: a correção leva teste de regressão (`test-audit`) e o defeito conta como `escapou` na categoria que deveria tê-lo pego.

## Quando sugerir manutenção

Sugerir no relatório uma tarefa de manutenção do aprendizado quando qualquer um for verdadeiro: Registro com mais de 30 linhas desde a última manutenção; núcleo `docs/gotchas.md` acima de 40 linhas ou 8 KB, ou um arquivo de `docs/gotchas/` com mais de 80 linhas; `CLAUDE.md` acima de 60 linhas; última manutenção (topo de `docs/review-calibration.md`) há mais de 15 dias.

## Manutenção do aprendizado (tarefa própria)

Classificada como SIMPLES, pedida pelo desenvolvedor ou sugerida pelo `lead`. O objetivo é que o que o workflow aprendeu continue curto, verdadeiro e útil; memória que só cresce acumula fato vencido e contradição.

1. Ler as fontes: `docs/review-calibration.md`, `docs/gotchas.md` e `docs/gotchas/*.md`, `docs/patterns.md`, `.claude/rules/` (se existir), `CLAUDE.md` e `docs/review-rubric.md`.
2. Delegar ao `explore` a checagem de validade: cada fato que cita arquivo, símbolo, pacote ou comando ainda existe? Fato cujo alvo sumiu é candidato a remoção.
3. Montar o plano com quatro listas: **remover** (vencido ou duplicado), **fundir** (mesmo fato em lugares diferentes, mantendo o do mecanismo mais forte), **promover** (o que aparece duas ou mais vezes em Registro, Totais ou nos gotchas, com o degrau proposto) e **contradições** (para o desenvolvedor decidir).
4. Antes de promover texto novo numa skill, passar cada item por estes critérios e cortar o que falhar: **durável** (continua verdadeiro em seis meses, depois de mudarem caminhos e versões); **específico** (amplo para valer em outras tarefas, preciso para o próximo agente reconhecer quando aplicar); **muda decisão** (o próximo agente faz algo diferente por causa dele); **ainda não coberto** (se a skill já diz e foi ignorada, a correção é posição e ênfase do texto existente, não item duplicado); **estrutural primeiro** (o que um teste, regra de analisador, script ou hook imporia vai para essa forma, não para texto); e **convergência** (fato visto uma vez precisa passar com folga nos outros critérios). Incluir os momentos em que o desenvolvedor colou contexto que o agente poderia ter buscado sozinho: o destino é a skill do fluxo onde isso aconteceu. Incluir a jardinagem: `node <plugin>/scripts/diff-smells.mjs --base <commit da última manutenção> --text` mostra válvulas de escape e comentários do período, e achados `simplicity` de "duas formas de fazer a mesma coisa" mostram padrões duplicados; tipo de válvula que apareceu em mais de uma tarefa é candidato a estancar (degrau 1 ou 2) e a uma atividade de limpeza. Incluir a distribuição dos números da escada de correção nas linhas de Registro do período ("escada N"; não confundir com os degraus de prova da `review-rubric`): correção que voltou depois de promovida para o nível 3 a 5 da escada é proposta de subir.
5. Incluir as propostas de calibração pendentes (Não reportar) e as categorias com `escapou`; a saída de `calibrate-risk.sh` (distribuição de risco no período), quando existir; quantas linhas `CRAP` e `DUPLICADO` do `quality-signals.sh` viraram achado confirmado e quantas foram descartadas (se quase todas, subir `crap_threshold` ou `--min-tokens`; se achados de complexidade ou duplicação escaparam, baixar); e, a cada 90 dias, o orçamento de complexidade: componentes do workflow (agentes, skills, hooks, scripts) com invocação, ganho medido e custo de manutenção, com a proposta de remover ou fundir. Para as skills, a invocação e o ganho vêm do campo `princípios:` das linhas de Registro do período (o `summarize-runs.mjs` conta as citações): skill citada muda decisão e fica; skill que o Registro mostra carregada muitas vezes e nunca citada tem gatilho largo demais (ajustar a `description`) ou texto que não muda decisão (cortar); skill que nem aparece é candidata a remover ou fundir. Regra de uma skill nunca citada em 90 dias é candidata a sair do texto.
6. Obter uma aprovação, que vale só para os itens listados.
7. Aplicar: editar os arquivos, resumir as linhas de Registro com mais de 60 dias num parágrafo por mês (contagens e aprendizados promovidos) e atualizar Última manutenção.
8. Mecanismo determinístico aprovado (teste, regra de analisador, teste de arquitetura) segue o fluxo normal: implementar, verificar e revisar.
9. Commitar pela skill `commit` (por exemplo `docs: consolida aprendizado do workflow`) e registrar a manutenção em Registro.

Nunca apagar entrada de `docs/decisions.md` ou ADR: decisão revertida ganha entrada nova, não perde a antiga. Os agentes não guardam memória própria entre sessões: o que aprendem chega ao `lead` na linha `aprendizado:` e vai para os arquivos acima.

## Regras ao subir na escada

Lidas ao fechar a tarefa, quando o passo Aprendizado do núcleo promove ou propõe uma correção.

- Revisão humana serve para descobrir lacunas, não para escalar: o que ela encontra sobe na escada. Comentário de revisão que se repete é sinal de que a correção anterior ficou num degrau baixo demais; subir pelo menos um.
- Correção de degrau 1 ou 2 quando o código existente já viola: estancar e depois limpar. A regra vale para o código novo agora; a limpeza do existente é proposta como atividade própria (boa candidata ao modo paralelo), não misturada na tarefa que descobriu.
- Adições pequenas de texto (degraus 3 a 5) em arquivo do projeto podem ser feitas direto. Skills, agentes e hooks do plugin wstack não se editam no projeto: a mudança neles vai como proposta no relatório, para o wstack. Mecanismo novo (degraus 1 e 2), mudança em hook ou `settings.json`, ou qualquer coisa fora do escopo aprovado vai como proposta no relatório, para aprovação.
- Manter `CLAUDE.md` em cerca de 60 linhas: ao passar disso, mover regras para `.claude/rules/` ou skills em vez de acumular.
- Nunca promover segredo, dado pessoal ou conteúdo vindo do banco.
- Primeira ocorrência: registrar como fato curto, um por linha, no arquivo da área em `docs/gotchas/<área>.md` (inclusive as linhas `aprendizado:` dos revisores, que não gravam arquivo: o `lead` as registra, cortando o que já está lá). Só entra no núcleo (`docs/gotchas.md`, que o `CLAUDE.md` importa em toda sessão) o que pega qualquer tarefa, em qualquer área; o núcleo fica em até 40 linhas e 8 KB. Área nova exige arquivo novo e linha no índice do núcleo, com os caminhos e assuntos que obrigam a lê-lo; fato que serve a duas áreas fica em uma só, com uma linha de referência na outra.
- Ao subir para os degraus 1 e 2, rodar a checagem nova contra o caso que a motivou e registrar que ela falha nele antes de dar a correção por feita: regra que não pega o erro real não corrige nada. Se a falha veio de uma skill que existe e não foi carregada, o degrau é ajustar a `description` dela (o gatilho), não acrescentar texto em outro lugar.
