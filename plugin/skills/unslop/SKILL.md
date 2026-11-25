---
name: unslop
description: >
  Limpa texto técnico em português brasileiro: tira enfeite, muleta e cara de texto gerado de mensagem de commit,
  descrição de PR, documentação (README, docs/decisions.md, gotchas), relatório e comentário de revisão. Carregar
  antes de escrever qualquer um desses textos, quando a skill commit pedir, ou quando o desenvolvedor pedir para
  revisar ou enxugar um texto (/unslop).
argument-hint: <arquivo ou texto a limpar>
---

# Unslop

Texto técnico bom diz o que mudou, por quê e o que isso causa, com o nome das coisas e números onde houver. O leitor é um colega com pressa e o diff aberto. Tudo o que não muda a compreensão dele sai.

## Como aplicar

1. Escrever primeiro, limpar depois: o rascunho vai para um arquivo da pasta temporária da sessão.
2. Rodar `node ${CLAUDE_PLUGIN_ROOT}/scripts/slop-check.mjs <arquivo>`. **Erro** sai sempre. **Aviso** é suspeita: manter só se a palavra disser algo que a troca não diz (um número, um nome, uma consequência), e nesse caso a frase precisa mostrar isso.
3. Reler com as seções abaixo, que pegam o que o script não pega.
4. O texto limpo é o que vai para o commit (`git commit -F <arquivo>`), para o `gh pr create --body-file` ou para o arquivo de documentação.

O script só olha palavras e padrões. Ele não lê código entre crases, menção entre aspas duplas nem blocos de código, e ignora as linhas de rodapé do commit (`Co-Authored-By:`, `Refs:` e as outras).

## Cortar

- **Abertura e fecho vazios:** "Claro!", "Ótima pergunta", "Com certeza", "Espero ter ajudado", "Qualquer dúvida, estou à disposição", "Em resumo", "Em suma".
- **Autorreferência:** "Este commit adiciona", "Neste PR", "Esta mudança tem como objetivo". O título já é a mudança; o corpo começa pelo motivo.
- **Muleta de ênfase:** "É importante ressaltar que", "Vale destacar que", "Cabe mencionar que". Se é importante, diga a coisa.
- **Narração do processo:** "rodei os testes", "o agente analisou", "após investigar". O que importa é o resultado e a evidência.
- **Lista que repete o diff:** arquivo por arquivo, função por função. O diff mostra o quê; o texto diz por quê.
- **Hedge em cascata:** "pode potencialmente", "de certa forma", "em alguns casos talvez". Uma ressalva, a verdadeira, com o caso.

## Trocar

| Em vez de | Escrever |
|---|---|
| robusto, abrangente, eficiente, de forma eficaz | o que concretamente aguenta, cobre ou economiza, com número se houver |
| crucial, fundamental, essencial | o que quebra sem isso |
| otimizar, melhorar significativamente | "de 420 ms para 90 ms", "uma consulta em vez de N" |
| aprimorar, potencializar, alavancar | melhorar, usar, ou o verbo do que de fato acontece |
| realizar (a validação, o processamento) | validar, processar: o verbo, não "realizar" + substantivo |
| a realização / a implementação de | o verbo: "implementar", "validar" |
| endereçar (um problema) | tratar, resolver, corrigir |
| performar | ter desempenho, rodar, responder em |
| através de (sem atravessar nada) | por, por meio de, com |
| a nível de | em, no nível de (quando há níveis de fato) |
| visando, com o intuito de | para |
| sendo que | e, mas, porque: a relação certa |
| o mesmo / a mesma como pronome ("o mesmo foi alterado") | ele, ela, o nome da coisa |
| vou estar fazendo, vamos estar enviando | vou fazer, vamos enviar |
| não apenas X, mas também Y | X e Y |
| basicamente, simplesmente, atualmente (enchimento) | nada |

Anglicismo: identificador e termo consagrado no time ficam como são (commit, merge, deploy, pull request, build, endpoint). Verbo aportuguesado ("deployar", "mergear") só se o projeto já usa; na dúvida, "publicar", "integrar".

## Formato

- Título de commit e de seção com só a primeira letra maiúscula (e nomes próprios), sem ponto final e sem emoji.
- Negrito no máximo um por parágrafo, para o termo que o leitor precisa achar de novo. Itálico quase nunca.
- Lista só para itens paralelos de verdade; duas ideias ligadas são uma frase.
- Travessão para aposto ou separação em campo de formato fixo; no meio da prosa, vírgula, dois-pontos ou ponto resolvem quase sempre.
- Parágrafo curto: uma ideia. Frase acima de umas 35 palavras costuma ser duas.

## Gramática que o texto gerado erra

- Crase: "à disposição", "às 10h", "devido à falha"; nunca antes de verbo ("a partir de", "a fazer") nem de masculino.
- "Onde" só para lugar; para situação ou caso, "em que", "quando", "no qual".
- Concordância com o sujeito posposto: "Foram removidos os testes", não "Foi removido os testes".
- Infinitivo no título de commit (skill `commit`): "corrigir", não "corrigido" nem "corrige".

## Restrições

- Não mudar o conteúdo técnico ao limpar: número, nome de símbolo, caminho, comando e citação ficam idênticos.
- Texto escrito pelo desenvolvedor só é limpo quando ele pede.
- Formato fixo de skill (relatório, Registro, candidato de revisão) segue o formato da skill, mesmo que use travessão e listas.
