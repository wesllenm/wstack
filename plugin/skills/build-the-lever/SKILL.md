---
name: build-the-lever
description: >
  Princípio: em trabalho repetitivo não trivial, faça a primeira unidade à mão, depois construa a ferramenta, prove-a
  rodando de novo na mesma unidade e só então aplique no resto; prefira ferramenta determinística a espalhar o mesmo
  trabalho entre agentes. Carregar em mudança que se repete em muitos arquivos (reference/lote.md da lead), em migração
  mecânica e antes de delegar a mesma transformação a vários subagentes.
---

# Construa a alavanca

## Regra

Trabalho que se repete se faz uma vez à mão e depois por ferramenta. A unidade feita à mão é o oráculo da ferramenta: a ferramenta só vale quando reproduz o oráculo exatamente.

## Como aplicar

1. Fazer a primeira unidade à mão, verificar com build e testes e guardar o resultado.
2. Construir a ferramenta (script, codemod, consulta, gerador) na pasta temporária da sessão, nunca no repositório, salvo se ela for virar parte do projeto com aprovação.
3. Rodar a ferramenta sobre a versão original da mesma unidade e conferir que o resultado é idêntico ao feito à mão. Divergência é ferramenta errada, não exceção a tratar à mão.
4. Aplicar no resto e conferir uma amostra do diff, com build e testes.

## Ferramenta em vez de agentes

Espalhar a mesma transformação entre vários subagentes multiplica o custo e a variação: cada um decide os casos de borda de um jeito. Uma ferramenta determinística decide uma vez, e o diff dela se revisa por amostra. Agente fica para o que exige julgamento por caso.
