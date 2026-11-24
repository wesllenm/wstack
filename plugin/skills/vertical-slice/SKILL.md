---
name: vertical-slice
description: >
  Estrutura padrão do código: slices puros por feature, com tudo dentro do
  slice (entrada, regra, acesso a dados), e abstração compartilhada só
  quando duas features precisarem dela.
---

# Vertical Slice

## Objetivo

Cada feature se entende, muda e testa olhando uma pasta só.

## Quando aplicar

Toda feature nova em qualquer projeto de `src/`.

## Padrão

- Organização por feature (caso de uso), não por camada técnica.
- Tudo o que a feature precisa fica dentro do slice: entrada (endpoint, handler, consumidor), validação, regra, acesso a dados, mapeamento e testes.
- Acesso a dados direto no slice, com a ferramenta de persistência do projeto; sem repositório genérico de CRUD (esconde invariantes, contorna outbox e controle de versão, e deixa a consulta vazar).
- Um slice não chama o handler de outro slice. Comunicação entre features por evento ou por módulo compartilhado explícito.
- Regras de arquitetura garantidas por teste de arquitetura da stack (slices não se referenciam; domínio não depende de infraestrutura), sem lista de exceções.

## Quando extrair algo compartilhado

Só quando duas features precisarem da mesma coisa de fato, não por antecipação:

- entidades e invariantes de domínio usadas por mais de uma feature vão para o módulo de domínio (ver `domain-modeling`);
- infraestrutura usada por mais de uma feature (cliente de integração, envio de mensagem) vira componente compartilhado;
- regra duplicada em duas features só é extraída se mudar pelos mesmos motivos; duplicação acidental é aceitável.

Não criar `Shared`, base classes, interfaces ou camadas genéricas antecipadamente. Base mínima só para o que já se repete (carregar por id, adicionar) é permitida; repositório genérico de CRUD continua proibido.

## Greenfield

Adotar desde a primeira feature.

## Brownfield

Features novas em slices; código existente em outra estrutura só migra com tarefa aprovada para isso. Se o projeto tiver outra estrutura consistente, ela prevalece e a divergência vai para `docs/decisions.md`.

## Restrições e cuidados

Interfaces de adaptador para integração externa são fronteiras exigidas pelo produto, não violação desta skill.

## Testes obrigatórios

Testes do slice na fronteira do slice; regra de arquitetura nova quando surgir fronteira nova.

## Exceções e limites

Workflows e orquestrações duráveis cruzam slices por desenho: o workflow chama etapas, e cada etapa pertence a um slice.

## Checklist de saída

- [ ] feature contida no próprio slice;
- [ ] nenhuma abstração criada para um único uso;
- [ ] nenhum slice chamando o interior de outro;
- [ ] testes de arquitetura verdes.
