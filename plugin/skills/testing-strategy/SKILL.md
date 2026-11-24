---
name: testing-strategy
description: >
  Define testes unitários, integração (Testcontainers), arquitetura, mutação,
  E2E (Playwright), carga, mocks, flakiness e gates de CI conforme risco e
  comportamento observável.
---

# Testing Strategy

## Objetivo

Confiança proporcional ao risco, com uma suíte rápida no ciclo local e os portões pesados no CI.

## Quando aplicar

Todo plano SIMPLES ou COMPLEXO define os testes por esta skill.

## Pirâmide

- Unitários (xUnit): lógica isolada, rápidos, sem I/O — rodam no hook Stop
- Integração (`[Trait("Category", "Integration")]`): fronteiras reais com dependências em contêiner (Testcontainers, ex.: Postgres e RabbitMQ), reproduzíveis no CI e na máquina do desenvolvedor, e `WebApplicationFactory` para endpoints [ENV-03]
- Arquitetura (NetArchTest/ArchUnitNET): regras de slice e dependência — rodam no hook
- Mutação (Stryker.NET): nos slices tocados, no CI, para pegar testes escritos "para passar" [TST-06]
- E2E (`[Trait("Category", "E2E")]`, Playwright for .NET): fluxos críticos do usuário — poucos e estáveis [ENV-03]
- Avaliação (quando o produto usa modelo de IA): conjunto de avaliação com casos representativos, a cada mudança de prompt ou modelo
- Carga: quando volume, SLA ou concorrência forem parte do risco

## BDD-first para SIMPLES e COMPLEXA

Antes de implementar, derivar `Dado`, `Quando`, `Então` dos critérios de aceite. Os cenários definem o que implementar e testar, e cada teste referencia o critério que cobre (rastreabilidade). [TST-01] [TDD-01]

## O que testar

- comportamento observável;
- fronteiras: null, vazio, máximo, mínimo, duplicação e falhas;
- não testar detalhes internos sem necessidade.

## Mocks

Mock só em fronteira que você não controla (provedor de modelo, gateway de pagamento, API de terceiro); banco e broker são reais via Testcontainers. Provedor de modelo em teste usa fake determinístico com respostas gravadas. [TST-09]

## Valor e proteção

Aplicar a skill `test-audit`: gate de autoria para todo teste novo ou alterado e proteção do oráculo para os testes existentes. Mais testes não é o objetivo; cada teste precisa proteger comportamento, regressão plausível ou contrato. [TST-02] [TST-05]

## Flakiness

Teste flaky não conta como passando. Corrigir ou quarentenar com issue e prazo. Retries não são solução permanente. Quarentena é alteração de teste existente e segue as regras de autorização da `test-audit`. [TST-08]

## Greenfield

Projetos de teste espelham `src/` em `tests/`; `xunit.runner.json` com paralelismo; Testcontainers reaproveitado por fixture de coleção.

## Brownfield

Criar regressão antes de corrigir bug e caracterização antes de refatoração quando viável. [TST-04] [TDD-07]

## Restrições e cuidados

Saídas (`TestResults/`, traces Playwright, relatórios Stryker) vão para a pasta temporária da sessão (`--results-directory`).

## Testes obrigatórios

Os definidos no plano a partir desta skill.

## Exceções e limites

Spikes e protótipos descartáveis podem não ter testes, desde que não sejam integrados.

## Checklist de saída

- [ ] cenários Dado/Quando/Então derivados dos critérios;
- [ ] camadas certas para o risco;
- [ ] categorias (`Integration`, `E2E`) marcadas;
- [ ] nenhum teste flaky contado como verde.
