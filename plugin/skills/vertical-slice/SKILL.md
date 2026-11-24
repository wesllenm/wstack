---
name: vertical-slice
description: >
  Estrutura padrão do código: slices por feature com controller fino,
  service por caso de uso e repositório por agregado (ADR 0003), e
  abstração compartilhada só quando duas features precisarem dela.
---

# Vertical Slice

## Objetivo

Cada feature se entende, muda e testa olhando uma pasta só.

## Quando aplicar

Toda feature nova em qualquer projeto de `src/`.

## Padrão

- Organização por feature (caso de uso), não por camada técnica: `src/SquadOS.App/Features/Demands/CaptureDemand/`. [ARQ-01]
- Tudo o que a feature precisa fica dentro do slice: `<Caso>Controller` (entrada HTTP), `<Caso>Service` (orquestração), DTOs de request/response, validação, mapeamento e testes (espelhados em `tests/`). Outras entradas (consumidor, activity) também ficam no slice e chamam a service.
- Desenho em três responsabilidades (ADR 0003, substitui o `DbContext` direto e a Minimal API do ADR 0002): [ARQ-01]
  - **Controller** (`[ApiController]`): só recebe, chama a service e devolve. Não referencia EF Core, `Infrastructure.Persistence`, repositório, `IUnitOfWork` nem `DbContext`.
  - **Service** (uma por caso de uso): orquestra (carrega o agregado pelo repositório, chama o comando de domínio, chama a UoW uma vez, usa `IObjectStorage` e portas de workflow). A regra de negócio fica no agregado (`Demand`), não na service. Não referencia EF Core, Npgsql nem `Infrastructure.Persistence`.
  - **Repositório por agregado raiz**: interface em `Common/<Agregado>/I<Agregado>Repository`, implementação em `Infrastructure/Persistence/Repositories/`. Métodos de intenção, sem `SaveChanges*`, sem dependência de `Features`. **Sem repositório genérico de CRUD** (`Update`/`ExecuteUpdate` genéricos contornam outbox, triggers e token de versão; `IQueryable` vaza).
  - **Unit of Work**: porta `IUnitOfWork` em `Common/Persistence/` (implementada pelo `SquadOsDbContext`), chamada só pela service; traduz concorrência, unicidade e commit incerto para exceções de aplicação (`Common/Persistence/`).
- Consultas de leitura (telas, relatórios, métricas) são classes separadas, com projeção e `AsNoTracking`, sem repositório: interface (e os tipos que ela devolve) em `Common/<Agregado>/`, implementação em `Infrastructure/Persistence/Queries/`: a infraestrutura não depende de `Features` (emenda M1 do ADR 0003).
- Um slice não chama o handler de outro slice. Comunicação entre features por evento ou por módulo compartilhado explícito. [ARQ-02]
- Regras de arquitetura garantidas por NetArchTest/ArchUnitNET em `tests/SquadOS.ArchitectureTests` (slices não se referenciam; domínio não depende de infraestrutura; controller sem EF/repositório; service sem EF/Npgsql/`Infrastructure.Persistence`; repositório sem `SaveChanges*` e sem `Features`), sem lista de exceções. [ARQ-04]

## Quando extrair algo compartilhado

Só quando duas features precisarem da mesma coisa de fato, não por antecipação:

- entidades e invariantes de domínio usadas por mais de uma feature vão para o módulo de domínio (ver `domain-modeling`);
- infraestrutura usada por mais de uma feature (cliente de provedor de código, cliente de modelo, storage S3) vira componente compartilhado;
- regra duplicada em duas features só é extraída se mudar pelos mesmos motivos; duplicação acidental é aceitável.

Não criar `Shared`, base classes, interfaces ou camadas genéricas antecipadamente. Base mínima só para o que já se repete (carregar por id, adicionar) é permitida; repositório genérico de CRUD continua proibido. [ARQ-05]

## Greenfield

Adotar desde a primeira feature.

## Brownfield

Features novas em slices com controller, service e repositório; código existente em outra estrutura só migra com demanda aprovada para isso (o próprio SquadOS concluiu a migração em 2026-10-27). Se o projeto tiver outra estrutura consistente, ela prevalece e a divergência vai para `docs/decisions.md`.

## Restrições e cuidados

Interfaces de adaptador (fonte de demanda, provedor de código) são fronteiras exigidas pelo produto (skill `source-adapters`), não violação desta skill.

## Testes obrigatórios

Testes do slice na fronteira do slice; regra de arquitetura nova quando surgir fronteira nova.

## Exceções e limites

Workflows Dapr orquestram vários slices por desenho: o workflow chama activities, e cada activity pertence a um slice.

## Checklist de saída

- [ ] feature contida no próprio slice;
- [ ] controller fino, service sem EF, repositório por agregado sem `SaveChanges`;
- [ ] nenhuma abstração criada para um único uso (o repositório por agregado e a UoW são exigidos pelo ADR 0003); [ARQ-03]
- [ ] nenhum slice chamando o interior de outro;
- [ ] testes de arquitetura verdes.
