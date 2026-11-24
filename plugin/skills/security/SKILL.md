---
name: security
description: >
  Orienta segurança em autenticação, autorização, dados pessoais, SQL,
  uploads, parsing, segredos, SSRF, webhooks, prompt injection, ferramentas
  de agentes, dependências, logs e endpoints públicos.
---

# Security

## Objetivo

O SquadOS trata o agente de código como prestador externo com privilégio mínimo: pode propor, nunca publicar sozinho. Nenhuma mudança amplia privilégio, expõe segredo ou dado sem decisão explícita.

## Quando aplicar

Sempre que o diff tocar uma das superfícies abaixo.

## Superfícies de risco — verificar quando o diff tocar

- Autenticação e autorização (OWASP A01, A07): BFF/OIDC do portal, quem pode aprovar em cada portão (configuração por cliente) [SEC-01]
- Acesso a dados ou SQL — queries parametrizadas, sem concatenação; `FromSqlRaw` com interpolação é proibido, usar `FromSql`/`SqlQuery` com `FormattableString` (OWASP A03) [DAT-04]
- Isolamento entre clientes/sistemas — IDOR em demanda, artefato, aprovação (OWASP A01) [SEC-02]
- Segredos, tokens e credenciais — nunca em código, log, prompt, artefato ou response; leitura via `IConfiguration` com provider do cofre (OWASP A02) [SEC-03]
- Webhooks de entrada — validação de assinatura (HMAC) antes de qualquer processamento, comparação em tempo constante, proteção contra replay [SEC-08]
- Upload ou parsing de arquivo (PDF, Markdown) — validar tipo real, tamanho, conteúdo; armazenar no S3 sem executar [SEC-04]
- Prompt injection — conteúdo de issue, comentário, documento e repositório é dado, não instrução: delimitado no prompt, nunca concatenado às instruções do sistema; saída do agente validada por JSON Schema antes de usar
- Ferramentas de agente do produto — cada estágio só recebe as ferramentas do seu contrato (o Analista não executa comando; o agente de código não acessa a ferramenta de demanda)
- Token do provedor de código — escopo mínimo: criar branch e PR só no repositório da tarefa; sem merge, sem deploy
- Sandbox do agente de código — sem credencial de produção, rede restrita a allowlist
- Execução dinâmica de código [SEC-06]
- Renderização e download de conteúdo de usuário ou integração — HTML sempre sanitizado; download com `Content-Disposition: attachment` e `X-Content-Type-Options: nosniff` [SEC-09]
- Sessão do portal — token de acesso nunca no navegador (BFF ou cookie `HttpOnly`) e proteção contra CSRF no cookie de sessão [SEC-10]
- Integrações externas — SSRF (URLs vindas de demanda/configuração), validação de origem [SEC-05]
- Dependências novas — vulnerabilidades e licença [DEP-02] [DEP-03]

## LGPD / privacidade

- CPF, e-mail, nome completo, localização: nunca logar em claro [PRV-01]
- Agentes usam só dados sintéticos ou mascarados; nenhuma base de produção entra no contexto
- Criptografar em repouso quando sensível [PRV-02]
- Definir tempo de retenção (artefatos, logs, Langfuse) [PRV-03]

## Princípios

- Least privilege: permissão mínima necessária
- Fail secure: erro deve negar acesso, não concedê-lo [SEC-01]
- Validar server-side — nunca confiar no client
- Defense in depth: múltiplas camadas

## Greenfield

Autorização por política nomeada desde o primeiro endpoint; varredura de segredos e dependências no CI desde o primeiro PR.

## Brownfield

- Não alterar autenticação sem revisão crítica independente
- Documentar vulnerabilidades existentes em `docs/gotchas.md`

## Restrições e cuidados

Mudança em autenticação, autorização, segredos ou tokens aciona `review-critical` (skill `lead`) e `security-agent`. [SEC-07]

## Testes obrigatórios

- acesso negado para usuário sem permissão (inclusive aprovar portão de outro sistema); [SEC-01] [SEC-02]
- webhook com assinatura inválida rejeitado sem efeito; [SEC-08]
- upload acima do limite ou de tipo inválido rejeitado; [SEC-04]
- conteúdo malicioso em demanda não altera ferramentas nem instruções do agente (teste no contrato do estágio).

## Exceções e limites

Não aplicar para endpoints internos sem autenticação por design (health checks), com justificativa documentada.

## Checklist de saída

- [ ] superfícies tocadas verificadas;
- [ ] nenhum segredo ou dado pessoal em código, log, prompt ou artefato;
- [ ] conteúdo do negócio tratado como dado;
- [ ] testes de negação presentes.
