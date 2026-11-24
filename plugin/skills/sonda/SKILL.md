---
name: sonda
description: Confere se o plugin wstack está instalado e funcionando nesta sessão (hooks, skill e leitura do .claude/risk.conf do projeto). Usar só quando o desenvolvedor pedir para rodar a sonda do wstack.
---

# Sonda do wstack

Relate ao desenvolvedor, nesta ordem, sem tentar corrigir nada:

1. **Skill:** esta skill carregou (você está lendo isto pelo plugin `wstack`).
2. **SessionStart:** procure no início do contexto da sessão a mensagem `wstack <versão> carregado.` e copie as quatro linhas dela. Se não houver, diga que o hook `SessionStart` do plugin não rodou.
3. **PreToolUse:** rode exatamente `echo wstack-sonda` no Bash. O hook do plugin deve pedir aprovação com o motivo `wstack-sonda: hook do plugin rodou; risk.conf do projeto: sonda = <valor>`. Diga se o pedido apareceu e qual valor veio. Se o comando rodar sem pedido, o hook `PreToolUse` não está ativo.
4. **Projeto:** leia `.claude/risk.conf` na raiz do projeto com a ferramenta Read e diga o valor da chave `sonda`, para comparar com o que os hooks leram.

Termine com uma linha: `sonda: <ok | falhou em N>`.
