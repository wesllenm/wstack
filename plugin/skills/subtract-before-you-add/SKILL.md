---
name: subtract-before-you-add
description: >
  Princípio: remova complexidade antes de construir; o desenho termina com a superfície (tipos públicos, parâmetros,
  configurações, caminhos de código) igual ou menor que antes. Carregar no plano de feature ou refatoração que
  acrescenta abstração, opção ou caminho novo, e na lente review-simplicity como critério.
---

# Subtraia antes de somar

## Regra

Antes de acrescentar, procurar o que sai: o caminho antigo que o novo substitui, a opção que ninguém usa, a camada que só repassa. O diff bom deixa a superfície do desenho igual ou menor; quando ela cresce, o motivo está no plano.

## Como aplicar

1. No plano, listar o que a mudança acrescenta à superfície: tipo público, método, parâmetro, configuração, flag, segundo caminho para a mesma tarefa.
2. Para cada item, procurar o que pode sair junto: o código que o novo torna morto, o parâmetro que passa a ter um valor só, o caminho antigo que fica duplicado.
3. Se nada sai e a superfície cresce, escrever no plano por que o acréscimo é necessário agora (o critério de aceitação que pede), não "para o futuro".
4. Na revisão, superfície que cresceu sem esse motivo é candidato `simplicity` (rubrica, lente de simplicidade).

## Sinais

- Feature que adiciona um segundo jeito de fazer algo que já tinha um.
- Parâmetro novo com o mesmo valor em todos os chamadores.
- Refatoração que termina com mais arquivos e mais tipos do que começou, sem mudança de comportamento.
