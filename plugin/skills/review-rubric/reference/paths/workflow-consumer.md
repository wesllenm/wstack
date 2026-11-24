# Review por caminho — workflow Dapr, subscriber e outbox

Aplicar quando o grupo tocar código de workflow ou de mensageria (ex.: `**/Features/Workflow/**`, `**/Infrastructure/Messaging/**`). Complementa o "Sempre verificar" da `SKILL.md`.

Workflow (replay determinístico):
- nada de `DateTime.UtcNow`, `Guid.NewGuid()`, I/O, `Task.Delay` nem configuração lida dentro do workflow; só `CurrentUtcDateTime`; as políticas viajam no input;
- mudar a sequência de activities ou o tipo de entrada de um workflow publicado exige uma versão nova (`...V2`); instância em voo reexecuta o histórico antigo;
- enum no histórico durável sai como número por padrão; manter a serialização por nome e o parse estrito;
- `WaitForExternalEventAsync` com prazo zero lança e com prazo negativo espera para sempre: tratar `restante <= 0` fora do SDK;
- o evento externo só acorda o workflow; a decisão vale pelo registro persistido (ex.: aprovação gravada), não pelo payload do evento.

Activities:
- idempotentes: a mesma activity pode ser reentregue; o registro que ela grava tem Id fixo por execução, e violação da PK conta como já gravado;
- falha de infraestrutura nunca consome tentativa de negócio (ex.: tentativa de um agente de IA); esgotar o retry deve bloquear com motivo tipado, não deixar a instância `Failed` com a entidade parada;
- conferir a decisão e bloquear por prazo é uma activity sobre a entidade rastreada (o token de `Version` serializa com o endpoint).

Subscriber e outbox:
- resposta 200 `SUCCESS`/`DROP` para processado ou descartado (mensagem malformada não trava a fila); 500 só para falha transitória;
- consumidor idempotente: início de workflow confere existência e estado; sinal para instância inexistente é descartado com log;
- dispatcher at-least-once com `eventId` estável, ordem por `(aggregate_id, aggregate_version)`, `dispatched_at IS NULL` literal na consulta (índice parcial) e um publicador por vez (advisory lock);
- eventos críticos passam por um comando do agregado que incrementa `Version`; evento fora do agregado viola `UNIQUE (aggregate_id, aggregate_version)`;
- endpoints do canal sidecar → app só com token em tempo constante, falha fechada, antes da autenticação.
