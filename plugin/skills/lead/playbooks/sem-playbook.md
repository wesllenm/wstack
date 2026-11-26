# Playbook: sem playbook

Para tarefa com mudança que não encaixa em feature, bug, investigação, performance nem refatoração: migrar um sistema de build, adotar uma ferramenta, trocar a forma de um processo, consolidar configurações espalhadas. O nível do `classify-diff.sh` continua decidindo gates, revisão e o tamanho do plano; este playbook só troca a sequência de passos por uma que funciona sem receita pronta.

A ideia: sem receita, o risco é trabalhar muito sem saber se está chegando. Cada unidade de trabalho vira um experimento com veredito, e a forma de verificar vem antes da primeira unidade.

1. **Condição de pronto testável.** Uma frase que um comando, um teste ou uma condução na aplicação decide ("o build do CI roda com a ferramenta nova e o tempo não passa de 8 minutos", "nenhum serviço lê a configuração antiga"). Junto, o nível de rigor: **alto** para o que é irreversível ou sai da máquina (dado, contrato, deploy, permissão), **normal** para o resto. Sem condição testável, a tarefa volta ao desenvolvedor antes do plano.
2. **Unidades pequenas, a incógnita de maior risco primeiro.** Quebrar o trabalho em unidades que cabem num commit cada, e pôr na frente a que pode invalidar o resto (a ferramenta nova suporta o caso mais difícil? a configuração antiga tem leitor escondido?). Se a primeira unidade refuta a premissa, o plano volta ao desenvolvedor, como na seção Interrupções do núcleo.
3. **Forma de verificar antes da primeira unidade.** O comando ou teste que mede a condição de pronto, rodado agora para registrar a linha de base (o estado atual, mesmo que falhe). Sem linha de base, uma unidade não tem como mostrar que ajudou.
4. **Cada unidade é um experimento.** Hipótese (o que esta unidade deve mudar na medida), execução, medida, e o veredito, com o rótulo de evidência da `review-rubric` (Degraus de prova):
   - **VERIFICADO:** a medida mudou como esperado, por teste ou script rodado (degrau 4 ou 5);
   - **NÃO VERIFICADO:** a medida não mudou, ou mudou ao contrário. A unidade é desfeita ou corrigida antes da próxima;
   - **INCONCLUSIVO:** a medida não decide (ruído, ambiente, falta de dado). Dizer o que decidiria e não empilhar outra unidade em cima.
   Commit por unidade com veredito VERIFICADO, como no Pipeline do nível.
5. **Conferir o todo contra a condição de pronto**, com o mesmo comando do passo 3. A tarefa só termina VERIFICADO quando a condição de pronto passa; unidades verificadas uma a uma não bastam.

O relatório do núcleo traz, no lugar de Resumo, a condição de pronto, a linha de base, a tabela de unidades (`unidade — hipótese — veredito — evidência`) e a conferência final. Os vereditos são os mesmos da prova por execução da `review-rubric` e da `blast-radius`.

**Aprendizado.** O relatório diz `Tipo: sem playbook`. Quando a mesma sequência de unidades aparecer em duas tarefas, propor no relatório um playbook novo para ela (seção Aprendizado do núcleo, Triagem das lições).
