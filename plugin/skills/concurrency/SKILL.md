---
name: concurrency
description: >
  Orienta controle de concorrência otimista por padrão, race conditions,
  atomicidade, locks, deadlocks, cancelamento, paralelismo limitado,
  idempotência e isolamento de estado.
---

# Concurrency

## Objetivo

Atualizações simultâneas não perdem dados nem violam invariantes.

## Quando aplicar

Entidade editável por mais de um ator (pessoa, workflow, webhook), contadores e orçamentos, processamento paralelo.

## Padrão: concorrência otimista

- Todo agregado ou registro editável por mais de um usuário ou processo tem controle de versão (no Npgsql, token de concorrência via `xmin` ou coluna `version` com `IsConcurrencyToken`). [CON-01]
- A atualização confere a versão lida; se mudou, a operação falha com `DbUpdateConcurrencyException`.
- Na API, conflito vira `409 Conflict` em Problem Details (skill `api-design`), com orientação ao cliente para recarregar e tentar de novo. [CON-02]
- Não resolver conflito sobrescrevendo silenciosamente ("last write wins"), salvo se o requisito disser que é aceitável, registrado no plano.

## Quando otimista não basta

Contadores, saldos e cotas (ex.: consumo por mês) e sequências com alta disputa podem precisar de operação atômica no banco (`ExecuteUpdate` com `SET consumed = consumed + @x WHERE consumed + @x <= limit`) ou lock (`SELECT ... FOR UPDATE`). A escolha é justificada no plano, com o motivo. [CON-03]

## Regras gerais

- Antes de sincronizar, eliminar o compartilhamento: um arquivo, chave, partição ou pasta por ator; serializar só a invariante que não separa, dita em uma frase (skill `separate-before-serializing`). Instrução pedindo cuidado não é controle de concorrência.
- Operação que lê, decide e grava precisa ser atômica ou protegida por versão.
- Quando um orquestrador (workflow) é dono do estado de uma entidade, a transição só passa por ele; webhook concorrente vira evento para o workflow, não escrita direta.
- Não paralelizar sem limite, hipótese e medição (skill `performance`); usar `Parallel.ForEachAsync` com `MaxDegreeOfParallelism` ou `Channel<T>` limitado. [CON-04]
- Propagar cancelamento em operações longas e assíncronas. [CON-04]
- Evitar bloqueio síncrono de tarefas assíncronas (`.Result`, `.Wait()`).
- Locks com timeout e ordem de aquisição consistente, para evitar deadlock. [CON-05]
- Trava, arquivo temporário ou reivindicação deixados por execução interrompida precisam ser reconhecíveis como vencidos pela próxima (prazo ou dono verificável); arquivo se grava em caminho temporário e se renomeia. Teste: rodar duas vezes e interromper no meio.
- Estado compartilhado em memória só com proteção explícita; serviços são stateless entre réplicas. [CON-05]

## Greenfield

Token de concorrência configurado na primeira entidade editável.

## Brownfield

Entidades existentes sem controle de versão: registrar em `docs/gotchas.md`; adicionar quando a tarefa tocar nelas.

## Restrições e cuidados

Quando o projeto usar Dapr Workflow, o código do workflow é single-threaded e determinístico; paralelismo de activities via `Task.WhenAll` sobre `CallActivityAsync`, nunca threads próprias.

## Testes obrigatórios

- Duas atualizações concorrentes da mesma versão: uma vence e a outra recebe conflito.
- Em contadores e orçamentos: execução concorrente não produz valor inconsistente nem ultrapassa o limite.

## Exceções e limites

Entidades imutáveis (ex.: registro de auditoria, evento) não precisam de controle de versão: só inserção.

## Checklist de saída

- [ ] entidades editáveis com controle de versão;
- [ ] conflito tratado como 409, sem sobrescrita silenciosa;
- [ ] exceções ao otimista justificadas no plano;
- [ ] teste de concorrência para o caso crítico.
