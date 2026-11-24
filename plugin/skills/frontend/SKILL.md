---
name: frontend
description: >
  Orienta componentes web, HTML semântico, acessibilidade conforme a meta
  do projeto, formulários, foco, estado, responsividade e performance,
  seguindo os padrões e bibliotecas existentes.
---

# Frontend

## Objetivo

Interfaces acessíveis, responsivas e consistentes com o resto do produto.

## Quando aplicar

Qualquer mudança no código de interface web do projeto.

## Acessibilidade

A meta de acessibilidade é definida por projeto e registrada em `.claude/project.md` pelo bootstrap (por exemplo, WCAG 2.2 AA ou requisitos básicos). Toda tela nova ou alterada cumpre a meta registrada. Se não houver meta registrada, perguntar ao desenvolvedor antes de implementar a primeira tela.

Independentemente da meta, sempre:

- HTML semântico (botão é `button`, link é `a`, títulos em ordem);
- tudo operável por teclado, com foco visível e ordem lógica; foco gerenciado ao abrir e fechar diálogo;
- todo campo com label associado; erros ligados ao campo (`aria-describedby`, `aria-invalid`);
- imagens informativas com texto alternativo; decorativas ocultas de leitores de tela;
- contraste mínimo 4.5:1 em texto e 3:1 em componentes; alvo de toque mínimo 24×24 (WCAG 2.5.8);
- atualizações em tempo real anunciadas com `aria-live` com moderação;
- os avisos de acessibilidade do compilador ou do linter são tratados como erro.

## Padrões

- Seguir o framework, a biblioteca de componentes e o gerenciamento de estado que o projeto já usa; não introduzir novos sem aprovação.
- Estado no nível mais baixo possível; estado de servidor separado de estado de interface quando o projeto tiver ferramenta para isso.
- Tempo real com reconexão automática e indicação visual de desconexão.
- Formulários com validação no cliente para feedback e sempre revalidados no servidor.
- Layout responsivo nas larguras que o produto suporta, registradas em `.claude/project.md`.
- Evitar requisições em cascata e renderizações desnecessárias em listas grandes.

## Greenfield

Escolha de biblioteca de componentes é decisão a registrar em `docs/decisions.md` na primeira tela.

## Brownfield

Seguir os componentes existentes mesmo quando outra abordagem parecer melhor; divergências vão para `docs/decisions.md`.

## Restrições e cuidados

Não renderizar HTML vindo de conteúdo do negócio ou de fonte externa sem sanitizar (injeção de HTML bruto só com conteúdo sanitizado): é dado não confiável. Download de original ou anexo sai com `Content-Disposition: attachment` e `X-Content-Type-Options: nosniff`.

## Testes obrigatórios

Comportamento de componentes com lógica (validação, estados, interação); checagem de tipos e lint do frontend sem erros; fluxos críticos cobertos por E2E conforme a skill `testing-strategy`, com checagem axe no E2E.

## Exceções e limites

Páginas de erro estáticas podem ter interação mínima, mas mantêm semântica e contraste.

## Checklist de saída

- [ ] meta de acessibilidade do projeto cumprida;
- [ ] teclado, foco e labels verificados;
- [ ] padrões e bibliotecas existentes respeitados;
- [ ] responsivo nas larguras suportadas;
- [ ] nenhum HTML não sanitizado.
