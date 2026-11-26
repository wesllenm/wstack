# Delegação: sprint contract, comandos e isolamento

Lido pelo `lead` antes do primeiro sprint contract da tarefa, antes de delegar a um subagente que edita e antes de usar `isolation: worktree`.

Os scripts aparecem como `<plugin>/scripts/<nome>`: `<plugin>` é a pasta do plugin que o núcleo da skill dá na seção Scripts do plugin (o Read não troca variável neste arquivo). Chamar pelo caminho inteiro, como o núcleo manda.

Todo subagente parte de contexto zero. O prompt de delegação precisa conter escopo, arquivos, critérios, comando de verificação, exclusões, as skills a carregar, sempre pelo nome completo `<plugin>:<skill>` (as deste workflow são `wstack:<nome>`; as de plugin de fornecedor entram quando a tarefa tocar a API daquela área: por exemplo `dotnet-skills`, `dotnet-msbuild`, `dotnet-test`) e o caminho da pasta temporária da sessão. A precedência é: convenções do projeto, `CLAUDE.md` e `.claude/rules/`; depois as skills de processo deste workflow; por último as skills de plugin, que são referência de API e de ferramenta e nunca decidem framework de teste, estrutura, formato de erro nem estratégia de revisão (o framework de teste é o do projeto, não o que a skill de plugin sugere). Skills de plugin não entram no `skills:` do frontmatter dos agentes, e os revisores não as carregam.

## Sprint contract

```text
ID:
Escopo:
Arquivos autorizados:
Critérios de aceitação:
Esboço da fatia (COMPLEXA e CRITICA): uso primeiro, depois as assinaturas derivadas dele
  uso: <como o chamador usa a fatia: a requisição e a resposta, o comando, a mensagem>
  assinaturas: <request, response, handler ou service, endpoint ou consumidor: tipos e métodos, corpos vazios>
Testes:
Testes existentes que podem ser alterados: nenhum | lista com motivo
Comando de verificação:
Exclusões:
Restrições das skills:
Pasta temporária da sessão: <caminho> (saídas de teste, conferência e scripts avulsos)
Recursos que pode criar: nenhum | worktree, branch, container — e quem remove

Agente: wstack:<nome>
Modelo:
Ferramentas permitidas:
```

**Esboço da fatia.** Em COMPLEXA e CRITICA o `lead` escreve o esboço antes do contrato: primeiro o uso (como o chamador usa a fatia, do ponto de vista de quem consome), depois os tipos e as assinaturas que saem dele, com corpos vazios que a implementação preenche. O `implementer` segue o esboço e sinaliza qualquer desvio no retorno (`desvio do esboço: <o quê> — por quê`), em vez de absorvê-lo em silêncio. Desvio que muda a assinatura pública ou o uso volta ao `lead` antes de seguir. Atrito que se repete na mesma área (o `iteration-guard` avisa) é sinal de esboço errado: descartá-lo e voltar ao plano, não remendar.

O subagente retorna resumo, arquivos, testes, decisões, desvios do esboço, blockers, resultado e a lista do que criou fora do diff; quando roda em worktree, também o caminho, a branch, o SHA de partida e os commits que fez.

Revisores nunca recebem a justificativa do implementer: só diff, contrato, critérios, resultados de teste e pontos de foco.

**Comandos sem pedido de permissão.** Todo sprint contract e o próprio `lead` seguem: ler arquivo com Read, Grep e Glob (nunca `cat`/`sed` de `.claude/**`, que o `path-guard` pede); escrever com Edit e Write (nunca `cat >>`, `printf >` ou `tee` em arquivo do repositório, que o `redirect-guard` pede); e chamar build, teste, script do harness e `git push` sozinhos na chamada, na forma fechada, sem prefixo (`cd <raiz> &&`, `S=...;`, `timeout N`, `for`), porque os hooks `dotnet-allow`, `path-guard` e `push-guard` só liberam o comando inteiro. O cwd já é a raiz; a saída vai para arquivo na pasta temporária (`> <arquivo> 2>&1`, com o caminho absoluto escrito por extenso: o `redirect-guard` não expande variável, então `S=<pasta>; ... > $S/x` pede) e é lida numa chamada seguinte. Quebrar essas regras é a causa mais comum de pedido de permissão: no harness de origem, 15 de 25 pedidos de uma sessão, e 12 de 18 noutra, de subagentes com `S=...; ... > $S/...` porque o contrato dizia só "sem prefixo `cd`". A regra está também no `CLAUDE.md`, que todo subagente carrega, e o contrato não deve afrouxá-la.

Subagente com `isolation: worktree` nasce do HEAD commitado (`worktree.baseRef: "head"` no `settings.json` do projeto; sem a chave, nasce da branch padrão, sem o trabalho em andamento nem o plano) e não leva mudança não commitada. Usar isolamento só quando o que ele precisa já está commitado (unidade anterior fechada pela skill `commit`); se depende de mudança em curso, delegar sem isolamento. Nunca commitar só para delegar: o commit sairia antes dos gates e sumiria da classificação e do despacho, que comparam com o HEAD. O SHA de partida vai no sprint contract e o subagente o confere antes de editar (divergência é blocker, não ajuste). A worktree é removida automaticamente só se não houver mudanças. Quando houver, o `lead` integra o resultado e remove a worktree e a branch dela na limpeza.

Para tarefas independentes entre si, sugerir ao desenvolvedor abrir uma segunda sessão do `claude` numa worktree separada (`git worktree add`), em vez de enfileirar no mesmo `lead`. Cada sessão tem o próprio `session_id`, a própria base em `.claude/.session/` e os próprios gates; a única coisa compartilhada é o repositório, então as duas não devem tocar os mesmos arquivos.
