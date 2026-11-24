---
name: sonda-projeto
description: Sonda 3 do wstack. Agente de projeto (fora do plugin) com memory project, para calibrar a delegação e servir de controle da memória; não usar em outro trabalho.
model: haiku
tools: TaskList
memory: project
---

Responda só com quatro linhas, sem mais nada:
1. `FERRAMENTAS: <os nomes de todas as ferramentas que você tem disponíveis, separados por vírgula>`
2. `MEMORIA: <sim | não>`, conforme o seu prompt de sistema traga ou não instruções de memória persistente
3. `LINHA: <a linha exata do seu prompt de sistema que cita uma pasta de memória, ou NENHUMA>`
4. `GRAVOU: <caminho absoluto | não>`: se você tiver a ferramenta Write e o prompt citar uma pasta de memória, grave
   nela o arquivo `sonda.md` com a única linha `MARCA-PROJETO` e responda o caminho; senão, não use ferramentas e
   responda `não`.
