---
name: sonda-caminhos
description: Sonda 2 do wstack. Confere se uma skill do plugin chama script do plugin por ${CLAUDE_PLUGIN_ROOT}, se regras allow do .claude/settings.json do projeto casam com esse caminho e se um hook Node do plugin importa outros módulos do plugin. Usar só quando o desenvolvedor pedir para rodar a sonda de caminhos do wstack.
---

# Sonda de caminhos do wstack

Não tente corrigir nada. Copie cada comando exatamente como ele aparece neste texto, sem aspas a mais, sem trocar a
variável pelo valor e sem completar o caminho. Rode um comando por vez, nunca em paralelo. Antes de cada comando,
escreva numa linha o que o desenvolvedor deve fazer se aparecer um pedido de aprovação.

## A. A skill chama um script do plugin

1. Escreva, entre crases, a linha abaixo exatamente como você a vê neste texto, e diga se ela mostra
   `${CLAUDE_PLUGIN_ROOT}` ou um caminho absoluto (o Claude Code trocou a variável ao carregar a skill):

   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-caminho.sh`

2. Escreva "Passo A: se aparecer pedido de aprovação, aprove só desta vez (não o 'não perguntar de novo')." e rode a
   linha acima. Relate a saída. O esperado é
   `wstack-sonda-caminho: rodou de <pasta do plugin>; CLAUDE_PLUGIN_ROOT no Bash: <valor ou ausente>`. Se der erro,
   relate o erro.

## B. Regras allow do projeto

Neste passo, uma negação é o resultado esperado, não um erro: quando um comando for negado, anote e siga para o
próximo número sem mudar nada no comando (nem aspas, nem caminho). Se o desenvolvedor disser para fazer diferente,
pare a sonda e relate o que já tiver.

Escreva "Passo B: negue todo pedido de aprovação que aparecer neste passo, com um No simples." e rode, nesta ordem, um
por vez:

- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-allow.sh 4`
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-allow.sh 1`
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-allow.sh 2`
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-allow.sh 3`
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-allow.sh 5`

Para cada número, relate um destes:
- `rodou`: veio a saída `wstack-sonda-allow: <número> rodou`;
- `negado pelo desenvolvedor`: o pedido apareceu e foi negado;
- `negado por hook: <motivo>`: veio um motivo de hook em vez de pedido;
- `erro: <mensagem>`: rodou, mas o bash deu erro (por exemplo, arquivo não encontrado).

O 4 é o controle e não tem regra: se ele rodou, a sessão não está no modo que pede aprovação e o passo B não vale;
diga isso. Os números 1, 2 e 3 têm cada um uma forma de regra no `.claude/settings.json` do projeto; o 5 não tem
regra, mas um hook do plugin o aprova. Leia o `.claude/settings.json` do projeto com a ferramenta Read e copie as três
regras `allow` ao lado dos números.

A regra é comparada com o texto do comando, então nem todo número se aplica em toda rodada. Se no passo A a linha veio
com a variável trocada por um caminho, o 1 não tem como casar: marque-o `não se aplica`. Se veio com
`${CLAUDE_PLUGIN_ROOT}` escrito, o 2 e o 3 não têm como casar: marque-os `não se aplica`.

Por fim, veja com a ferramenta Read se existe `.claude/settings.local.json` no projeto. Se existir, copie as regras
`allow` dele: uma regra gravada por um "não perguntar de novo" pode ter liberado algum número.

## C. Hook Node do plugin importa outros módulos

Escreva "Passo C: se aparecer pedido de aprovação, aprove só desta vez." e rode `echo wstack-sonda-node`. O hook Node do plugin
deve negar o comando com o motivo
`wstack-sonda-node: hook Node rodou; módulo da mesma pasta: ok; módulo de outra pasta: ok`. Relate o motivo que veio.
Se o comando rodou e imprimiu `wstack-sonda-node`, o hook não rodou. Se o motivo falar de node ausente ou de falha do
node, relate isso.

## Resultado

Termine com uma tabela (passo, o que se esperava, o que veio) e com uma linha:

`sonda-caminhos: a=<variável trocada no texto | variável só no Bash | falhou> b=<números que rodaram, ou nenhum; números que não se aplicam> c=<ok | falhou>`
