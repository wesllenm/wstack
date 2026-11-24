---
name: sonda-agentes
description: Sonda 3 do wstack. Confere como o Claude Code trata agentes de plugin (agente da sessão pelo settings.json, delegação por nome curto ou com prefixo, pré-carga de skill, variável no corpo do agente, memória). Usar só quando o desenvolvedor pedir a sonda de agentes do wstack.
---

# Sonda de agentes do wstack

Não tente corrigir nada nem contornar um erro: relate o que veio, com o texto exato. Faça um passo por vez, na ordem.

## 0. Versão

Copie a linha `wstack <versão> carregado.` do início da sessão (mensagem do hook `SessionStart`). Se não houver, diga.

## A. Agente da sessão

Diga se o seu prompt de sistema contém a linha `PRINCIPAL-ATIVO-7Q`. Se contém, a sessão começou como o agente
`wstack:sonda-principal`, ligado pelo `"agent"` do `.claude/settings.json` do projeto. Leia esse arquivo com a ferramenta
Read e copie o valor de `"agent"`.

## B. Delegação

Chame, pela ferramenta de subagentes, um por vez, nesta ordem, com o pedido "responda conforme as suas instruções":

1. `sonda-folha-a`
2. `wstack:sonda-folha-a`
3. `sonda-folha-b`
4. `wstack:sonda-folha-b`

Para cada chamada, relate a resposta do subagente (as duas linhas) ou o erro exato da ferramenta. A `sonda-folha-a`
está na lista de ferramentas do agente principal pelo nome curto; a `sonda-folha-b`, com o prefixo `wstack:`.

## C. Pré-carga de skill

Chame `wstack:sonda-pre-curto` e depois `wstack:sonda-pre-prefixo` (se o nome com prefixo der erro, tente o curto e diga
que tentou). Relate as duas linhas de cada resposta. A primeira diz se a skill `sonda-alvo` chegou ao contexto do
subagente: o esperado, se chegou, é `abacaxi-7q`. A `sonda-pre-curto` a pede pelo nome curto; a `sonda-pre-prefixo`, com
o prefixo.

## D. Variável no corpo do agente

Das respostas de B e C, junte a segunda linha: se ela traz um caminho absoluto terminado em `/hooks`, o Claude Code
trocou `${CLAUDE_PLUGIN_ROOT}` no corpo do agente; se traz o texto com `${`, não trocou.

## E. Memória

Chame `wstack:sonda-memoria` (ou o nome curto, se der erro) e relate a linha `MEMORIA: ...`. Depois rode
`ls -la .claude/agent-memory 2>&1 | head` e relate a saída.

## Resultado

Termine com uma tabela (passo, o que veio) e com uma linha:

`sonda-agentes: versão=<x> principal=<sim|não> folha-a=<curto ok/erro, prefixo ok/erro> folha-b=<curto ok/erro, prefixo ok/erro> pre-curto=<abacaxi-7q|NENHUM|erro> pre-prefixo=<abacaxi-7q|NENHUM|erro> variável-no-agente=<trocada|não> memória=<sim|não>`
