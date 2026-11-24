---
name: observability
description: >
  Orienta logs, métricas, traces, correlation IDs e health checks em
  endpoints, integrações, filas, jobs e operações relevantes, seguindo a
  instrumentação que o projeto já usa.
---

# Observability

## Objetivo

Toda operação relevante pode ser encontrada, seguida e medida em produção com as ferramentas que o projeto já tem.

## Padrão

Seguir a instrumentação do projeto, documentada em `.claude/architecture.md` pelo bootstrap (biblioteca de log, formato, traces, métricas, onde os dados vão). Não introduzir nova biblioteca, exporter ou backend de observabilidade sem aprovação.

## Quando aplicar

Endpoints críticos, integrações externas, filas e consumidores, jobs, operações financeiras, mudanças de performance e fluxos assíncronos.

## Regras que valem em qualquer stack

- Logs estruturados com mensagem fixa (template) e dados em propriedades, nunca interpolados no texto.
- Propagar o correlation id ou trace id existente entre chamadas HTTP, filas e jobs; o id da entidade principal da operação vai como atributo ou baggage em todo span relacionado.
- Registrar início, falha e resultado de integrações externas e operações assíncronas, com duração.
- Nível de log coerente: erro para falha que exige ação, aviso para degradação tolerada, informação para marcos de negócio, debug desligado em produção.
- Nunca registrar segredos, tokens, senhas, dados de cartão, CPF, e-mail ou payloads com dados pessoais.
- Erro registrado uma vez, no ponto em que é tratado, e não em cada camada que o repassa.

## Greenfield

O bootstrap pergunta a stack de observabilidade e registra a decisão em `docs/decisions.md`. Health checks (`/health` e `/alive`) em todo serviço.

## Brownfield

Seguir exatamente o padrão encontrado. Lacunas relevantes vão para `docs/gotchas.md`, não para correção fora do escopo.

## Restrições e cuidados

Cardinalidade de métricas: identificador de alta cardinalidade (id da entidade, usuário) é atributo de span, nunca dimensão de métrica.

## Testes obrigatórios

Instrumentação genérica não exige teste; a que é requisito de negócio (como contabilização de consumo) tem teste de que a operação a registra.

## Exceções e limites

Scripts e ferramentas de desenvolvimento não precisam de telemetria.

## Checklist de saída

- [ ] instrumentação no padrão do projeto;
- [ ] correlation id ou trace propagado nas fronteiras tocadas;
- [ ] integrações e operações assíncronas com início, falha, resultado e duração;
- [ ] nenhum dado sensível em log ou métrica.
