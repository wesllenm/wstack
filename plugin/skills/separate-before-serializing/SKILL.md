---
name: separate-before-serializing
description: >
  Princípio: antes de sincronizar atores concorrentes (subagentes, sessões, workers, requisições), elimine o
  compartilhamento: um arquivo, chave, branch, pasta ou porta por ator. Instrução pedindo cuidado não é controle de
  concorrência. Carregar no checkpoint de paralelismo do plano, no modo paralelo (reference/paralelo.md da lead) e com a
  skill concurrency quando o código tiver estado mutável compartilhado.
---

# Separe antes de serializar

## Regra

O primeiro controle de concorrência é não compartilhar. Só depois de provar que o compartilhamento é inevitável entra a serialização (trava, fila, versão otimista), e ela protege uma invariante real, dita em uma frase.

## Como aplicar

1. Listar o estado mutável que mais de um ator toca: arquivo, linha ou tabela, chave de cache, branch, pasta, porta, variável global.
2. Para cada um, procurar a separação: um por ator (nome com o id do ator, pasta própria, worktree, faixa de portas, partição por chave).
3. O que não separa (o mesmo agregado, o mesmo contador de negócio) é a invariante real: escrever qual é e serializar só ela, com o mecanismo da skill `concurrency`.
4. Nunca resolver com texto: "cada agente cuida para não sobrescrever", "rodar um de cada vez" sem mecanismo que garanta são pedidos, não controle.

## Sinais

- Dois atores gravando o mesmo arquivo de estado, log ou saída de teste.
- Correção de condição de corrida que acrescenta espera (`sleep`, retry) em vez de tirar o compartilhamento.
- Plano paralelo em que duas frentes listam os mesmos arquivos.
