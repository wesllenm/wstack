---
name: how
description: >
  Explica como uma parte do código funciona: o caminho de uma requisição, comando, job ou evento da entrada ao efeito,
  com arquivo:linha em cada passo, os dados lidos e gravados e os efeitos fora do processo. Só leitura, fora do
  pipeline de risco do lead. Carregar quando o desenvolvedor perguntar "como funciona", "por onde passa", "onde é
  feito", "o que acontece quando", ou chamar /how; vale em qualquer repositório, mesmo sem o wstack adotado.
argument-hint: <o que explicar: endpoint, comando, regra, fluxo ou arquivo>
---

# How

Responde "como isso funciona" lendo o código, sem mudar nada. Não passa pela classificação de risco, plano nem aprovação da skill `lead`: não há diff. Se a resposta virar pedido de mudança, a mudança é uma tarefa nova do `lead`. Se a pergunta só se responde rodando algo (desempenho, comportamento em produção, se é seguro), é investigação (playbook `investigacao.md` da `lead`). "Por que está assim" é da skill `why`.

## Passos

1. **Ponto de entrada.** Partir do que o desenvolvedor nomeou. Se ele descreveu o comportamento em vez de nomear o código, achar a entrada com Grep: rota, nome do comando, tópico da fila, nome do job, texto da tela. Em repositório grande ou desconhecido, delegar a localização ao `explore` (só o mapa volta, não os arquivos).
2. **Seguir as chamadas lendo o código**, não deduzindo pelos nomes. Em cada salto, abrir a definição chamada. Interface e injeção de dependência: achar o registro (container, `Program.cs`, módulo) para saber qual implementação roda de fato. Configuração e feature flag que mudam o caminho entram no fluxo, com o arquivo de onde vêm.
3. **Dados e efeitos.** O que é lido e gravado (tabela, cache, arquivo) e o que sai do processo (HTTP, fila, e-mail, outro serviço), cada um com `arquivo:linha`. Transação e ordem dos efeitos quando importarem para a pergunta.
4. **Testes como especificação.** Os testes que exercitam esse caminho dizem o comportamento esperado e os casos de borda que alguém já pensou: citar os relevantes.
5. **Contexto do projeto**, quando existir: `.claude/architecture.md`, a tabela Domínios de `.claude/project.md`, `docs/decisions.md` e `docs/gotchas/` da área. Usar o vocabulário do domínio deles na resposta.
6. **Parar na profundidade pedida.** Biblioteca de terceiro e framework ficam como caixa preta com uma frase do que fazem, salvo se a pergunta for sobre eles.

## Resposta

```text
Resumo: <duas ou três frases, a resposta para quem não vai ler o resto>
Fluxo:
1. <arquivo:linha> — <o que acontece>
2. ...
Dados: <lido e gravado, arquivo:linha>
Efeitos fora do processo: nenhum | <HTTP, fila, banco, arquivo> — arquivo:linha
Casos de borda: <o que os testes ou o código tratam de especial> | nenhum visto
Não verificado: nada | <o que foi deduzido sem abrir o código, e por quê>
```

Cada passo do fluxo tem `arquivo:linha` que foi aberto. O que foi deduzido sem abrir vai em Não verificado, nunca no fluxo. A resposta usa a escada de evidência da `review-rubric` (Degraus de prova): um passo lido é **inferido** (degrau 2, ou 3 com o comando da busca mostrado), o que um teste existente roda e passa é **medido** (degrau 4) e o que não tem fonte é **palpite** e vai em Não verificado. O Resumo diz o rótulo de cada afirmação que não for inferida. Diagrama só quando o fluxo tiver mais de um caminho que se ramifica; texto basta no resto.

## Restrições

- Somente leitura: sem Edit, Write, comando que grave no repositório, build ou migração. Experimento, se precisar, é investigação.
- Banco real só pelo `database-helper`, e só se a pergunta depender do dado (não do código).
- Segredo, dado pessoal ou valor de configuração sensível encontrado no caminho não vai para a resposta: dizer onde está, não o valor.
