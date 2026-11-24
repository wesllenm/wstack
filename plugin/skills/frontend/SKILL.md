---
name: frontend
description: >
  Orienta o frontend web (ex.: SvelteKit): componentes, HTML semântico, acessibilidade
  WCAG 2.2 AA, formulários, foco, estado, responsividade, SignalR e
  performance, seguindo os padrões e bibliotecas existentes.
---

# Frontend

## Objetivo

Interfaces acessíveis, responsivas e consistentes com o resto do produto.

## Quando aplicar

Qualquer mudança no código de frontend do projeto.

## Acessibilidade

A meta fica em `.claude/project.md` (padrão: **WCAG 2.2 AA**). Toda tela nova ou alterada cumpre a meta. [FE-01]

Independentemente da meta, sempre:

- HTML semântico (botão é `button`, link é `a`, títulos em ordem); [FE-02]
- tudo operável por teclado, com foco visível e ordem lógica; foco gerenciado ao abrir e fechar diálogo; [FE-02]
- todo campo com label associado; erros ligados ao campo (`aria-describedby`, `aria-invalid`); [FE-02]
- imagens informativas com texto alternativo; decorativas ocultas de leitores de tela;
- contraste mínimo 4.5:1 em texto e 3:1 em componentes; alvo de toque mínimo 24×24 (2.5.8);
- atualizações em tempo real anunciadas com `aria-live` com moderação;
- os avisos de acessibilidade do compilador Svelte (`a11y_*`) são tratados como erro.

## Padrões

- Autenticação por BFF com cookie `HttpOnly`, sem token no navegador e com proteção contra CSRF no cookie de sessão (ex.: SvelteKit como SPA estática com `adapter-static`, servida pela API .NET). [SEC-10]
- Com Svelte 5, runes (`$state`, `$derived`, `$props`); TypeScript estrito.
- Seguir a biblioteca de componentes e o gerenciamento de estado que o projeto já usa; não introduzir novos sem aprovação. [FE-03]
- Estado no nível mais baixo possível; estado de servidor separado de estado de interface.
- Tempo real (ex.: `@microsoft/signalr`) com reconexão automática e indicação visual de desconexão.
- Formulários com validação no cliente para feedback e sempre revalidados no servidor. [FE-04]
- Layout responsivo nas larguras suportadas pelo projeto (ex.: desktop ≥ 1280px, tablet ≥ 768px).
- Evitar requisições em cascata e renderizações desnecessárias em listas grandes (listas longas paginadas por cursor).

## Greenfield

Escolha de biblioteca de componentes é decisão a registrar em `docs/decisions.md` na primeira tela.

## Brownfield

Seguir os componentes existentes mesmo quando outra abordagem parecer melhor; divergências vão para `docs/decisions.md`.

## Restrições e cuidados

Não renderizar HTML vindo de usuário, documento ou integração (ex.: issue) sem sanitizar (`{@html}` só com conteúdo sanitizado): conteúdo do negócio é dado não confiável. Download de original ou anexo sai com `Content-Disposition: attachment` e `X-Content-Type-Options: nosniff`. [SEC-09]

## Testes obrigatórios

Comportamento de componentes com lógica (validação, estados, interação) com Vitest + Testing Library; `svelte-check` sem erros; fluxos críticos (ex.: checkout, aprovação) cobertos por E2E conforme a skill `testing-strategy`, com checagem axe no E2E.

## Exceções e limites

Páginas de erro estáticas podem ter interação mínima, mas mantêm semântica e contraste.

## Checklist de saída

- [ ] WCAG 2.2 AA cumprida;
- [ ] teclado, foco e labels verificados;
- [ ] padrões e bibliotecas existentes respeitados;
- [ ] responsivo nas larguras suportadas;
- [ ] nenhum HTML não sanitizado.
