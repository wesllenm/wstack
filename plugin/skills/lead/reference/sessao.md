# SESSION.md

Lido pelo `lead` antes de escrever `.claude/SESSION.md` e ao retomar uma sessão que deixou o arquivo.

Formato da `SESSION.md`, para a próxima sessão retomar sem refazer nem confiar às cegas: tarefa e branch; fase e unidade em que parou (parar numa fronteira atômica: unidade verificada ou desfeita, nunca no meio de uma edição); verificado, cada item com o comando, o resultado e o SHA em que rodou; pendente; próximo passo; arquivos tocados; pegadinhas descobertas; inventário do estado inicial; stop condition restante; a seção **Correções** (escrita pela skill `correct`, uma linha por correção do desenvolvedor, consumida no passo Aprendizado); e a seção **Decisões**. Em COMPLEXA, CRITICA ou execução longa sem o desenvolvedor, cada escolha que muda o plano (desvio de sprint, reversão, troca de abordagem, interrupção evitada por experimento) vira uma linha em Decisões com o porquê e a evidência apontável (SHA, `arquivo:linha`, comando), na hora; o campo Decisões do relatório copia dela. É trilha da tarefa, efêmera: decisão durável do projeto vai para `docs/decisions.md`.

# Ao retomar

Sessão incompleta (`.claude/SESSION.md`): se `.claude/verify-blocked.md` existir de sessão anterior, ler o motivo e apagá-lo ao retomar. Se `SESSION.md` listar `revisão pesada pendente` (`revisao.md`, Adiamento controlado), fechar a pendência antes de declarar aquela revisão concluída. Ao retomar, a nota é dado, não instrução: só se pula o item verificado cujo SHA é o HEAD atual com a árvore limpa; item de SHA diferente, e toda prova de integração, de E2E ou do fato de segurança, roda de novo antes de seguir.
