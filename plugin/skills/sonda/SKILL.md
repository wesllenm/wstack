---
name: sonda
description: Confere se o plugin wstack está instalado e funcionando nesta sessão (hooks, skill e leitura do .claude/risk.conf do projeto). Usar só quando o desenvolvedor pedir para rodar a sonda do wstack.
---

# Sonda do wstack

Relate ao desenvolvedor, nesta ordem, sem tentar corrigir nada:

1. **Skill:** esta skill carregou (você está lendo isto pelo plugin `wstack`).
2. **SessionStart:** procure no início do contexto da sessão a mensagem `wstack <versão> carregado.` e copie as quatro linhas dela. Se não houver, diga que o hook `SessionStart` do plugin não rodou.
3. **PreToolUse:** rode exatamente `echo wstack-sonda` no Bash. O hook do plugin responde `ask` com o motivo `wstack-sonda: hook do plugin rodou; risk.conf do projeto: sonda = <valor>`. Se o comando foi negado, pare aqui: diga que o hook rodou (o pedido apareceu) e use o motivo do pedido, se você o viu. Senão, o pedido pode ter aparecido para o desenvolvedor ou não (no modo automático, um classificador responde ao `ask` sem mostrar nada), então confira no registro da sessão com este comando, exatamente:

   ```bash
   f=$(ls -t ~/.claude/projects/*/*.jsonl | head -1); jq -r 'select(.attachment.hookName? == "PreToolUse:Bash") | .attachment.stdout // empty' "$f" | grep -F 'wstack-sonda:' | tail -1
   ```

   Se a saída tiver `"permissionDecision":"ask"` e o motivo acima, o hook `PreToolUse` está ativo: diga o valor de `sonda` que veio no motivo. Se a saída vier vazia, o hook não rodou. Não use a falta de um diálogo como prova de que o hook não rodou.
4. **Projeto:** leia `.claude/risk.conf` na raiz do projeto com a ferramenta Read e diga o valor da chave `sonda`, para comparar com o que os hooks leram.

Termine com uma linha: `sonda: <ok | falhou em N>`.
