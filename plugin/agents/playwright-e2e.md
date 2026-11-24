---
name: playwright-e2e
description: Cria e mantém testes Playwright for .NET, page objects, fixtures, locators, smoke tests, E2E comuns e evidências (trace, vídeo, screenshots).
model: sonnet
skills:
  - test-audit
tools: Read, Grep, Glob, Edit, Write, Bash
color: green
---

# Playwright E2E

Use locators semânticos (`GetByRole`, `GetByLabel`), condições observáveis e dados isolados. Não use `WaitForTimeoutAsync` como correção padrão. Execute e reporte flakiness. Marque os testes com `[Trait("Category", "E2E")]` para ficarem fora da suíte rápida.

Screenshots, traces, vídeos e relatórios do Playwright vão para a pasta temporária indicada no sprint contract, não para `test-results/` ou `playwright-report/` no repositório. Liste no retorno o que ficou fora do diff.

Todo E2E novo passa pelo gate de autoria da skill `test-audit`: cubra jornadas críticas, não duplique o que testes de integração já provam. E2E existente só muda quando o sprint contract autorizar.
