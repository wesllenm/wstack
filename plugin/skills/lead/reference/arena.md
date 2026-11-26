# Arena de design

Lido pelo `lead` no planejamento de COMPLEXA ou CRITICA quando o plano tem uma decisão de design cara de reverter: modelagem de domínio (agregados, invariantes, estados), contrato público (API, payload de evento, schema de artefato) ou forma do dado persistido. Decisão que um experimento simples resolve, ou que se desfaz com um refactoring local, não vai para a arena.

A arena compara propostas independentes antes da aprovação única. Ela custa vários subagentes, então entra no plano como etapa, com o motivo, e não roda fora do planejamento.

1. **Pergunta e critérios antes das propostas.** Escrever a decisão como pergunta, as restrições (o que já existe e não muda) e os critérios com peso: invariantes a proteger, consumidores do contrato, evolução prevista, custo de migração, testabilidade. Critério escrito depois de ver as propostas tende a escolher a favorita.
2. **Duas ou três propostas em paralelo.** Um `planner` por proposta, no mesmo turno, todos com o mesmo pacote (pergunta, restrições, critérios, arquivos relevantes) e cada um com uma postura diferente, para não voltarem a mesma resposta:
   - a menor mudança que atende aos critérios;
   - o modelo mais seguro, que torna o estado inválido impossível (skill `domain-modeling`);
   - o ponto de vista de quem consome o contrato (skill `api-design` ou `event-driven`).

   Cada proposta volta neste formato: modelo ou contrato (tipos, assinaturas, payload); como atende a cada critério; o que fica difícil depois; riscos; o que só se decide rodando.
3. **Protótipo só para o que só se decide rodando.** Quando um critério depende de fato observável (desempenho, ergonomia do contrato num teste, plano de execução), até dois `implementer` com `isolation: worktree`, a partir do HEAD commitado, com sprint contract de protótipo descartável: só o esqueleto e um teste que exercita o critério (`delegacao.md`). Protótipo não é integrado; a worktree sai na limpeza.
4. **Divergência demais reenquadra.** Se as propostas respondem a perguntas diferentes (cada uma resolveu outro problema), a pergunta estava mal posta: reescrevê-la com as restrições que faltaram e rodar o passo 2 de novo, uma vez. Na segunda vez, segue com o que veio.
5. **Juiz independente.** Um `planner` novo, somente leitura, que não gerou nenhuma proposta, recebe a pergunta, os critérios com peso e as propostas (sem dizer qual postura gerou qual), pontua cada uma de 0 a 10 por critério com a evidência e recomenda uma.
6. **Pontuação do `lead`, sem ver a do juiz.** O `lead` monta a própria tabela critério × proposta, cada célula com a nota e a evidência (trecho da proposta, resultado do protótipo), e escolhe uma antes de abrir a do juiz.
7. **Comparar as duas.** Escolhas iguais: confirmada. Escolhas diferentes: o `lead` relê as propostas nos critérios em que as notas divergem e manda ao juiz a divergência para ele reler também; o plano mostra as duas tabelas, a divergência e a escolha final com o porquê. Combinar partes de propostas diferentes só quando elas protegem invariantes diferentes; a combinação é uma proposta nova e passa pelos critérios de novo, nas duas pontuações.
8. **Levar ao plano.** O plano apresenta as tabelas, a escolha e o porquê, e a aprovação única decide. A escolha aprovada vai para `docs/decisions.md` do projeto, com as alternativas descartadas e as duas notas (do `lead` e do juiz).

No relatório:

```text
Arena: <pergunta> — propostas: N (posturas) — reenquadrada: não | sim (motivo) — protótipos: N — juiz: <proposta> (nota) — lead: <proposta> (nota) — escolhida: <proposta> — critério decisivo
```
