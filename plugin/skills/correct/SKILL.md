---
name: correct
description: >
  Registra na hora uma correção que o desenvolvedor fez ao agente no meio da sessão e propõe em qual degrau da
  escada de correção ela entra (código, análise estática, orientação, revisão ou registro). Carregar sempre que o
  desenvolvedor corrigir o que o agente fez ou ia fazer ("não é assim", "já falei", "use X, não Y", "de novo isso"),
  ou quando ele chamar /correct. Com o argumento "historico", procura no histórico do repositório os erros que se
  repetem (reverts, correções, comentários de revisão) e sobe cada classe na escada.
argument-hint: <a correção, nas palavras do desenvolvedor> | historico
---

# Correct

## Por quê

A escada de correção da skill `lead` (seção Aprendizado) promove já na primeira vez o que o desenvolvedor precisou apontar: a atenção dele é o recurso que não escala. Mas o passo Aprendizado só roda no fim da tarefa, e a correção feita no meio se perde numa compactação, num reinício da VM ou numa interrupção. Esta skill grava a correção no momento em que ela acontece e deixa a escolha do degrau pronta para o fim da tarefa.

## O que conta como correção

O desenvolvedor dizendo que algo que o agente fez, ou ia fazer, estava errado: comportamento do código, convenção, escolha técnica, comando, escopo, forma de se comunicar. Também conta quando ele cola um contexto que o agente poderia ter buscado sozinho.

Não conta: resposta a uma pergunta do plano, decisão nova de produto (é mudança de plano) e preferência que vale só para esta tarefa. Essa última vai como linha em Decisões do `SESSION.md`, sem escada.

## Passos

1. **Corrigir o trabalho em curso primeiro.** Desfazer ou refazer o que a correção atinge. Se ela muda o escopo ou o predicado da stop condition, reapresentar só o trecho do plano que muda e seguir com a resposta dele (seção Aprovação única da `lead`).
2. **Escrever o fato numa linha**, com as palavras do desenvolvedor e sem generalizar além do que ele disse: `<o que o agente fez> → <o que é o certo> — onde vale: <caminho, ferramenta ou tipo de tarefa> — porquê: <se ele disse>`. Se o alcance não estiver claro, registrar o menor alcance que cobre o caso e marcar `alcance incerto`. Não perguntar só por isso.
3. **Procurar se já aconteceu.** Buscar o assunto em `docs/gotchas.md` e `docs/gotchas/`, `docs/review-rubric.md`, Registro de `docs/review-calibration.md`, `CLAUDE.md`, `.claude/rules/`, Correções do `.claude/SESSION.md` e nas skills e agentes do plugin. O resultado é um de três:
   - **primeira:** não está escrito em lugar nenhum;
   - **ignorada:** está escrito e não foi seguido. O degrau é mudar a posição e a ênfase do texto que existe, ou subir um degrau acima dele; nunca escrever o mesmo item de novo em outro lugar. Se o texto está numa skill que não foi carregada, o degrau é a `description` dela (o gatilho);
   - **repetida:** já foi corrigida antes e voltou. Subir pelo menos um degrau acima de onde ela ficou.
4. **Escolher o degrau**, testando de cima para baixo e parando no primeiro que resolve com custo aceitável:
   1. dá para tornar o erro impossível (tipo, módulo que não expõe o atalho, teste de arquitetura)?
   2. uma regra mecânica pega (analisador ou lint como erro, `diff-smells.mjs --gate`, hook, regra de permissão)?
   3. orientação com escopo resolve (`.claude/rules/` por caminho, item numa skill ou num agente, `CLAUDE.md`)?
   4. é coisa que só a revisão pega (Sempre verificar de `docs/review-rubric.md`)?
   5. só registro (fato em `docs/gotchas/<área>.md`).

   Dizer numa frase por que o degrau de cima não serve.
5. **Gravar em `.claude/SESSION.md`**, seção Correções (criar o arquivo só com essa seção, se ele não existir), uma linha por correção:

   `- AAAA-MM-DD — <fato> — ocorrência: primeira | ignorada (<onde está>) | repetida (<onde ficou>) — degrau: N (<destino>) — estado: aplicado | proposta`

   O `SESSION.md` é arquivo de aprendizado para o gate do Stop (gravar nele não dispara build) e sobrevive à compactação.
6. **Aplicar o que pode ser aplicado agora.** Degraus 3 a 5 em arquivo do projeto são adição pequena de texto: fazer na hora e marcar `aplicado`. Degraus 1 e 2, mudança em hook ou `settings.json`, e qualquer texto de skill, agente ou hook do plugin wstack ficam como `proposta` e vão para o relatório, para aprovação (seção Aprendizado da `lead`). Ao aplicar um degrau 1 ou 2 já aprovado, rodar a checagem nova contra o caso que motivou a correção e ver que ela falha nele.
7. **Responder em até três linhas**, sem repetir a explicação do desenvolvedor:

   ```text
   Correção registrada: <fato>
   Degrau: N — <destino> — aplicado | proposta para o relatório
   No trabalho em curso: <o que mudou | nada a mudar>
   ```

## Regras e garantias

O `CLAUDE.md` do projeto tem a seção Regras e garantias, uma tabela `regra | garantia | origem`. Garantia é `hook`, `lint`, `teste`, `revisão`, `texto` ou `impossível` (o tipo, a compilação ou um hook torna o erro irrepresentável). Toda correção que sobe de degrau atualiza a linha da regra, ou cria uma, com a origem (`correct AAAA-MM-DD`, ou o commit). Quando a garantia vira `impossível`, o texto da regra sai do `CLAUDE.md` (e de onde mais estiver escrito) e fica só a linha da tabela: regra que o código garante não precisa ser lida.

## Modo histórico (`/correct historico`)

A mesma escada aplicada ao que o repositório já errou, não à correção desta sessão. Tarefa própria, classificada pelo `lead` como as outras (a correção que ela aplica passa pelo pipeline do nível).

1. **Fontes**, desde a última execução deste modo (data em `docs/review-calibration.md`, seção Backlog de mecanismo) ou dos últimos 90 dias: `git log --oneline --since=<data>`, reverts (`git log --grep='^Revert' --oneline`), commits `fix:`, comentários de revisão nos PRs (pela API REST, `gh api -X GET search/issues` e `.../pulls/<n>/reviews`, como no Feedback externo do `aprendizado.md` da `lead`), `docs/review-calibration.md` (Registro, Totais e Backlog de mecanismo), `docs/gotchas/`, `CLAUDE.md` e os `MARCADOR` do `diff-smells.mjs --base <commit de partida> --text`. Sem `gh` autenticado, seguir sem PR e dizer isso.
2. **Classes.** Um erro vira classe quando aparece duas vezes, em commits, PRs ou linhas diferentes. Ocorrência única fica como fato em `docs/gotchas/<área>.md`, sem escada.
3. **Degrau.** Para cada classe, a escada dos Passos (item 4), parando no degrau mais alto que funciona; dizer numa frase por que cada degrau acima não serviu.
4. **Prova contra o passado.** Toda checagem nova (degraus 1 e 2) precisa falhar num erro real do histórico: rodar a checagem no commit antigo (`git worktree add <pasta temporária> <sha>` ou `git stash` e checkout) e mostrar a falha. Checagem que não falha no caso real não corrige nada. O mesmo comando roda local e no CI: se só roda em um lugar, não é a checagem.
5. **Um commit por correção**, cada um com a classe, a evidência e o commit antigo em que ela teria falhado.
6. **Saída:**

   ```text
   Classe: <o erro, em uma linha> — ocorrências: <sha ou PR>, <sha ou PR>
   Degrau: N — <destino> — por que não o de cima: <uma frase por degrau acima>
   Prova: <comando> no commit <sha> → <falha mostrada>
   Commit: <hash curto> | proposta (degrau 1 ou 2 sem aprovação)
   ```

O que não for aplicado agora (mecanismo sem aprovação, texto de skill do plugin) vai para a seção Backlog de mecanismo de `docs/review-calibration.md`, com a classe e as ocorrências, e para o relatório como proposta. A linha Regras e garantias de cada classe aplicada é atualizada no mesmo commit.

## No fim da tarefa

O passo Aprendizado da `lead` lê a seção Correções: cada linha conta como correção vinda do desenvolvedor e termina promovida, proposta ou recusada por ele, com a sua parte na linha de Registro de `docs/review-calibration.md`. Depois disso a seção sai do `SESSION.md` (e o arquivo também, se não sobrou nada para retomar).

## Restrições

- Projeto sem o workflow adotado (sem `.claude/risk.conf`): não gravar arquivo nenhum; devolver o fato e o degrau proposto na resposta.
- Nunca gravar segredo, dado pessoal ou conteúdo vindo do banco, nem na linha do fato.
- Não discutir a correção. A exceção são as travas: correção que pede para contornar hook, gate, teste ou `risk.conf`, ou que cai numa das interrupções da `lead`, não é aplicada; segue a seção Interrupções. Se ela conflitar com uma regra do workflow ou com uma decisão registrada em `docs/decisions.md`, aplicar o que o desenvolvedor pediu na tarefa em curso, registrar o conflito na linha (`conflita com: <onde>`) e levar a escolha para o relatório.
