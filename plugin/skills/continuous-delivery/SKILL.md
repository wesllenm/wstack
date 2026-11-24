---
name: continuous-delivery
description: >
  Orienta fluxo de branch por feature com PR, pipeline reproduzível,
  releases sempre reversíveis sem restaurar banco, compatibilidade entre
  versões, feature flags para lançamento controlado e deploy.
---

# Continuous Delivery

## Objetivo

Toda mudança chega à branch principal revisada e verificada, e toda release pode ser revertida sem restaurar banco.

## Quando aplicar

Toda feature; mudanças em pipeline, publicação ou templates de CI.

## Fluxo de branches

- Uma branch por **entrega** (uma tarefa pode sair em mais de uma), criada a partir da branch principal: `feat/<id>-<slug>`, `fix/<id>-<slug>`, `chore/<slug>`, em `kebab-case`.
- Chaves de configuração e variáveis de ambiente seguem o padrão do ecossistema do perfil de stack.
- Integração por pull request quando a feature estiver completa e verificada, depois dos gates do plano.
- Branch mantida atualizada com a principal durante o trabalho para reduzir conflitos.
- Toda entrega sai atrás de feature flag, desligada por padrão, para lançamento controlado (liberar para parte dos usuários, desligar rápido); a flag não serve para esconder trabalho incompleto. Exceção (correção sem mudança de comportamento, ajuste de configuração) é declarada no `plan.md` com o motivo.
- Abrir PR e fazer push continuam dependendo de autorização explícita.

## Release sempre reversível

Toda release precisa poder voltar para a versão anterior sem restaurar banco:

- o código da versão anterior (N-1) funciona com o schema da versão nova (N);
- mudança incompatível de schema segue expansão-contração (skill `db-evolution`): expandir numa release, migrar código e dados, contrair só numa release posterior, depois que a volta não for mais necessária;
- remoção de coluna, tabela ou campo de contrato nunca acontece na mesma release que deixa de usá-lo;
- eventos, APIs e esquemas de contrato mantêm compatibilidade com consumidores da versão anterior;
- workflows de longa duração em execução continuam rodando após o deploy: mudança na definição de workflow segue o versionamento do mecanismo usado pelo projeto.

Uma mudança que não possa ser revertida assim é decisão de escopo e interrompe o plano.

## Pipeline

- Build reproduzível: toolchain e dependências com versão fixada (lockfile), sem passos manuais.
- Pipeline roda build, testes, análise e os portões da esteira em todo PR; PR com pipeline vermelho não é integrado.
- Deploy idempotente e configuração por ambiente fora do código.
- Publicação em produção exige autorização explícita do tech lead, registrada e presa ao SHA da release (novo commit invalida a autorização); nenhuma outra aprovação (revisão de código, aceite da homologação) a substitui.
- Publicação progressiva (canário) com métricas e limites de SLO definidos antes do deploy e rollback automático quando violados. A feature flag é outro mecanismo: desligá-la não é o rollback do canário.

## Greenfield

Versões fixadas (toolchain e dependências) e workflow de CI na primeira feature de fundação.

## Brownfield

Seguir o pipeline existente; mudanças nele são tarefa própria.

## Restrições e cuidados

A aprovação do plano não autoriza deploy, publicação, push nem alteração em produção (comandos de deploy e publicação, como `kubectl apply`, ficam em `permissions.ask`).

## Testes obrigatórios

Pipeline verde no PR; em expansão-contração, teste de compatibilidade N-1, inclusive para eventos e schemas.

## Exceções e limites

Hotfix segue o mesmo fluxo, com prioridade, nunca commit direto na branch principal.

## Checklist de saída

- [ ] trabalho numa branch de feature;
- [ ] versão N-1 compatível com o schema e os contratos da versão N;
- [ ] nada destrutivo na mesma release que deixa de usar o recurso;
- [ ] entrega atrás de feature flag (ou exceção no `plan.md`);
- [ ] publicação com autorização do tech lead presa ao SHA e canário com rollback automático;
- [ ] pipeline verde.
