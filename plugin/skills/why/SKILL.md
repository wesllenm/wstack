---
name: why
description: >
  Explica por que um trecho de código está como está: acha o commit e o PR que o introduziram ou mudaram, a decisão
  registrada (docs/decisions.md, ADR), a discussão de revisão e o que sessões anteriores aprenderam, separando o que
  está registrado do que é inferido. Só leitura, fora do pipeline de risco do lead. Carregar quando o desenvolvedor
  perguntar "por que isso está assim", "quem decidiu", "dá para tirar isso", "isso era de propósito", ou chamar /why;
  vale em qualquer repositório, mesmo sem o wstack adotado.
argument-hint: <arquivo:linha, símbolo ou comportamento>
---

# Why

Responde "por que isso está assim" com o histórico, sem mudar nada. Não passa pela classificação de risco, plano nem aprovação da skill `lead`. "Como funciona" é da skill `how`; se a resposta virar pedido de mudança, a mudança é tarefa nova do `lead`.

A regra que importa: separar **registrado** (alguém escreveu o motivo num commit, PR, decisão ou comentário) de **inferido** (o motivo foi deduzido do código ou da época). Motivo inventado com cara de registro é pior que "não achei": quem perguntou pode estar decidindo se pode tirar o código.

## Passos

1. **Localizar o trecho exato** (`arquivo:linha` e o intervalo de linhas). Se o desenvolvedor deu um comportamento, achar o código antes (como na skill `how`, passo 1).
2. **Histórico das linhas.** `git log -L <início>,<fim>:<arquivo> --oneline` lista os commits que mexeram nesse intervalo, do mais novo ao mais velho, cada um com o diff do intervalo; `git show <sha>` mostra a mensagem e o diff de cada um. Para um símbolo que mudou de lugar ou de nome, `git log -S<nome> --oneline` acha quando ele apareceu ou sumiu. Essas formas rodam sem pedido de permissão; `git blame` pede, e o `log -L` responde o mesmo com o motivo junto.
3. **Achar o commit de origem do comportamento**, não o último que tocou a linha: renomeação, formatação e mudança mecânica não explicam nada. Seguir para trás até o commit que mudou o significado.
4. **PR e revisão.** `gh pr list --state merged --search <sha>` acha o PR do commit; `gh pr view <n> --json title,body,comments,reviews` traz a descrição e a discussão. Comentário de revisão que pediu a mudança costuma ser o motivo real. Sem `gh` autenticado, seguir sem PR e dizer isso.
5. **Decisões e aprendizado do projeto**: `docs/decisions.md`, ADRs, `docs/gotchas.md` e `docs/gotchas/` da área, comentário de porquê no próprio código, issue citada no commit (`Refs:`, `Closes:`). Para o que foi discutido em sessões do Claude Code e não chegou ao git, carregar a skill `recall` com o caminho e o símbolo.
6. **O que mudou desde então.** O motivo ainda vale? Procurar se a restrição original sumiu: dependência atualizada, chamador removido, regra de negócio trocada, teste que protegia o comportamento. Isso responde o "dá para tirar" sem decidir por ninguém.
7. **Histórico cortado.** Se o `git log --oneline --decorate` termina num commit marcado `grafted`, o clone é raso (sessão na nuvem, CI): dizer que o histórico anterior não está disponível, em vez de concluir que o código "sempre foi assim".

## Resposta

```text
Resposta: <uma ou duas frases>
Origem: <sha curto> <data> <título> — PR <n> | sem PR — autor
Motivo registrado: "<citação curta do commit, PR, decisão ou comentário>" — <onde> | nenhum registro achado
Inferido: nada | <o que se deduz do código ou da época, e de quê>
Ainda vale: sim | não | incerto — <o que mudou ou continua igual, com arquivo:linha>
Confiança: registrado | inferido | desconhecido — <o que falta para subir (histórico raso, gh sem acesso, PR sem descrição)>
```

## Restrições

- Somente leitura: sem Edit, Write, checkout de outro commit, `git switch` para o passado ou qualquer comando que mude a árvore.
- Não decidir se o código pode sair: mostrar o motivo e se ele ainda vale; a decisão é do desenvolvedor e, se for tirar, é uma tarefa do `lead`.
- Nome e e-mail de autor só se o desenvolvedor perguntar quem; a resposta padrão é o motivo, não a pessoa.
- Segredo ou dado pessoal achado em commit antigo não vai para a resposta: dizer onde está e que precisa de tratamento.
