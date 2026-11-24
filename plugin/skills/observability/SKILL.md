---
name: observability
description: >
  Orienta logs, métricas, traces, correlation IDs e health checks em
  endpoints, integrações, filas, jobs, chamadas de modelo e operações
  relevantes, seguindo a instrumentação OpenTelemetry do projeto.
---

# Observability

## Objetivo

Toda operação relevante pode ser encontrada, seguida e medida em produção com as ferramentas que o projeto já tem, e toda demanda tem um trace que atravessa todos os estágios.

## Padrão

Instrumentação documentada em `.claude/architecture.md`: OpenTelemetry via Aspire ServiceDefaults (logs, traces, métricas), `ILogger` com logging estruturado, dashboard do Aspire em dev, Application Insights/Azure Monitor e Langfuse (via OTel, convenções GenAI) em produção. Não introduzir nova biblioteca, exporter ou backend de observabilidade sem aprovação. [OBS-01]

## Quando aplicar

Endpoints, webhooks, adaptadores, activities de workflow, chamadas de modelo, consumidores, jobs, controle de custo e mudanças de performance.

## Regras que valem em qualquer stack

- Logs estruturados com message template fixo e dados em propriedades (`logger.LogInformation("Estágio {Stage} concluído para {DemandId}", ...)`), nunca interpolação; preferir `LoggerMessage` source-generated em caminho quente. [OBS-02]
- Propagar o trace id entre HTTP, pub/sub do Dapr, workflow e activities; o `DemandId` vai como atributo/baggage em todo span da demanda. [OBS-03]
- Registrar início, falha e resultado de integrações externas e operações assíncronas, com duração. [OBS-04]
- Toda execução de agente registra modelo, versão do prompt/skill, tokens de entrada e saída, custo, duração e resultado (atributos `gen_ai.*` do OTel) — e o mesmo vai para a entidade Execução de agente.
- `ActivitySource` e `Meter` com nome por componente (`SquadOS.Workflow`, `SquadOS.Agents`), registrados no ServiceDefaults.
- Nível de log coerente: erro para falha que exige ação, aviso para degradação tolerada, informação para marcos de negócio, debug desligado em produção.
- Nunca registrar segredos, tokens, senhas, CPF, e-mail, conteúdo de prompt com dados do cliente ou payloads com dados pessoais. Conteúdo de prompt/resposta só vai para o Langfuse, com mascaramento e conforme a política do cliente. [PRV-01] [SEC-03]
- Erro registrado uma vez, no ponto em que é tratado, e não em cada camada que o repassa. [OBS-05]

## Greenfield

Decidido no bootstrap (`docs/decisions.md`). Health checks `/health` e `/alive` do ServiceDefaults em todo serviço.

## Brownfield

Seguir exatamente o padrão encontrado. Lacunas relevantes vão para `docs/gotchas.md`, não para correção fora do escopo.

## Restrições e cuidados

Cardinalidade de métricas: identificador de alta cardinalidade (`DemandId`, usuário) é atributo de span, nunca dimensão de métrica. [OBS-06]

## Testes obrigatórios

Para controle de custo e corte por orçamento: teste de que a execução registra tokens e custo. Instrumentação genérica não exige teste.

## Exceções e limites

Scripts e ferramentas de desenvolvimento não precisam de telemetria.

## Checklist de saída

- [ ] instrumentação no padrão do projeto;
- [ ] trace e `DemandId` propagados nas fronteiras tocadas;
- [ ] integrações, activities e chamadas de modelo com início, falha, resultado, duração (e tokens/custo);
- [ ] nenhum dado sensível em log ou métrica.
