---
name: blast-radius
description: >
  Mapeia o que uma mudança pode quebrar fora do diff: símbolos e comportamentos que mudam, quem depende deles além do
  que o grep acha (versão fixada e fonte de biblioteca, concorrência e tempo de execução, JSON da API, colunas e
  índices, feature flags, consumidores de mensagem), o fato de segurança que torna a mudança segura e a execução que o
  prova. Carregar no plano de toda tarefa CRITICA e de COMPLEXA que toque contrato público, migration ou mensageria;
  o resultado vai para o contrato do sprint e para o foco das lentes.
argument-hint: <a mudança planejada ou o diff: símbolos, arquivos, commits>
---

# Blast radius

Responde "o que esta mudança pode quebrar que não está no diff" antes de escrever o código, e prova o fato do qual a
segurança dela depende. O `lead` roda esta skill no plano (`reference/pipeline.md`); o resultado entra no sprint
contract e vira ponto de foco das lentes, e em CRITICA o `review-critical` recebe o fato de segurança para tentar
quebrá-lo depois do código. A evidência de cada afirmação usa a escada da `review-rubric` (Degraus de prova).

## Passos

1. **Ler a mudança.** Os símbolos que mudam (assinatura, tipo, comportamento, formato persistido ou publicado), cada
   um com `arquivo:linha`; os commits da tarefa, quando já houver.
2. **Escrever o fato de segurança:** a única afirmação que, se for verdade, torna a mudança segura ("toda leitura de
   `Pedido.Status` trata o valor novo", "nenhum consumidor da fila `pedidos` lê o campo removido").
3. **Procurar além do grep**, em cada uma das frentes, e dizer o comando ou o arquivo de cada busca:
   - versões fixadas (`packages.lock.json`, `package-lock.json`, `Cargo.lock`) e o código-fonte da biblioteca chamada
     nessa versão;
   - tempo de execução e concorrência: o que roda no descarte, no cancelamento, em paralelo, em retry;
   - o JSON que a API devolve e os contratos públicos (OpenAPI, schemas, clientes gerados);
   - colunas e índices do banco que a mudança lê, grava ou deixa de usar (`database-helper` quando depender do dado);
   - feature flags que ligam ou desligam o caminho;
   - consumidores de mensagem (Service Bus, RabbitMQ, pub/sub) e outro serviço que lê os mesmos bytes.
   Busca vazia é resultado válido: registrar o comando e "nenhum".
4. **Classificar cada risco** por probabilidade (alta, média, baixa) e custo se acontecer (dado perdido ou corrompido,
   contrato quebrado, indisponibilidade, cosmético).
5. **Provar o fato de segurança** rodando um teste ou script contra o código real (degrau 4), ou conduzindo na
   aplicação pela `verify-<app>` (degrau 5). Antes do código, a prova é o teste que vai falhar se o fato não valer: ele
   entra no sprint contract, e o veredito sai depois que a implementação o roda.
6. **Responder** no formato abaixo.

## Resposta

```text
Mudança: <o que muda, com arquivo:linha por símbolo>
Fato de segurança: <uma frase> — VERIFICADO (degrau 4 ou 5: comando → resultado) | NÃO VERIFICADO (a prova rodou e o fato não vale) | INCONCLUSIVO (degrau atual e a prova que falta)
Riscos confirmados:
- <risco> — probabilidade — custo — arquivo:linha — degrau
Descartados:
- <risco> — por quê — arquivo:linha ou comando da busca vazia
Reprodução: <comando que roda a prova do fato de segurança>
Foco para as lentes: <os pontos que o contrato e a revisão precisam cobrir>
```

Cada afirmação leva o rótulo da escada: **medida** (degraus 4 e 5), **inferida** (2 e 3) ou **palpite** (1). Fato de
segurança que fica em palpite vai ao plano como pergunta, não como premissa. Os vereditos são os da prova por
execução da `review-rubric` e do playbook `sem-playbook.md` da `lead`; INCONCLUSIVO conta como `não provado` no
`revisao.md` (o commit de CRITICA espera o desenvolvedor).

## Restrições

- Citar só código real, aberto nesta sessão: nunca inventar chamador, API, coluna ou consumidor. O que não deu para
  abrir vai como "não verificado", não como risco descartado.
- Sem edição de código de produção: a skill lê, busca e roda testes e scripts na pasta temporária da sessão. O teste
  que prova o fato entra no código pelo sprint contract, com o gate de autoria da `test-audit`.
- Consultar outros modelos não faz parte desta skill.
