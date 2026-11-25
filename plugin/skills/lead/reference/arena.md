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
4. **Comparar.** Uma tabela critério × proposta, cada célula com a evidência (trecho da proposta, resultado do protótipo). Escolher uma. Combinar partes de propostas diferentes só quando elas tocam invariantes diferentes; a combinação é uma proposta nova e passa pelos critérios de novo.
5. **Levar ao plano.** O plano apresenta a tabela, a escolha e o porquê, e a aprovação única decide. A escolha aprovada vai para `docs/decisions.md` do projeto, com as alternativas descartadas.

No relatório:

```text
Arena: <pergunta> — propostas: N (posturas) — protótipos: N — escolhida: <proposta> — critério decisivo
```
