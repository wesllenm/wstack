# Playbook: performance

Para pedido de deixar algo mais rápido, mais leve ou mais barato (latência, throughput, memória, alocação, CPU, tamanho do bundle, custo de tokens), ou para regressão de performance relatada. Achado de benchmark que aparece na revisão de outra tarefa não é este playbook: é triado pela revisão (`revisao.md`).

As ferramentas de cada camada estão na skill `performance` e na referência da stack dela. Carregar a skill antes do passo 2.

1. **Métrica e alvo antes de tudo.** O que se mede (p95 de um endpoint, alocação por operação, comandos de banco por requisição, KB comprimidos, tokens por chamada), em que escala e quanto basta. Sem alvo dado pelo desenvolvedor, o plano propõe um, e a aprovação única decide. "Mais rápido" sem número não é stop condition.
2. **Linha de base no código intocado**, com a camada certa da `performance`: contagem nos testes, `bench-compare.sh`, perfil de CPU, suíte instrumentada ou profiling sob demanda. Rodar mais de uma vez para saber o ruído. Gravar comando, números, ruído e SHA.
3. **Achar onde está o custo** com medição, não com intuição: perfil de CPU, plano de execução no banco real (`query-plan` pelo `database-helper`), contagem de chamadas. Quando a origem não for óbvia, delegar ao `performance-agent`.
4. **Planejar uma mudança por hipótese**, na ordem do maior custo medido. A stop condition é o alvo do passo 1 atingido na mesma medição do passo 2.
5. **Mudar uma coisa de cada vez e medir de novo** com o mesmo comando. Mudança sem ganho acima do ruído é revertida, mesmo que pareça melhor. Mudança que troca legibilidade ou correção por ganho pequeno vai ao relatório para o desenvolvedor decidir.
6. **Prender o ganho.** Teste de contagem ou orçamento no benchmark (camadas 2 e 3 da `performance`) que falharia se a regressão voltasse. É o degrau 1 ou 2 da escada contra a próxima regressão.
7. **Testes de comportamento verdes e revisão** pelo nível (seção Revisão do núcleo).

**Subida iterativa (hillclimb).** Quando o alvo pede várias tentativas, os passos 2 a 6 viram um laço com estas regras:
- **Medição congelada.** Antes da primeira tentativa, conferir que a medição separa as cargas que importam (rodar com a carga pequena e a grande e ver números diferentes acima do ruído), congelar o comando e a carga, e registrar a linha de base e um gate de regressão verde (os testes de comportamento e os de contagem). A medição não muda no meio do laço; se precisar mudar, a linha de base é refeita.
- **Log de tentativas**, ignorado pelo git (na pasta temporária da sessão), uma linha por tentativa: `mudança — mecanismo esperado — resultado (antes → depois, ruído) — decisão (mantida | revertida)`.
- **Uma mudança por tentativa**, mantida só se a métrica passa do ruído e o gate continua verde; senão, revertida antes da próxima.
- **Parada.** O alvo atingido, ou um mínimo de três tentativas seguidas sem ganho acima do ruído; o predicado de parada nunca é relaxado no meio para "terminar". Parar sem o alvo vai ao relatório com o log.
- **Correção e simplicidade acima do número.** Ganho que troca correção, ou que só aparece com código bem mais difícil de ler, vai ao relatório para o desenvolvedor decidir, mesmo passando do ruído.

No relatório, o campo Performance do núcleo traz, além do formato dele:

```text
Alvo: <métrica> — <alvo> — atingido | não atingido (<quanto faltou>)
Linha de base: <comando> — <valor> ± <ruído> — <SHA>
Mudanças: <mudança> — antes → depois — mantida | revertida (sem ganho acima do ruído)
Ganho preso por: <teste de contagem | orçamento no benchmark | nada, motivo>
```
