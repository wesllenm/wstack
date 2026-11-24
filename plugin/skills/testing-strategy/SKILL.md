---
name: testing-strategy
description: >
  Define testes unitários, integração, arquitetura, mutação, E2E, carga,
  mocks, flakiness e gates de CI conforme risco e comportamento observável.
---

# Testing Strategy

## Objetivo

Confiança proporcional ao risco, com uma suíte rápida no ciclo local e os portões pesados no CI.

## Quando aplicar

Todo plano SIMPLES ou COMPLEXO define os testes por esta skill.

## Pirâmide

- Unitários: lógica isolada, rápidos, sem I/O — rodam no hook Stop
- Integração (categoria `Integration`): fronteiras reais (banco, fila, API, contrato externo) com dependências em contêiner, reproduzíveis no CI e na máquina do desenvolvedor, e teste de endpoint pelo host da própria aplicação
- Arquitetura (ferramenta da stack): regras de slice e dependência — rodam no hook
- Mutação (ferramenta da stack): nos slices tocados, no CI, para pegar testes escritos "para passar"
- E2E (categoria `E2E`): fluxos críticos do usuário — poucos e estáveis
- Avaliação (conjunto de casos reais): a cada mudança de prompt, skill ou modelo dos agentes do produto, quando houver
- Carga: quando volume, SLA ou concorrência forem parte do risco

## BDD-first para SIMPLES e COMPLEXA

Antes de implementar, derivar `Dado`, `Quando`, `Então` dos critérios de aceite. Os cenários definem o que implementar e testar.

## O que testar

- comportamento observável;
- fronteiras: null, vazio, máximo, mínimo, duplicação e falhas;
- não testar detalhes internos sem necessidade.

## Mocks

Mock só em fronteira que você não controla (provedor de modelo, provedor de código, serviço de terceiros); banco e broker são reais em contêiner. Provedor de modelo em teste usa fake determinístico com respostas gravadas.

## Valor e proteção

Aplicar a skill `test-audit`: gate de autoria para todo teste novo ou alterado e proteção do oráculo para os testes existentes. Mais testes não é o objetivo; cada teste precisa proteger comportamento, regressão plausível ou contrato.

## Flakiness

Teste flaky não conta como passando. Corrigir ou quarentenar com issue e prazo. Retries não são solução permanente. Quarentena é alteração de teste existente e segue as regras de autorização da `test-audit`.

## Greenfield

Projetos de teste espelham `src/` em `tests/`; paralelismo habilitado no runner; dependências em contêiner reaproveitadas por fixture compartilhada.

## Brownfield

Criar regressão antes de corrigir bug e caracterização antes de refatoração quando viável.

## Restrições e cuidados

Saídas (resultados de teste, traces do E2E, relatórios de mutação) vão para a pasta temporária da sessão.

## Testes obrigatórios

Os definidos no plano a partir desta skill.

## Exceções e limites

Spikes e protótipos descartáveis podem não ter testes, desde que não sejam integrados.

## Checklist de saída

- [ ] cenários Dado/Quando/Então derivados dos critérios;
- [ ] camadas certas para o risco;
- [ ] categorias (`Integration`, `E2E`) marcadas;
- [ ] nenhum teste flaky contado como verde.
