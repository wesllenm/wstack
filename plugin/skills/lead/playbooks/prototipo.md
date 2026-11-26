# Playbook: protótipo

Para pergunta que só um código descartável responde: qual de duas abordagens é mais rápida, como fica uma tela, se uma biblioteca resolve o caso, se um contrato é cômodo de usar. O entregável é a decisão, não o código. Pode servir de entrada para a arena (`arena.md`), quando um critério dela depende de comportamento observável.

1. **A única decisão.** Escrever a decisão que o protótipo precisa responder, numa frase, e o critério que a decide (tempo medido, saída observada, captura de tela comparada). Sem uma decisão assim, não é protótipo: a tarefa vai para o tipo feature.
2. **Código descartável, isolado.** Na pasta temporária da sessão (fora do repositório, `limpeza.md`), com a stack mais leve que mostre a ideia: script, console, página estática. Sem testes, sem abstração, sem tocar o código de produção. O protótipo nunca é commitado no branch da feature.
3. **Variantes lado a lado.** Duas ou três, com a mesma entrada, para comparar no mesmo critério.
4. **Verificar na superfície certa:** saída ou tempo observado para comportamento (rodado mais de uma vez quando é tempo), captura de tela para visual. Opinião sobre o código do protótipo não decide nada.
5. **Entregar** a decisão, as alternativas com o resultado de cada uma, a recomendação e o caminho da pasta, dizendo que o código é descartável e não vai para o repositório.

```text
Decisão: <a pergunta> — critério: <o que decide>
Variantes: <variante> — <resultado medido ou observado>
Recomendação: <variante> — porquê
Pasta: <caminho na pasta temporária> — código descartável, fora do repositório
```

A pasta sai na limpeza com o resto da pasta temporária, salvo se o desenvolvedor pedir para conferir; aí o relatório dá o caminho. Sem diff de código, a linha em Registro usa `investigação` no lugar do nível.
