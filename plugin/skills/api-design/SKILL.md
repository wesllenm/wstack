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

Endpoint novo (inclusive webhooks de entrada), mudança de contrato, novo recurso, integração consumida por terceiros.

## Padrões

### Camada HTTP

- O ponto de entrada HTTP só recebe a requisição (DTO de request), chama o serviço do caso de uso e devolve o DTO de response; sem regra de negócio, sem acesso a dados, sem transação.
- Rota sob `/vN` e autorização declarada por endpoint ou por convenção do grupo; nada público por omissão.
- Validação de entrada de formato no DTO/binding; a regra de negócio e o resultado de domínio vêm do serviço.

### Erros

- Formato Problem Details (RFC 9457), com `Content-Type: application/problem+json`.
- A tradução de erro para Problem Details é feita por **filtro/handler central**, a partir de exceções de aplicação (conflito de concorrência → 409, violação de unicidade → 409, commit incerto, falha de regra) e de resultados tipados do serviço; o endpoint não faz `try/catch` nem monta `code` à mão. O `code` estável continua obrigatório.
- Campos: `type` (URI estável por tipo de erro), `title`, `status`, `detail`, `instance`.
- Erros de validação estendem com `errors`, lista de `{ field, message }`.
- Código de erro de negócio estável como extensão (`code`), para o cliente tratar sem ler texto.
- Nunca expor stack trace, SQL, nome de tabela ou mensagem interna de exceção.
- Mapeamento: 400 entrada inválida, 401 sem autenticação, 403 sem permissão, 404 inexistente ou sem acesso quando revelar existência for risco, 409 conflito de estado ou concorrência, 422 regra de negócio violada, 429 limite, 5xx falha do servidor.

### Paginação

- Cursor (keyset) em toda listagem.
- Parâmetros `limit` e `cursor`; resposta com os itens e `nextCursor` (ausente na última página).
- Cursor opaco para o cliente, derivado de uma ordenação estável e única (por exemplo, data + id).
- `limit` com padrão e máximo definidos pelo servidor.
- Offset só quando houver requisito explícito de pular para a página N, registrado em `docs/decisions.md`.

### Idempotência

- Header `Idempotency-Key` obrigatório em operações com efeito externo: cobrança, pagamento, envio de mensagem (e-mail, SMS, WhatsApp, push), disparo de pipeline e chamada a integração externa que altera estado.
- Webhooks de entrada são idempotentes pelo id de entrega do provedor (ex.: `X-GitHub-Delivery`) ou hash do payload assinado.
- O servidor guarda chave + resultado por um período definido; repetição com a mesma chave devolve o resultado original, e repetição com a mesma chave e payload diferente é 422.
- Demais operações seguem a semântica HTTP normal (PUT e DELETE idempotentes por definição).

### Versionamento

- Versão na URL desde o início: `/v1/...`.
- Nomes: URLs em minúsculas com `kebab-case`, recursos no plural e substantivos; JSON e parâmetros de consulta em `camelCase`; `code` de erro estável no formato `dominio.nome_do_erro` em minúsculas.
- Dentro de uma versão, só mudanças compatíveis: adicionar campo opcional, endpoint ou valor de enum que o cliente já trata.
- Quebra de contrato exige nova versão (`/v2`), com período de convivência e deprecação anunciada (header `Deprecation` e `Sunset`).
- Criar nova versão é decisão de escopo e precisa de aprovação.

### Contratos

- Contrato documentado (OpenAPI ou o formato do projeto) atualizado na mesma mudança; o diff do contrato é portão de CI.
- Autenticação e autorização definidas por endpoint; nada público por omissão (webhooks com validação de assinatura em vez de usuário).
- Limites de tamanho de payload (inclusive upload) e de taxa definidos para endpoints públicos.

## Greenfield

Adotar todos os padrões acima desde o primeiro endpoint.

## Brownfield

Endpoints existentes mantêm seu formato (contrato, rotas e `code`); migração de estilo de implementação preserva o contrato público e segue o plano aprovado. Endpoints novos seguem esta skill, salvo se o projeto já tiver padrão consistente diferente, que então prevalece e é registrado em `docs/decisions.md`. Não migrar formato de erro ou paginação de endpoints existentes sem aprovação.

## Testes obrigatórios

- Formato de erro de cada status retornado pelo endpoint.
- Paginação: primeira página, página seguinte e última página sem `nextCursor`.
- Idempotência: repetição com a mesma chave não repete o efeito.
- Autorização: acesso negado para quem não deve acessar.

## Exceções e limites

Endpoints de health (`/health`, `/alive`) ficam fora de versionamento.

## Checklist de saída

- [ ] ponto de entrada HTTP fino (só recebe, chama o serviço, devolve), sem acesso a dados;
- [ ] erros em Problem Details via filtro central, sem vazamento interno;
- [ ] listagens por cursor com limite máximo;
- [ ] `Idempotency-Key` onde houver efeito externo;
- [ ] rota sob `/vN` e mudança compatível dentro da versão;
- [ ] contrato documentado atualizado.
