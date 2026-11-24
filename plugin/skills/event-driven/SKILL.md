---
name: event-driven
description: >
  Orienta eventos, comandos, mensageria, outbox em eventos críticos,
  consumidores idempotentes, retry, DLQ, compatibilidade de payload e sagas
  quando processamento assíncrono for adequado.
---

# Event-Driven

## Objetivo

Processamento assíncrono que não perde o que importa e não duplica efeito.

## Quando aplicar

Integração assíncrona, publicação ou consumo de mensagens, jobs em fila, fluxos de longa duração.

## Quando não aplicar

Não introduzir mensageria para transação simples dentro de um único serviço sem benefício concreto (desacoplamento real, absorção de pico, integração lenta).

## Padrões

### Evento ou comando

- Evento: fato passado, nome no passado (`OrderPaid`), publicado sem saber quem consome.
- Comando: pedido a um destinatário específico (`SendInvoice`), nome no imperativo.

### Outbox

- Obrigatório quando perder o evento causa dano de negócio: efeito financeiro, cobrança, pagamento, notificação obrigatória ao cliente ou ao órgão regulador, e integração cujo desencontro exige reconciliação manual.
- Implementação: tabela de eventos gravada na mesma transação da mudança de estado e publicada por um dispatcher, ou o outbox transacional da plataforma de mensageria quando o armazenamento e o broker forem compatíveis — decisão registrada em `docs/decisions.md` na primeira feature que precisar.
- Nos demais eventos, publicar após o commit da transação e registrar falha de publicação em log com correlation id; perda eventual é aceita.
- Classificar cada evento novo como crítico ou não crítico no plano.

### Consumidores

- Todo consumidor é idempotente: mensageria entrega pelo menos uma vez. Deduplicar por id da mensagem ou por chave de negócio.
- Retry limitado com backoff exponencial e jitter; esgotado, mensagem vai para DLQ com o motivo.
- DLQ monitorada; mensagem em DLQ não é descartada silenciosamente.
- Não depender de ordem entre mensagens, salvo quando o broker garantir por chave de partição e isso estiver documentado.

### Contrato de payload

- Só mudanças aditivas no payload de um evento publicado.
- Quebra de contrato gera novo tipo ou nova versão do evento, com convivência até os consumidores migrarem.
- Nome do evento no passado, em minúsculas com ponto (`order.paid`), com a versão no contrato.
- Payload carrega id do evento, tipo, versão, data de ocorrência, id da entidade principal e correlation id (trace).
- Não trafegar dados pessoais nem conteúdo de documentos do negócio no payload: referência e hash.

### Sagas

Só quando um fluxo atravessa serviços e precisa de compensação. Cada passo tem compensação definida e o estado da saga é persistido.

## Brownfield

Seguir o broker, as convenções de nome e o formato de envelope existentes. Não introduzir outbox em eventos não críticos só por consistência.

## Restrições e cuidados

Webhook de entrada não processa síncrono: valida assinatura, grava (idempotente) e publica.

## Testes obrigatórios

- Consumidor processando a mesma mensagem duas vezes sem efeito duplicado.
- Falha no consumidor leva a retry e, esgotado, à DLQ.
- Em evento crítico: evento gravado no outbox na mesma transação da mudança de estado.

## Exceções e limites

Notificações em tempo real para a interface (push, WebSocket) são best-effort e não usam outbox.

## Checklist de saída

- [ ] evento classificado como crítico ou não crítico;
- [ ] outbox nos críticos;
- [ ] consumidor idempotente;
- [ ] retry limitado e DLQ;
- [ ] payload compatível com a versão anterior e sem dados pessoais.
