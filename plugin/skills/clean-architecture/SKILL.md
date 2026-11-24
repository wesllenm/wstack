---
name: clean-architecture
description: >
  Critérios para quando introduzir camadas, ports, adapters e inversão de
  dependência. Não é a estrutura padrão: o padrão são slices com controller,
  service e repositório por agregado (skill vertical-slice); esta
  skill diz quando uma abstração adicional se justifica.
---

# Clean Architecture

## Objetivo

Introduzir separação de camadas e abstrações só onde elas pagam o próprio custo.

## Quando aplicar

Ao considerar criar interface, camada, port/adapter ou módulo compartilhado.

## Padrão

A estrutura padrão é a da skill `vertical-slice`: slice com controller, service e repositório por agregado, sem camadas genéricas. As portas exigidas por esse desenho (`IUnitOfWork`, `I<Agregado>Repository`, exceções de aplicação) ficam em `Common` e são implementadas em `Infrastructure/Persistence`; não contam como "abstração nova" a justificar pelos critérios abaixo. Esta skill não impõe domínio, aplicação e infraestrutura como camadas obrigatórias, e **não autoriza repositório genérico de CRUD**. [ARQ-01] [ARQ-03]

## Quando introduzir uma abstração (port e adapter)

Somente quando pelo menos um critério for verdadeiro: [ARQ-03]

1. duas ou mais features precisam da mesma dependência externa e da mesma forma de usá-la;
2. a dependência externa precisa ser trocável por requisito real (dois provedores, ambiente de teste sem acesso ao serviço);
3. a regra de negócio precisa ser testada sem a infraestrutura e o teste pela fronteira real é inviável ou lento demais.

Quando o produto exige provedores trocáveis por requisito (ex.: mais de um provedor de pagamento, storage pela API S3, feature flags via OpenFeature), essas portas ficam registradas em `docs/decisions.md` como previstas; outras precisam dos critérios.

Mesmo então, a interface é definida pelo uso (o que o chamador precisa) e não pela ferramenta (não espelhar a API da biblioteca).

## Quando isolar o domínio

Quando entidades e invariantes são usadas por mais de uma feature (skill `domain-modeling`). O domínio não depende de infraestrutura: nada de acesso a banco, HTTP, fila ou Dapr dentro de entidades. [ARQ-04]

## Greenfield

Modelo de domínio (ex.: `<App>/Common/<Agregado>`) sem referência a EF Core, Dapr ou ASP.NET; regra NetArchTest garante.

## Brownfield

Se o projeto já usa Clean Architecture de forma consistente, seguir a estrutura existente; esta skill passa a orientar só o que é novo, e a divergência vai para `docs/decisions.md`. Não remover camadas existentes fora do escopo.

## Restrições e cuidados

Não aplicar:

- CRUD simples, protótipo, script, integração pontual;
- "para o caso de trocar o banco um dia" sem requisito;
- interface com uma única implementação e nenhum dos critérios acima (exceto as portas do desenho padrão: repositório por agregado e UoW).

## Testes obrigatórios

Regra de arquitetura para cada fronteira nova.

## Exceções e limites

Interfaces exigidas por framework (ex.: `IHostedService`) não contam como abstração nova.

## Checklist de saída

- [ ] toda abstração nova atende a um dos três critérios, registrado no plano;
- [ ] interfaces definidas pelo uso;
- [ ] domínio sem dependência de infraestrutura.
