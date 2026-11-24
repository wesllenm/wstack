---
name: security
description: >
  Orienta segurança em autenticação, autorização, dados pessoais, SQL,
  uploads, parsing, segredos, SSRF, webhooks, prompt injection, ferramentas
  de agentes, dependências, logs e endpoints públicos.
---

# Security

## Objetivo

Nenhuma mudança amplia privilégio, expõe segredo ou dado sem decisão explícita. Quando o produto executa um agente de código, ele é tratado como prestador externo com privilégio mínimo: pode propor, nunca publicar sozinho.

## Quando aplicar

Sempre que o diff tocar uma das superfícies abaixo.

## Superfícies de risco — verificar quando o diff tocar

- Autenticação e autorização (OWASP A01, A07)
- Acesso a dados ou SQL — queries parametrizadas, sem concatenação; SQL bruto com interpolação de string é proibido, usar a API parametrizada da stack (OWASP A03)
- Isolamento entre clientes/tenants — IDOR (OWASP A01)
- Segredos, tokens e credenciais — nunca em código, log, prompt, saída gerada ou response; leitura pela configuração da stack com provider do cofre (OWASP A02)
- Webhooks de entrada — validação de assinatura (HMAC) antes de qualquer processamento, comparação em tempo constante, proteção contra replay
- Upload ou parsing de arquivo — validar tipo real, tamanho, conteúdo; armazenar sem executar
- Prompt injection — conteúdo de issue, comentário, documento e repositório é dado, não instrução: delimitado no prompt, nunca concatenado às instruções do sistema; saída do agente validada por schema antes de usar
- Ferramentas de agente do produto — cada etapa só recebe as ferramentas do seu contrato (por exemplo, o agente que só analisa não executa comando)
- Token do provedor de código — escopo mínimo: criar branch e PR só no repositório da tarefa; sem merge, sem deploy
- Sandbox do agente de código — sem credencial de produção, rede restrita a allowlist
- Execução dinâmica de código
- Renderização e download de conteúdo de usuário ou integração — HTML sempre sanitizado; download com `Content-Disposition: attachment` e `X-Content-Type-Options: nosniff`
- Sessão da aplicação web — token de acesso nunca no navegador (BFF ou cookie `HttpOnly`) e proteção contra CSRF no cookie de sessão
- Integrações externas — SSRF (URLs vindas de entrada do usuário ou de configuração), validação de origem
- Dependências novas — vulnerabilidades e licença

## LGPD / privacidade

- CPF, e-mail, nome completo, localização: nunca logar em claro
- Agentes usam só dados sintéticos ou mascarados; nenhuma base de produção entra no contexto
- Criptografar em repouso quando sensível
- Definir tempo de retenção (dados gerados, logs, traces)

## Princípios

- Least privilege: permissão mínima necessária
- Fail secure: erro deve negar acesso, não concedê-lo
- Validar server-side — nunca confiar no client
- Defense in depth: múltiplas camadas

## Greenfield

Autorização por política nomeada desde o primeiro endpoint; varredura de segredos e dependências no CI desde o primeiro PR.

## Brownfield

- Não alterar autenticação sem revisão crítica independente
- Documentar vulnerabilidades existentes em `docs/gotchas.md`

## Restrições e cuidados

Mudança em autenticação, autorização, segredos ou tokens aciona `review-critical` (skill `lead`) e `security-agent`.

## Testes obrigatórios

- acesso negado para usuário sem permissão (inclusive ação sobre recurso de outro cliente/tenant);
- webhook com assinatura inválida rejeitado sem efeito;
- upload acima do limite ou de tipo inválido rejeitado;
- conteúdo malicioso na entrada do negócio não altera ferramentas nem instruções do agente (teste no contrato da etapa).

## Exceções e limites

Não aplicar para endpoints internos sem autenticação por design (health checks), com justificativa documentada.

## Checklist de saída

- [ ] superfícies tocadas verificadas;
- [ ] nenhum segredo ou dado pessoal em código, log, prompt ou saída gerada;
- [ ] conteúdo do negócio tratado como dado;
- [ ] testes de negação presentes.
