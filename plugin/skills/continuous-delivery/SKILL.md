---
name: continuous-delivery
description: >
  Orienta fluxo de branch por feature com PR, pipeline reproduzível,
  releases sempre reversíveis sem restaurar banco, compatibilidade entre
  versões, feature flags (OpenFeature) para lançamento controlado e deploy.
---

# Continuous Delivery

## Objetivo

Toda mudança chega à branch principal revisada e verificada, e toda release pode ser revertida sem restaurar banco.

## Quando aplicar

Toda feature; mudanças em pipeline, AppHost de publicação ou templates de CI.

## Fluxo de branches

- Uma branch por **entrega** (uma demanda pode sair em mais de uma), criada a partir de `main`: `feat/<id>-<slug>`, `fix/<id>-<slug>`, `chore/<slug>`, em `kebab-case`. [DEL-02] [NOM-05]
- Chaves de configuração e variáveis de ambiente seguem o padrão do ecossistema do perfil (.NET: `Secao__Chave`; demais: `MAIUSCULAS_COM_SUBLINHADO`). [NOM-05]
- Integração por pull request quando a feature estiver completa e verificada, depois dos gates do plano. [DEL-02]
- Branch mantida atualizada com a principal durante o trabalho para reduzir conflitos.
- Toda entrega sai atrás de feature flag (OpenFeature), desligada por padrão, para lançamento controlado (liberar para parte dos usuários, desligar rápido); a flag não serve para esconder trabalho incompleto. Exceção (correção sem mudança de comportamento, ajuste de configuração) é declarada no `plan.md` com o motivo. [squados] O SquadOS ainda não cumpre esta regra (não tem OpenFeature; ver `docs/decisions.md`). [DEL-05]
- Abrir PR e fazer push continuam dependendo de autorização explícita.

## Release sempre reversível

Toda release precisa poder voltar para a versão anterior sem restaurar banco: [DEL-01]

- o código da versão anterior (N-1) funciona com o schema da versão nova (N);
- mudança incompatível de schema segue expansão-contração (skill `db-evolution`): expandir numa release, migrar código e dados, contrair só numa release posterior, depois que a volta não for mais necessária; [DAT-01]
- remoção de coluna, tabela ou campo de contrato nunca acontece na mesma release que deixa de usá-lo; [DAT-02]
- eventos, APIs e JSON Schemas de artefato mantêm compatibilidade com consumidores da versão anterior; [EVT-05]
- workflows Dapr em execução continuam rodando após o deploy: mudança na definição de workflow segue versionamento (skill `dapr-workflow`).

Uma mudança que não possa ser revertida assim é decisão de escopo e interrompe o plano.

## Pipeline

- Build reproduzível: SDK fixado em `global.json`, Central Package Management (`Directory.Packages.props`) com versões fixas, `package-lock.json` no portal, sem passos manuais. [DEL-03]
- Pipeline roda build, testes, análise e os portões da esteira em todo PR; PR com pipeline vermelho não é integrado.
- Deploy pelo AppHost do Aspire (Kubernetes, Container Apps ou Compose), idempotente, configuração por ambiente fora do código. [DEL-04]
- Publicação em produção exige autorização explícita do tech lead, registrada e presa ao SHA da release (novo commit invalida a autorização); nenhuma outra aprovação (revisão de código, aceite da homologação) a substitui. [DEL-06]
- Publicação progressiva (canário) com métricas e limites de SLO definidos antes do deploy e rollback automático quando violados. A feature flag é outro mecanismo: desligá-la não é o rollback do canário. [DEL-07]

## Execução em contêiner

Premissa (`docs/decisions.md`, 2026-10-26): construir, testar e rodar acontece em contêiner, no desenvolvimento, no CI e nos sistemas dos clientes.

- Toda aplicação tem `Dockerfile` (multi-estágio, usuário sem privilégio, imagem base fixada por versão) e roda em contêiner. [ENV-01]
- Ambiente de desenvolvimento e de teste sobe com um comando (Compose ou equivalente), com banco, fila e armazenamento também em contêiner; nada além do Docker é exigido. [ENV-02]
- O CI executa build, testes e checagens dentro de contêiner, com a mesma imagem de desenvolvimento. [ENV-04]
- Imagem sem segredo embutido; configuração por variável de ambiente ou cofre. [ENV-05]
- Em sistema legado sem Docker, ENV-01, ENV-02 e ENV-04 aceitam desvio pontual com o motivo no `plan.md`.
- [squados] Estado atual: o App roda como processo do host e ainda não há `Dockerfile` nem sidecar do Dapr em contêiner (sprint de reprodutibilidade pendente).

## Greenfield

`global.json`, CPM e workflow de CI do próprio SquadOS na primeira feature de fundação.

## Brownfield

Seguir o pipeline existente; mudanças nele são tarefa própria.

## Restrições e cuidados

A aprovação do plano não autoriza deploy, publicação, push nem alteração em produção (`aspire publish/deploy`, `azd`, `kubectl apply` ficam em `permissions.ask`).

## Testes obrigatórios

Pipeline verde no PR; em expansão-contração, teste de compatibilidade N-1, inclusive para eventos e schemas. [DEL-01]

## Exceções e limites

Hotfix segue o mesmo fluxo, com prioridade, nunca commit direto em `main`.

## Checklist de saída

- [ ] trabalho numa branch de feature;
- [ ] versão N-1 compatível com o schema e os contratos da versão N;
- [ ] nada destrutivo na mesma release que deixa de usar o recurso;
- [ ] entrega atrás de feature flag (ou exceção no `plan.md`);
- [ ] publicação com autorização do tech lead presa ao SHA e canário com rollback automático;
- [ ] pipeline verde.
