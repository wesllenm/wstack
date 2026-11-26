# Playbook: bug

Para comportamento errado que já existe: relato do desenvolvedor, issue, teste falhando, erro de produção. Comportamento novo ou mudado de propósito é feature, mesmo que o pedido diga "corrigir". Vale em todo nível; em TRIVIAL os passos cabem na execução direta, sem plano formal.

Os passos vão para a lista de tarefas logo depois da classificação, nesta ordem.

1. **Reproduzir antes de editar.** Um teste automatizado que falha pelo motivo relatado (o vermelho da skill `tdd`, com o gate de autoria da `test-audit`), ou a condução na skill `verify-<app>` quando o defeito só aparece na aplicação real. Guardar o comando, a saída e o SHA. Falhar por outro motivo (erro de compilação, fixture quebrada) não é reprodução. Sem reproduzir depois de um esforço razoável, interromper com o que foi tentado (seção Interrupções do núcleo, contexto insuficiente): correção às cegas não entra.
2. **Achar a causa, não o sintoma.** A linha e a condição que produzem o erro, com evidência (`arquivo:linha`, o valor observado). Uma hipótese só vira causa quando um experimento a confirma: teste focado, log temporário na pasta temporária da sessão, `git bisect` entre um SHA bom e um ruim. Escrever no plano `sintoma → causa → por que a correção atinge a causa`.
   Duas correções que falharam no mesmo gate pela mesma razão: carregar a skill `attack-the-premise` e verificar a premissa comum antes da terceira.
3. **Procurar o mesmo padrão em outros lugares**, com o `explore`. O que estiver fora do escopo vira follow-up no relatório, não correção oportunista.
4. **Planejar a menor mudança que remove a causa.** A stop condition é o teste do passo 1, que falhava antes e passa depois, mais a suíte rápida verde.
5. **Corrigir**, rodar o teste do passo 1 e a suíte rápida.
6. **Revisar** pelo nível (seção Revisão do núcleo). As lentes recebem a causa e a reprodução como ponto de foco.
7. **Aprendizado.** Bug vindo de produção, de PR ou de outro revisor conta como `escapou` na categoria que deveria tê-lo pego (`aprendizado.md`, Feedback externo). Perguntar à escada se dava para tornar o erro impossível (degrau 1) antes de aceitar só o teste de regressão.

No relatório, além do formato do núcleo:

```text
Reprodução: <comando> — falhava em <SHA> — passa em <SHA>
Causa: <arquivo:linha> — <uma frase>
Mesmo padrão em outros lugares: nenhum | arquivo:linha — follow-up
```
