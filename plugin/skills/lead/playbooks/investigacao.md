# Playbook: investigação

Para pergunta sobre o sistema sem pedido de mudança: "por que isso acontece", "isso é seguro", "quanto custa", "onde está o gargalo", "o que quebra se eu mudar X". A resposta é o entregável; nada no repositório muda, salvo o aprendizado. Se a resposta levar a uma mudança, a mudança é uma tarefa nova, com tipo, classificação e plano próprios.

Sem diff não há classificação, plano formal, aprovação, revisão nem commit de código. As travas continuam valendo: leitura de banco só pelo `database-helper`, experimento só na pasta temporária da sessão, nenhuma edição no repositório para "testar uma ideia".

1. **Objetivo e menor mudança** (seção Início do núcleo): o objetivo é a pergunta; a menor mudança é a resposta com evidência.
2. **Hipóteses.** Listar as explicações plausíveis e, para cada uma, a evidência que a separa das outras. Pergunta com um fato observável como resposta se decide rodando algo, não opinando (seção Aprovação única do núcleo).
3. **Coletar evidência sem editar o repositório:**
   - leitura com o `explore`, ou com o `planner` em código desconhecido;
   - histórico: `git log`, `git blame`, `docs/decisions.md`, ADRs e a skill `recall`;
   - experimento ou protótipo descartável na pasta temporária;
   - banco real pelo `database-helper`;
   - medição pelo `performance-agent` ou pelas camadas da skill `performance`.
4. **Parar** quando uma hipótese tem evidência e as outras foram descartadas com evidência, ou quando a próxima evidência exige mudança no código, acesso ou credencial. Nesse caso, dizer o que falta.
5. **Aprendizado.** Fato que serviria a outra tarefa vai para `docs/gotchas/<área>.md`. A linha em Registro usa `investigação` no lugar do nível, com `achados: 0 confirmados, 0 refutados, 0 recusados, 0 escaparam`. Sem diff de código, o hook `Stop` não roda build.

A resposta substitui o relatório do núcleo:

```text
Resposta: <uma ou duas frases>
Evidência: arquivo:linha | comando — saída | SHA | consulta — o que mostra
Descartado: hipótese — evidência que a derruba
Confiança: alta | média | baixa — o que falta para subir
Próximo passo: nenhum | tarefa proposta — tipo — menor mudança
Referências lidas: playbooks/investigacao.md e as demais
```
