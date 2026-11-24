# Review por caminho — workflow Dapr, subscriber e outbox

Aplicar quando o grupo tocar `**/Features/Workflow/**` ou `**/Infrastructure/Messaging/**`. Complementa o "Sempre verificar" da `SKILL.md`.

Workflow (replay determinístico):
- nada de `DateTime.UtcNow`, `Guid.NewGuid()`, I/O, `Task.Delay` nem configuração lida dentro do workflow; só `CurrentUtcDateTime`; as políticas viajam no input;
- mudar a sequência de activities ou o tipo de entrada de um workflow publicado exige uma versão nova (`...V2`); instância em voo reexecuta o histórico antigo;
- enum no histórico durável sai como número por padrão; manter a serialização por nome e o parse estrito;
- `WaitForExternalEventAsync` com prazo zero lança e com prazo negativo espera para sempre: tratar `restante <= 0` fora do SDK;
- o evento só acorda o workflow; a decisão vale pelo `Approval` persistido que cobre o hash do artefato da rodada.

Activities:
- idempotentes: a mesma activity pode ser reentregue; o `AgentRun` tem Id fixo por execução e violação da PK conta como já gravado;
- falha de infraestrutura nunca consome a tentativa do agente; esgotar o retry deve bloquear com motivo tipado, não deixar a instância `Failed` com a demanda parada;
- conferir a decisão e bloquear por prazo é uma activity sobre a demanda rastreada (o token de `Version` serializa com o endpoint).

Subscriber e outbox:
- resposta 200 `SUCCESS`/`DROP` para processado ou descartado (mensagem malformada não trava a fila); 500 só para falha transitória;
- consumidor idempotente: início de workflow confere existência e estado; sinal para instância inexistente é descartado com log;
- dispatcher at-least-once com `eventId` estável, ordem por `(demand_id, demand_version)`, `dispatched_at IS NULL` literal na consulta (índice parcial) e um publicador por vez (advisory lock);
- eventos críticos passam por um comando do agregado que incrementa `Version`; evento fora do agregado viola `UNIQUE (demand_id, demand_version)`;
- endpoints do canal sidecar → app só com token em tempo constante, falha fechada, antes da autenticação.
