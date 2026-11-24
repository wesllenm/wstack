---
name: resilience
description: >
  Orienta timeout, retry, circuit breaker, bulkhead, fallback, cancelamento,
  idempotência e prevenção de falhas em cascata em integrações externas e
  chamadas de modelo de IA.
---

# Resilience

## Objetivo

Falha de dependência externa (provedor de modelo, provedor de código, serviço de terceiros) degrada de forma controlada e nunca perde o estado do trabalho em andamento.

## Quando aplicar

Toda chamada externa nova ou alterada, e toda etapa de workflow que chama algo fora do processo.

## Princípios

- Toda chamada externa tem timeout.
- HTTP com a política padrão de resiliência da stack (timeout, retry, circuit breaker); ajustar a política por cliente quando o SLA exigir.
- Retry só em operação idempotente (ou com `Idempotency-Key`), com backoff exponencial e jitter, em uma única camada (cliente HTTP, orquestrador ou código, nunca empilhados) e respeitando `Retry-After` (429 do provedor de modelo).
- Circuit breaker por dependência, para evitar tempestade de retry.
- Em workflow durável: retry de etapa pela política do motor de workflow, não por loop manual; esperas humanas com evento externo + timeout.
- Limites explícitos por etapa (iterações, tokens, tempo): estourou, para e escala para humano com contexto pronto — nunca loop infinito.
- Propagar o token de cancelamento até o I/O.

## Greenfield

Política padrão compartilhada por todos os clientes; exceções por cliente HTTP documentadas no próprio registro.

## Brownfield

Seguir a política existente; não empilhar retry em cima de retry (cliente HTTP + orquestrador + código).

## Restrições e cuidados

Retry, circuit breaker, bulkhead e fallback dependem de idempotência, SLA, criticidade e risco de retry storm. Não adicionar padrões sem observabilidade, testes e estratégia de degradação. Fallback de modelo (trocar provedor) é decisão de produto, não de código.

## Testes obrigatórios

- timeout da dependência leva ao comportamento definido (retry, falha registrada, escalonamento);
- 429/5xx transitório é re-tentado; 4xx definitivo não é;
- limite de iterações/tokens interrompe e marca o trabalho como bloqueado.

## Checklist de saída

- [ ] timeout em toda chamada externa;
- [ ] retry só em idempotente, sem empilhamento;
- [ ] limites por etapa aplicados;
- [ ] falha observável (log/trace) e testada.
