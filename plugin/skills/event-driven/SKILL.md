---
name: event-driven
description: >
  Orienta eventos, comandos, mensageria (pub/sub do Dapr sobre RabbitMQ),
  outbox em eventos críticos, consumidores idempotentes, retry, DLQ,
  compatibilidade de payload e sagas quando processamento assíncrono for adequado.
---

# Event-Driven

## Objetivo

Processamento assíncrono que não perde o que importa e não duplica efeito.

## Quando aplicar

Integração assíncrona, publicação ou consumo de mensagens, jobs em fila, fluxos de longa duração.

## Quando não aplicar

Não introduzir mensageria para transação simples dentro de um único serviço sem benefício concreto (desacoplamento real, absorção de pico, integração lenta). Fluxo de estágios de uma demanda é **workflow** (skill `dapr-workflow`), não coreografia de eventos.

## Padrões

### Evento ou comando

- Evento: fato passado, nome no passado (`DemandCaptured`, `StageCompleted`), publicado sem saber quem consome.
- Comando: pedido a um destinatário específico (`MirrorStatusToSource`), nome no imperativo.

### Mensageria

- Pub/sub do Dapr (`DaprClient.PublishEventAsync`, assinatura declarativa ou programática) com RabbitMQ como componente padrão; trocar de broker é só configuração do componente. Não usar o cliente do RabbitMQ diretamente.
- Envelope CloudEvents (padrão do Dapr).

### Outbox

- Obrigatório quando perder o evento causa dano de negócio: transição de estado da Demanda, aprovação registrada, espelho obrigatório na ferramenta do cliente, efeito de custo (corte de orçamento) e integração cujo desencontro exige reconciliação manual. [EVT-02]
- Implementação: tabela `Evento` (modelo de dados) gravada na mesma transação da mudança de estado e publicada por um dispatcher; ou o outbox transacional do Dapr quando o state store e o pub/sub forem compatíveis — decisão registrada em `docs/decisions.md` na primeira feature que precisar.
- Nos demais eventos, publicar após o commit da transação e registrar falha de publicação em log com correlation id; perda eventual é aceita.
- Classificar cada evento novo como crítico ou não crítico no plano. [EVT-01]

### Consumidores

- Todo consumidor é idempotente: mensageria entrega pelo menos uma vez. Deduplicar por id da mensagem (CloudEvents `id`) ou por chave de negócio. [EVT-03]
- Retry limitado com backoff exponencial e jitter (política de resiliência do Dapr); esgotado, mensagem vai para dead-letter topic com o motivo. [EVT-04]
- DLQ monitorada; mensagem em DLQ não é descartada silenciosamente. [EVT-04]
- Não depender de ordem entre mensagens, salvo quando o broker garantir por chave de partição e isso estiver documentado. [EVT-07]

### Contrato de payload

- Só mudanças aditivas no payload de um evento publicado. [EVT-05]
- Quebra de contrato gera novo tipo ou nova versão do evento, com convivência até os consumidores migrarem.
- Nome do evento no passado, em minúsculas com ponto (`demand.captured`), com a versão no contrato. [NOM-04]
- Payload carrega id do evento, tipo, versão, data de ocorrência, `DemandId` e correlation id (trace). [EVT-06]
- Não trafegar dados pessoais nem conteúdo de artefato no payload: referência e hash. [PRV-04]

### Sagas

Só quando um fluxo atravessa serviços e precisa de compensação. No SquadOS, a saga natural é o próprio Dapr Workflow: cada passo com compensação definida e estado persistido pelo runtime.

## Greenfield

Componentes Dapr (pub/sub, state store) declarados no AppHost do Aspire.

## Brownfield

Seguir o broker, as convenções de nome e o formato de envelope existentes. Não introduzir outbox em eventos não críticos só por consistência.

## Restrições e cuidados

Webhook de entrada não processa síncrono: valida assinatura, grava (idempotente) e publica. [SEC-08]

## Testes obrigatórios

- Consumidor processando a mesma mensagem duas vezes sem efeito duplicado.
- Falha no consumidor leva a retry e, esgotado, à DLQ.
- Em evento crítico: evento gravado no outbox na mesma transação da mudança de estado. [EVT-02]

## Exceções e limites

Notificações em tempo real do portal (SignalR) são best-effort e não usam outbox.

## Checklist de saída

- [ ] evento classificado como crítico ou não crítico;
- [ ] outbox nos críticos;
- [ ] consumidor idempotente;
- [ ] retry limitado e DLQ;
- [ ] payload compatível com a versão anterior e sem dados pessoais.
