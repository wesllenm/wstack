# Performance — Frontend web (portal Svelte 5 / SvelteKit)

Stack real do portal (`src/portal`): SvelteKit 3.1 como SPA estática (`adapter-static`, `fallback: index.html`), Svelte 5 com runes, Vite 8, Vitest 5 + Testing Library + jsdom, axe-core, e testes de navegador reais em .NET (`tests/SquadOS.E2ETests`, Playwright for .NET e Chromium). Sem React, sem biblioteca de componentes, sem pacote npm em runtime: o bundle é só o framework e o código do portal. Referência de JS/TS em geral: `node.md`.

## Camada 1 — regras estáticas

`svelte-check --fail-on-warnings`, `eslint-plugin-svelte` e o compilador (avisos `a11y_*` viram erro no `vite.config.ts`) já rodam em `npm --prefix src/portal run check` e `run lint`. Nada específico de performance está ligado; regra nova entra no `eslint.config.js` (arquivo protegido).

## Camada 2 — contagem nos testes

- **Requisições por página, em navegador real** (E2E .NET): registrar `page.Request += (_, r) => requested.Add(r.Url)` antes de navegar (padrão já usado em `StoryScreenTests.cs` e `SignOutTests.cs`), filtrar a API (`/v1/` e `/bff/`) e afirmar que (a) a contagem **não cresce** com a quantidade de itens da fila ou da Story (comparar com poucos e com muitos itens semeados no backend em memória), (b) não há URL repetida na carga e (c) a atualização automática reconsulta só a primeira página e a sessão (`/bff/user`) uma vez por ciclo. Não fixar o número exato: afirmar igualdade entre dois volumes.
- **Requisições nos testes de componente** (Vitest): o `fetch` é simulado (`tests/fetch.ts`), então a contagem de chamadas por cenário se afirma ali; o recuo de 429/503, o intervalo mínimo entre gatilhos e o `AbortController` já têm teste (`PendingQueue.test.ts`); uma tela nova com lista precisa do mesmo tipo de afirmação.
- **Renders**: Svelte 5 não tem `<Profiler>`; o equivalente é contar execução de `$effect` e de `$derived` com um contador no teste de componente, só onde uma lista grande re-renderiza a cada atualização. Não criar seam de produção para isso (`test-audit`, pergunta 4).

## Camada 3 — tamanho do bundle

Total comprimido por tipo (js, css), determinístico, pode virar achado (TAMANHO: +5% e +2 KB) e aceita orçamento. Medido pelo `.claude/scripts/bundle-size.sh` sobre `src/portal/build` (adaptador estático: o build é `build/`, não `dist/`); o script emite o TSV comum e é do `lead` (não editar daqui). Linhas do `risk.conf` (propostas, ainda não adotadas porque **nenhum caminho `hot` está declarado**):

```ini
hot    = src/portal/src/* -> Bundle
bench  = Bundle -> npm --prefix src/portal ci --ignore-scripts --no-audit --no-fund && SQUADOS_BUILD_VERSION=bench npm --prefix src/portal run build && bash "$BENCH_SCRIPTS/bundle-size.sh" src/portal/build > "$BENCH_TSV"
budget = total:js -> <definir depois da primeira medição>
```

Medido na S7.2a: JS ~38 KB e CSS ~2 KB gzip. Orçamento só com número de referência (a primeira medição em CI vira a base); a build usa `SQUADOS_BUILD_VERSION` para o hash do CSP ser reprodutível. Métricas de laboratório (Lighthouse) são opcionais e informativas.

## Camada 3b — suíte instrumentada

Não aplicável por ora.

## Camada 4 — profiling

Painel Performance do DevTools e o trace do Playwright (`context.Tracing`, gravado na pasta temporária da sessão, nunca em `test-results/`). Para investigar polling ou re-render, medir com o relógio simulado (`vi.useFakeTimers`) antes de usar navegador real.
