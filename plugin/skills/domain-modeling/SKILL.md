---
name: domain-modeling
description: >
  Orienta linguagem ubíqua, entidades, value objects, agregados, invariantes,
  bounded contexts e eventos para conceitos de negócio relevantes.
---

# Domain Modeling

## Objetivo

Garantir que o código reflita o modelo mental do especialista de negócio. Registrar termos, conceitos e regras em `docs/glossary.md`.

## Quando aplicar

- Feature introduz conceito novo de domínio
- Divergência entre linguagem do código e linguagem do negócio
- Regra de negócio complexa sem representação explícita

## Princípios

- Linguagem ubíqua first: usar os termos que o especialista usa, não os técnicos (no SquadOS, o vocabulário vem do documento de visão: Demanda, Estágio, Portão, Artefato, Aprovação, Execução de agente)
- Entidades têm identidade; Value Objects têm apenas valor (ex.: `DemandId`, `RiskLevel`, `TokenUsage`, `ArtifactHash`)
- Agregados protegem invariantes — nada fora do agregado viola suas regras (a Demanda é o agregado raiz; Artefato e Aprovação são imutáveis depois de gravados) [DOM-01]
- Bounded context define o limite onde um modelo é válido
- Separar o que muda junto do que muda independentemente

## Protocolo com o dev

1. Perguntar pelo nome que o negócio usa para o conceito (não inventar)
2. Perguntar pelas invariantes: o que nunca pode ser violado?
3. Perguntar pelos eventos: o que muda de estado e quando?
4. Registrar no glossary antes de implementar

## Glossary

Atualizar `docs/glossary.md` com formato: [DOC-03]
`**Termo**: definição usada pelo negócio. Diferença de [sinônimo técnico].` Incluir o nome em inglês usado no código.

## Greenfield

Termos do documento de visão já estão no glossário; novos termos entram antes do código.

## Brownfield

- Identificar o vocabulário já estabelecido no código existente
- Não renomear entidades sem impacto claro e aprovação
- Mapear divergências entre modelo atual e modelo do negócio em `docs/decisions.md`

## Restrições e cuidados

Entidades sem dependência de infraestrutura (skill `clean-architecture`). Transição de estado só por método do agregado, nunca por setter público. [ARQ-04] [DOM-01]

## Testes obrigatórios

Cada invariante tem teste unitário no agregado. [DOM-01]

## Exceções e limites

Não aplicar para:
- CRUD simples sem complexidade de negócio
- Entidades de configuração ou infraestrutura

## Checklist de saída

- [ ] termos no glossário;
- [ ] invariantes protegidas no agregado e testadas;
- [ ] eventos de domínio nomeados no passado.
