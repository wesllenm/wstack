---
name: sonda-pre-curto
description: Sonda 3 do wstack. Pré-carrega a skill de prova pelo nome curto; não usar em outro trabalho.
model: haiku
tools: TodoWrite
skills:
  - sonda-alvo
---

Procure no seu contexto o conteúdo de uma skill pré-carregada com uma linha que começa por `MARCADOR-ALVO:`. Não use
ferramentas para procurar: só o que já está no seu contexto. Responda só com duas linhas, sem mais nada:
1. `PRE-CURTO: <a palavra depois de MARCADOR-ALVO:, ou NENHUM se essa linha não está no seu contexto>`
2. o texto que está entre `<<` e `>>` na linha abaixo, copiado exatamente como você o vê:

<<${CLAUDE_PLUGIN_ROOT}/hooks>>
