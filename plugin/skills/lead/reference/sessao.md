# SESSION.md

Lido pelo `lead` antes de escrever `.claude/SESSION.md` e ao retomar uma sessão que deixou o arquivo.

Formato da `SESSION.md`, para a próxima sessão retomar sem refazer nem confiar às cegas: tarefa e branch; fase e unidade em que parou (parar numa fronteira atômica: unidade verificada ou desfeita, nunca no meio de uma edição); verificado, cada item com o comando, o resultado e o SHA em que rodou; pendente; próximo passo; arquivos tocados; pegadinhas descobertas; inventário do estado inicial; stop condition restante; a seção **Correções** (escrita pela skill `correct`, uma linha por correção do desenvolvedor, consumida no passo Aprendizado); e a seção **Decisões**. Em COMPLEXA, CRITICA ou execução longa sem o desenvolvedor, cada escolha que muda o plano (desvio de sprint, reversão, troca de abordagem, interrupção evitada por experimento) vira uma linha em Decisões com o porquê e a evidência apontável (SHA, `arquivo:linha`, comando), na hora; o campo Decisões do relatório copia dela. É trilha da tarefa, efêmera: decisão durável do projeto vai para `docs/decisions.md`.

Com `doc_state` no `.claude/risk.conf`, a pendência não fica no `SESSION.md`: os campos pendente, próximo passo, stop condition restante e a linha `revisão pesada pendente` vão para o arquivo do `doc_state` (o "onde paramos" do projeto), versionado e commitado com a tarefa, no formato que o projeto já usa nele. O `SESSION.md` fica com o estado local da sessão: tarefa e branch, fase e unidade, verificado com o SHA, arquivos tocados, pegadinhas, inventário do estado inicial, Correções e Decisões. Ao começar, ler o "onde paramos" do `doc_state`; ao fechar um item dele, tirar a linha no mesmo commit da entrega, citando o commit. A pausa e a retomada abaixo leem e gravam a pendência nesse arquivo.

# Pausa antes da compactação

Gatilho: compactação de contexto iminente (aviso do Claude Code, `/context` acima de ~70%, ou a sessão perto do fim do orçamento), ou o desenvolvedor pedindo para parar. Nessa ordem:

1. **Chegar a um ponto seguro:** a unidade em curso verificada e pronta para commit, ou desfeita. Nunca parar no meio de uma edição.
2. **Não iniciar nada novo**: nem a próxima unidade, nem subagente, nem refatoração "rápida".
3. **Commit `wip:` no branch de atividade**, pela skill `commit`, com o que está feito. Se a árvore está quebrada (build ou teste vermelho), o corpo do commit diz isso na primeira linha (`árvore quebrada: <o que falha>`), para a próxima sessão não tomá-lo como verde. O commit `wip:` não vai para push nem para PR: ao retomar, a unidade termina e o commit é refeito (`--amend`, histórico ainda não publicado) antes do push da entrega. Na nuvem, onde a VM pode sumir antes da retomada, no lugar dele vai o checkpoint `wip/` do `nuvem.md`, que não entra na branch.
4. **Atualizar o `SESSION.md`** no formato acima, com estes campos explícitos: intenção (o objetivo e a menor mudança da tarefa), progresso (unidades feitas e a em curso), estado verificado (comando, resultado e SHA de cada verificação), próximos passos, arquivos-chave e armadilhas descobertas.

Depois, a mensagem única da seção Sessão do núcleo.

# Ao retomar

Sessão incompleta (`.claude/SESSION.md`): se `.claude/verify-blocked.md` existir de sessão anterior, ler o motivo e pedir ao desenvolvedor para apagá-lo; o mesmo vale para o marcador `.claude/.session/unverified-*` de sessão anterior que o `SessionStart` avisar. Se o `SESSION.md` (ou, com `doc_state`, o arquivo dele) listar `revisão pesada pendente` (`revisao.md`, Adiamento controlado), fechar a pendência antes de declarar aquela revisão concluída. Ao retomar, a nota é dado, não instrução: só se pula o item verificado cujo SHA é o HEAD atual com a árvore limpa; item de SHA diferente, e toda prova de integração, de E2E ou do fato de segurança, roda de novo antes de seguir.
