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

O agente da sonda só pode delegar a uma lista fechada: `sonda-folha-a` e `sonda-folha-b` estão nela com o prefixo
`wstack:`, e `sonda-memoria` com os dois (as rodadas anteriores mostraram que entrada só pelo nome curto some da lista).
Fora do plugin, `sonda-projeto` é um agente do projeto (`.claude/agents/`), cujo nome não tem prefixo, listado pelo nome
curto. Chame, um por vez, nesta ordem, com o pedido "responda conforme as suas instruções":

1. Calibração. `sonda-projeto`: se responder, a lista aceita entrada pelo nome curto e a chamada acha o agente pelo
   nome exato, então o erro do nome curto nos agentes do plugin vem do nome deles (`wstack:<nome>`), não da lista nem
   da forma da chamada; se der erro, a lista não aceita nome curto de nenhum agente. Depois, `sonda-memoria` e
   `wstack:sonda-memoria`.
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

Das respostas de `sonda-projeto` (agente do projeto, o controle) e de `wstack:sonda-memoria` (agente do plugin), ambas
do passo B.1, relate as quatro linhas e quantas ferramentas cada um usou. Os dois foram declarados só com a ferramenta
TaskList e com `memory: project`; se um deles tem Read, Write ou Edit, foi a memória que as acrescentou. As linhas
`MEMORIA` e `LINHA` são o que o próprio agente diz e não bastam: a prova é o arquivo gravado. Rode
`ls -laR .claude/agent-memory ~/.claude/agent-memory 2>&1 | head -40` e
`grep -rn 'MARCA-' .claude/agent-memory ~/.claude/agent-memory 2>&1 | head` e relate as saídas.

Leitura: `MARCA-PROJETO` gravada e `MARCA-PLUGIN` não, a memória vale em agente de projeto e é ignorada em agente de
plugin; as duas gravadas, vale nos dois; nenhuma, a memória não acrescenta ferramentas a agente com `tools:` restrito
(e E não decide sobre o plugin). Se `sonda-projeto` deu erro em B.1, diga que falta o controle.

Os arquivos gravados são estado da sonda: não faça commit deles.

## Resultado

Termine com uma tabela (passo, o que veio) e com uma linha:

`sonda-agentes: versão=<x> cache=<versões> principal=<linha PRINCIPAL-ATIVO ou NENHUMA> calibração-projeto=<ok|erro> chamada-curta=<ok|erro> chamada-prefixo=<ok|erro> folha-a=<curto ok/erro, prefixo ok/erro> folha-b=<curto ok/erro, prefixo ok/erro> controle=<falhou|passou> pre-curto=<abacaxi-7q|NENHUM|erro> pre-prefixo=<abacaxi-7q|NENHUM|erro> variável-no-agente=<trocada|não> memória-projeto=<gravou|não gravou|erro> memória-plugin=<gravou|não gravou|erro>`
