---
name: sonda-agentes
description: Sonda 3 do wstack. Confere como o Claude Code trata agentes de plugin (agente da sessão pelo settings.json, delegação por nome curto ou com prefixo, pré-carga de skill, variável no corpo do agente, memória). Usar só quando o desenvolvedor pedir a sonda de agentes do wstack.
---

# Sonda de agentes do wstack

Não tente corrigir nada nem contornar um erro: relate o que veio, com o texto exato. Faça um passo por vez, na ordem.
Quando o passo manda chamar um subagente, faça a chamada mesmo que o nome não apareça entre os subagentes que você vê:
o erro da ferramenta, se vier, é o dado. Em toda chamada de subagente, relate também quantas ferramentas ele usou
(o resultado da chamada traz esse número).

## 0. Versão e atualização

1. Copie a linha `wstack <versão> carregado.` do início da sessão (mensagem do hook `SessionStart`). Se não houver, diga.
2. Rode `ls ~/.claude/plugins/cache/wstack/wstack/` e
   `jq '.plugins["wstack@wstack"]' ~/.claude/plugins/installed_plugins.json` e relate as saídas (as versões no cache e
   as datas de instalação e de atualização dizem se o plugin foi instalado agora ou atualizado na partida).

## A. Agente da sessão

1. Copie, do seu prompt de sistema, a linha inteira que começa por `PRINCIPAL-ATIVO-` (o sufixo só existe no prompt do
   agente da sonda; não está neste texto). Se não houver essa linha, diga NENHUMA.
2. Leia o `.claude/settings.json` do projeto com a ferramenta Read e copie o valor de `"agent"`.

## B. Delegação

O agente da sonda só pode delegar a uma lista fechada: `sonda-folha-a` está nela pelo nome curto, `sonda-folha-b` com o
prefixo `wstack:`, e `sonda-memoria` com os dois. Chame, um por vez, nesta ordem, com o pedido "responda conforme as suas
instruções":

1. `sonda-memoria` e depois `wstack:sonda-memoria` (calibração: listado nas duas formas, então só a forma do nome na
   chamada pode falhar)
2. `sonda-folha-a`
3. `wstack:sonda-folha-a`
4. `sonda-folha-b`
5. `wstack:sonda-folha-b`
6. `general-purpose` (controle: fora da lista; se a lista for aplicada, tem de falhar)

Para cada chamada, relate a resposta do subagente ou o erro exato da ferramenta.

Leitura: se em A não veio a linha `PRINCIPAL-ATIVO-...`, a sessão não é o agente da sonda e não tem lista de delegação;
diga isso, e os itens 2 a 5 valem só como dado da forma do nome na chamada. Se o controle (6) não falhou, a lista não foi
aplicada; diga isso também.

## C. Pré-carga de skill

Chame `wstack:sonda-pre-curto` e depois `wstack:sonda-pre-prefixo` (se o nome com prefixo der erro, tente o curto e diga
que tentou). Relate as duas linhas de cada resposta e quantas ferramentas cada um usou. A primeira linha diz se a skill
`sonda-alvo` chegou ao contexto do subagente: o esperado, se chegou, é `abacaxi-7q`. Esses subagentes não têm ferramenta
de leitura. A `sonda-pre-curto` pede a skill pelo nome curto; a `sonda-pre-prefixo`, com o prefixo.

## D. Variável no corpo do agente

Das respostas de B e C, junte a segunda linha. Ela traz o que o corpo do agente tinha no lugar da variável
CLAUDE_PLUGIN_ROOT: se veio um caminho absoluto terminado em `/hooks`, o Claude Code trocou a variável no corpo do agente;
se veio o texto com cifrão e chaves, não trocou.

## E. Memória

Da resposta de `sonda-memoria` (passo B.1), relate as três linhas. O agente foi declarado só com a ferramenta TodoWrite;
se ele tem Read, Write ou Edit, foi a memória que as acrescentou. Depois rode `ls -la .claude/agent-memory 2>&1 | head`
e relate a saída.

## Resultado

Termine com uma tabela (passo, o que veio) e com uma linha:

`sonda-agentes: versão=<x> cache=<versões> principal=<linha PRINCIPAL-ATIVO ou NENHUMA> chamada-curta=<ok|erro> chamada-prefixo=<ok|erro> folha-a=<curto ok/erro, prefixo ok/erro> folha-b=<curto ok/erro, prefixo ok/erro> controle=<falhou|passou> pre-curto=<abacaxi-7q|NENHUM|erro> pre-prefixo=<abacaxi-7q|NENHUM|erro> variável-no-agente=<trocada|não> memória=<ferramentas a mais: sim|não>`
