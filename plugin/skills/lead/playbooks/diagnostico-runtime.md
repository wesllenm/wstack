# Playbook: diagnóstico de runtime

Para comportamento que só aparece com o processo rodando: vazamento de memória, thread pool esgotado, CPU alta sem causa no código lido, travamento, deadlock, latência que oscila, exceção que some do log. A regra: diagnosticar pelo processo rodando, não só pela leitura do código. O entregável é o diagnóstico com referências, não a correção; quando a causa fica clara, a correção segue o playbook de bug (`bug.md`) ou o de performance (`performance.md`), como tarefa própria.

Sem diff de produção não há classificação nem commit de código. Instrumentação temporária vive na pasta temporária da sessão ou numa worktree descartável, e sai na limpeza (`limpeza.md`).

1. **Capturar um sinal do processo rodando**, o mais barato que responde à pergunta, e guardar comando e arquivo na pasta temporária da sessão. Em .NET:
   - `dotnet-counters monitor` (ou `collect`) para GC, alocação, thread pool, exceções e contadores do ASP.NET;
   - `dotnet-trace collect` para CPU e eventos (perfil de amostragem, `--profile cpu-sampling`);
   - `dotnet-dump collect` e `dotnet-dump analyze` (`dumpheap -stat`, `gcroot`, `clrstack -all`, `syncblk`) para memória e travamento;
   - logs estruturados e traces do OpenTelemetry ou do Application Insights, pelo correlation id (skill `observability`).
   Em outra stack, o equivalente: perfil de CPU, heap snapshot, dump de threads, traces.
2. **Reduzir o artefato ao achado principal.** Dump, trace e log grandes são analisados por um subagente (`performance-agent`), que lê o arquivo e devolve só o achado: o tipo que mais cresce e quem o segura, a pilha que domina a CPU, a thread bloqueada e o que ela espera. O artefato não entra no contexto principal.
3. **Provar o mecanismo** com instrumentação temporária (log, contador, evento no ponto suspeito) ou uma reprodução controlada (carga, sequência de chamadas, falha injetada) que faz o sinal aparecer e sumir sob comando. Sinal que não se reproduz fica como hipótese, com o rótulo `palpite` ou `inferida` da escada da `review-rubric`.
4. **Mapear para o código:** arquivo, símbolo e a linha que aloca, bloqueia ou agenda, com `arquivo:linha` aberto, e o caminho do ponto de entrada até ela.
5. **Entregar o diagnóstico**, sem corrigir. Se a causa está clara, propor a tarefa seguinte com o tipo (bug ou performance) e a reprodução do passo 3 como teste que falha.

A resposta substitui o relatório do núcleo:

```text
Sinal: <ferramenta e comando> — <o que mostrou> — <arquivo do artefato na pasta temporária>
Achado principal: <uma frase> — degrau de evidência
Mecanismo: <instrumentação ou reprodução> → <resultado> | não provado: <o que faltou>
Código: <arquivo:linha> — <símbolo> — <aloca | bloqueia | agenda> — caminho desde <ponto de entrada>
Próxima tarefa: bug | performance | nenhuma — <proposta>
```

**Aprendizado.** A linha em Registro usa `investigação` no lugar do nível, como no playbook de investigação. Ferramenta ou comando de captura que funcionou neste projeto vai para `docs/gotchas/<área>.md`.
