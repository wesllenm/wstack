---
name: tdd
description: >
  Red-green-refactor para features novas, bugs e mudanças de comportamento,
  usando testes como especificação e ferramenta de design.
---

# TDD — Test-Driven Development

## Objetivo

Produzir código correto, legível e verificável por ciclos curtos, com testes derivados dos critérios de aceite antes do código.

## Quando aplicar

Feature nova, bug, mudança de comportamento, regra de negócio, transição de estado de entidade de negócio, contrato ou transformação importante (ex.: adaptador convertendo dado externo no modelo interno).

## Ciclo

RED: criar teste que descreve comportamento e falha pelo motivo esperado (não por erro de compilação ou setup).
GREEN: implementar a menor solução correta.
REFACTOR: melhorar estrutura preservando comportamento, com a suíte verde a cada passo.

## Princípios

- testar comportamento observável na fronteira do slice (handler, endpoint, etapa de workflow), não detalhes internos;
- todo teste novo passa pelo gate de autoria da skill `test-audit`;
- criar regressão antes de corrigir bug quando viável, e confirmar que ela falha pelo motivo esperado antes da correção;
- em GREEN, fazer o teste passar mudando a implementação, nunca o teste existente;
- nome do teste descreve o cenário em linguagem do domínio: `Aprovar_pedido_fora_do_prazo_nao_avanca_etapa`;
- executar verificação após cada mudança relevante;
- não usar cobertura de linhas como objetivo único; o teste de mutação nos slices tocados, onde configurado, é o termômetro de valor.

## Bug: depuração guiada por evidência

1. Reproduzir na superfície em que o bug aparece (teste, script ou a skill `verify-<app>`, §12.24) antes de mexer em produção. Se não reproduz, provocar o gatilho, apertar as condições ou instrumentar até reproduzir; perguntar ao desenvolvedor só depois de esgotar isso, dizendo por quê.
2. Listar as hipóteses e eliminar, a cada passo, a que corta mais espaço do problema, com evidência de execução (log, instrumentação, estado lido), não com leitura do código. Para regressão, `git bisect` com o teste de reprodução.
3. Hipótese refutada pela evidência: reverter tudo que ela motivou. Mudança "por via das dúvidas" é hipótese, não correção, e não vai para o commit.
4. Achar onde o sistema errou primeiro, não onde o erro apareceu. Perguntar se o estado que disparou o sintoma é legítimo: se é, o código que quebrou nele é a causa; se o estado nunca deveria existir, uma verificação no ponto da quebra esconde o bug, e a correção é achar quem produziu o estado. Guard, retry, exceção engolida, valor limitado à força e estado descartado são os jeitos usuais de esconder bug.
5. Falha que só aparece depois de reiniciar: suspeitar primeiro de estado persistido (configuração, cache, arquivo de lock, estado serializado).
6. Procurar o padrão, não só a ocorrência: corrigir todos os lugares com a mesma falha.
7. O teste de regressão entra no histórico antes da correção, ou no mesmo commit com a falha anterior registrada no relatório.
8. Se o fato decisivo exigiu escavação funda, propor o sinal barato e sempre ligado (log, métrica, assert) que o teria mostrado de primeira, como aprendizado.

## Greenfield

TDD desde o primeiro slice. Critérios de aceite em Gherkin viram cenários `Dado/Quando/Então` (skill `testing-strategy`) e cada cenário vira pelo menos um teste.

## Brownfield

Usar caracterização ou regressão quando viável. Não exigir cobertura total de legado.

## Restrições e cuidados

- Workflows duráveis: testar a lógica de orquestração com as etapas substituídas por fakes e o tempo controlado; não depender de espera real.
- Não criar seam de produção só para teste (ver `test-audit`).
- Marcar integração pela categoria da stack para manter o hook rápido.

## Testes obrigatórios

- ao menos um teste por critério de aceite tocado;
- regressão para todo bug corrigido, com evidência de falha antes da correção.

## Exceções e limites

Spikes, protótipos, documentação, configuração, ajustes visuais, composição simples (injeção de dependência, wiring), infraestrutura sem lógica e correções triviais podem usar fluxo pragmático, com a justificativa no relatório.

## Checklist de saída

- [ ] comportamento definido;
- [ ] teste criado ou exceção justificada;
- [ ] teste executado e visto falhando (RED);
- [ ] implementação mínima;
- [ ] testes passando;
- [ ] refatoração com suíte verde;
- [ ] resultado registrado.
