---
name: api-design
description: >
  Orienta criação e evolução de APIs HTTP: formato de erro Problem Details,
  paginação por cursor, idempotência em operações com efeito externo,
  versionamento na URL, contratos e compatibilidade.
---

# API Design

## Objetivo

APIs previsíveis: todo endpoint responde erros, paginação, idempotência e versão do mesmo jeito.

## Quando aplicar

Endpoint novo (API do portal, webhooks de entrada), mudança de contrato, novo recurso, integração consumida por terceiros.

## Padrões

### Controllers

- Endpoints HTTP são **controllers** (`[ApiController]`, `<Caso>Controller` no slice), no lugar de Minimal API (ADR 0003). O controller só recebe a requisição (DTO de request), chama a service do caso de uso e devolve o DTO de response/`ActionResult`; sem regra de negócio, sem EF Core, sem repositório, sem `DbContext`, sem `IUnitOfWork`. [ARQ-01]
- Rota sob `/vN` e autorização por atributo (`[Authorize(Policy = ...)]`) ou convenção do grupo; nada público por omissão. Endpoints de infraestrutura (health, OpenAPI, canal do sidecar) podem continuar como Minimal API até migrarem.
- Validação de entrada de formato no DTO/binding; a regra de negócio e o resultado de domínio vêm da service.

### Erros

- Formato Problem Details (RFC 9457), com `Content-Type: application/problem+json` (`AddProblemDetails` + `ProblemDetails`/`ValidationProblemDetails` nos controllers). [API-01]
- A tradução de erro para Problem Details é feita por **filtro/handler central** (`IExceptionHandler`/filtro de exceção), a partir de exceções de aplicação (`ConcurrencyConflictException` → 409, `UniqueViolationException` → 409, commit incerto, falha de regra) e de resultados tipados da service; o controller não faz `try/catch` nem monta `code` à mão. O `code` estável continua obrigatório.
- Campos: `type` (URI estável por tipo de erro), `title`, `status`, `detail`, `instance`.
- Erros de validação estendem com `errors`, lista de `{ field, message }`. [API-10]
- Código de erro de negócio estável como extensão (`code`), para o cliente tratar sem ler texto.
- Nunca expor stack trace, SQL, nome de tabela ou mensagem interna de exceção. [API-02]
- Mapeamento: 400 entrada inválida, 401 sem autenticação, 403 sem permissão, 404 inexistente ou sem acesso quando revelar existência for risco, 409 conflito de estado ou concorrência, 422 regra de negócio violada, 429 limite, 5xx falha do servidor. [API-03]

### Paginação

- Cursor (keyset) em toda listagem. [API-04]
- Parâmetros `limit` e `cursor`; resposta com os itens e `nextCursor` (ausente na última página).
- Cursor opaco para o cliente, derivado de uma ordenação estável e única (por exemplo, data + id).
- `limit` com padrão e máximo definidos pelo servidor.
- Offset só quando houver requisito explícito de pular para a página N, registrado em `docs/decisions.md`.

### Idempotência

- Header `Idempotency-Key` obrigatório em operações com efeito externo: chamada a provedor de código (criar branch, abrir PR, comentar), comentário ou transição na ferramenta de demanda, disparo de pipeline, envio de notificação e chamada a integração externa que altera estado. [API-05]
- Webhooks de entrada são idempotentes pelo id de entrega do provedor (ex.: `X-GitHub-Delivery`) ou hash do payload assinado. [SEC-08]
- O servidor guarda chave + resultado por um período definido; repetição com a mesma chave devolve o resultado original, e repetição com a mesma chave e payload diferente é 422.
- Demais operações seguem a semântica HTTP normal (PUT e DELETE idempotentes por definição).

### Versionamento

- Versão na URL desde o início: `/v1/...`. [API-06]
- Nomes: URLs em minúsculas com `kebab-case`, recursos no plural e substantivos; JSON e parâmetros de consulta em `camelCase`; `code` de erro estável no formato `dominio.nome_do_erro` em minúsculas. [NOM-03]
- Dentro de uma versão, só mudanças compatíveis: adicionar campo opcional, endpoint ou valor de enum que o cliente já trata.
- Quebra de contrato exige nova versão (`/v2`), com período de convivência e deprecação anunciada (header `Deprecation` e `Sunset`).
- Criar nova versão é decisão de escopo e precisa de aprovação.

### Contratos

- Contrato OpenAPI (`Microsoft.AspNetCore.OpenApi`) atualizado na mesma mudança; o diff de OpenAPI é portão de CI. [API-07]
- Autenticação e autorização definidas por endpoint; nada público por omissão (`RequireAuthorization` no grupo; webhooks com validação de assinatura em vez de usuário). [API-08]
- Limites de tamanho de payload (inclusive upload de PDF/Markdown) e de taxa definidos para endpoints públicos. [API-09]

## Greenfield

Adotar todos os padrões acima desde o primeiro endpoint.

## Brownfield

Endpoints existentes mantêm seu formato (contrato, rotas e `code`); a migração de Minimal API para controller preserva o contrato público e segue o plano de migração aprovado (ADR 0003). Endpoints novos seguem esta skill, salvo se o projeto já tiver padrão consistente diferente, que então prevalece e é registrado em `docs/decisions.md`. Não migrar formato de erro ou paginação de endpoints existentes sem aprovação.

## Restrições e cuidados

O portal consome a API via BFF; tokens não chegam ao navegador. Não expor endpoint só para o portal fora do BFF. [SEC-10]

## Testes obrigatórios

- Formato de erro de cada status retornado pelo endpoint.
- Paginação: primeira página, página seguinte e última página sem `nextCursor`.
- Idempotência: repetição com a mesma chave não repete o efeito.
- Autorização: acesso negado para quem não deve acessar.

## Exceções e limites

Endpoints de health (`/health`, `/alive`) do Aspire ServiceDefaults ficam fora de versionamento.

## Checklist de saída

- [ ] controller fino (só recebe, chama a service, devolve), sem EF/repositório;
- [ ] erros em Problem Details via filtro central, sem vazamento interno;
- [ ] listagens por cursor com limite máximo;
- [ ] `Idempotency-Key` onde houver efeito externo;
- [ ] rota sob `/vN` e mudança compatível dentro da versão;
- [ ] contrato OpenAPI atualizado.
