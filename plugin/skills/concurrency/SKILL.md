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

- Todo agregado ou registro editável por mais de um usuário ou processo tem controle de versão (coluna de versão, row version ou equivalente da ferramenta de persistência).
- A atualização confere a versão lida; se mudou, a operação falha com conflito.
- Na API, conflito vira `409 Conflict` em Problem Details (skill `api-design`), com orientação ao cliente para recarregar e tentar de novo.
- Não resolver conflito sobrescrevendo silenciosamente ("last write wins"), salvo se o requisito disser que é aceitável, registrado no plano.

## Quando otimista não basta

Contadores, orçamentos consumidos, saldos e sequências com alta disputa podem precisar de operação atômica no banco (update condicional, como `UPDATE ... SET consumed = consumed + @x WHERE consumed + @x <= limit`) ou lock (`SELECT ... FOR UPDATE`). A escolha é justificada no plano, com o motivo.

## Regras gerais

- Operação que lê, decide e grava precisa ser atômica ou protegida por versão.
- Transição de estado só pelo dono da máquina de estados (workflow ou serviço); webhook concorrente vira evento para ele, não escrita direta.
- Não paralelizar sem limite, hipótese e medição (skill `performance`); o paralelismo tem grau máximo explícito (semáforo, pool ou fila limitada).
- Propagar cancelamento em operações longas e assíncronas.
- Evitar bloqueio síncrono de tarefas assíncronas.
- Locks com timeout e ordem de aquisição consistente, para evitar deadlock.
- Trava, arquivo temporário ou reivindicação deixados por execução interrompida precisam ser reconhecíveis como vencidos pela próxima (prazo ou dono verificável); arquivo se grava em caminho temporário e se renomeia. Teste: rodar duas vezes e interromper no meio.
- Estado compartilhado em memória só com proteção explícita; serviços são stateless entre réplicas.

## Greenfield

Token de concorrência configurado na primeira entidade editável.

## Brownfield

Entidades existentes sem controle de versão: registrar em `docs/gotchas.md`; adicionar quando a tarefa tocar nelas.

## Testes obrigatórios

- Duas atualizações concorrentes da mesma versão: uma vence e a outra recebe conflito.
- Em contadores e orçamentos: execução concorrente não produz valor inconsistente nem ultrapassa o limite.

## Exceções e limites

Entidades imutáveis (só inserção, como registros de auditoria) não precisam de controle de versão.

## Checklist de saída

- [ ] entidades editáveis com controle de versão;
- [ ] conflito tratado como 409, sem sobrescrita silenciosa;
- [ ] exceções ao otimista justificadas no plano;
- [ ] teste de concorrência para o caso crítico.
