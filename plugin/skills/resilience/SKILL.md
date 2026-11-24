---
name: resilience
description: >
  Orienta timeout, retry, circuit breaker, bulkhead, fallback, cancelamento,
  idempotência e prevenção de falhas em cascata em integrações externas e
  chamadas de modelo de IA.
---

# Resilience

## Objetivo

Falha de dependência externa (provedor de modelo, provedor de código, ferramenta de demanda, CI do cliente) degrada de forma controlada e nunca perde estado da demanda.

## Quando aplicar

Toda chamada externa nova ou alterada, e toda activity de workflow que chama algo fora do processo.

## Princípios

- Toda chamada externa tem timeout. [RES-01]
- HTTP via `IHttpClientFactory` com `AddStandardResilienceHandler` (Microsoft.Extensions.Http.Resilience, já no ServiceDefaults do Aspire); ajustar a política por cliente quando o SLA exigir.
- Retry só em operação idempotente (ou com `Idempotency-Key`), com backoff exponencial e jitter, em uma única camada (handler HTTP, Dapr ou código, nunca empilhados) e respeitando `Retry-After` (429 do provedor de modelo). [RES-02] [RES-04]
- Circuit breaker por dependência, para não tempestade de retry. [RES-03]
- Em workflow: retry de activity pela política do Dapr Workflow, não por loop manual; esperas humanas com `WaitForExternalEventAsync` + timeout.
- Limites explícitos por estágio (iterações, tokens, tempo): estourou, para e escala para humano com contexto pronto — nunca loop infinito.
- Propagar `CancellationToken` até o I/O.

## Greenfield

Política padrão no ServiceDefaults; exceções por cliente HTTP documentadas no próprio registro.

## Brownfield

Seguir a política existente; não empilhar retry em cima de retry (HTTP handler + Dapr + código). [RES-04]

## Restrições e cuidados

Retry, circuit breaker, bulkhead e fallback dependem de idempotência, SLA, criticidade e risco de retry storm. Não adicionar padrões sem observabilidade, testes e estratégia de degradação. Fallback de modelo (trocar provedor) é decisão de produto, não de código. [RES-03]

## Testes obrigatórios

- timeout da dependência leva ao comportamento definido (retry, falha registrada, escalonamento);
- 429/5xx transitório é re-tentado; 4xx definitivo não é; [RES-04]
- limite de iterações/tokens interrompe e marca a demanda como Bloqueada.

## Exceções e limites

Chamadas locais ao sidecar do Dapr usam a resiliência do próprio Dapr.

## Checklist de saída

- [ ] timeout em toda chamada externa;
- [ ] retry só em idempotente, sem empilhamento;
- [ ] limites por estágio aplicados;
- [ ] falha observável (log/trace) e testada.
