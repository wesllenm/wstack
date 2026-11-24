# Performance — Frontend web (exemplos em Svelte 5 / SvelteKit)

Os exemplos supõem SvelteKit como SPA estática (`adapter-static`), Svelte 5 com runes, Vite, Vitest + Testing Library + jsdom, axe-core e testes de navegador reais com Playwright (for .NET ou Node). Em outra stack, usar o equivalente. Referência de JS/TS em geral: `node.md`.

## Camada 1 — regras estáticas

`svelte-check --fail-on-warnings`, `eslint-plugin-svelte` e o compilador (avisos `a11y_*` viram erro no `vite.config.ts`) rodam no check e no lint do frontend. Regra nova de performance entra no `eslint.config.js` (arquivo protegido).

## Camada 2 — contagem nos testes

- **Requisições por página, em navegador real** (E2E): registrar as requisições antes de navegar (Playwright for .NET: `page.Request += (_, r) => requested.Add(r.Url)`; Node: `page.on('request', ...)`), filtrar a API (ex.: `/v1/` e `/bff/`) e afirmar que (a) a contagem **não cresce** com a quantidade de itens da lista (comparar com poucos e com muitos itens semeados no backend de teste), (b) não há URL repetida na carga e (c) a atualização automática reconsulta só a primeira página e a sessão uma vez por ciclo. Não fixar o número exato: afirmar igualdade entre dois volumes.
- **Requisições nos testes de componente** (Vitest): o `fetch` é simulado, então a contagem de chamadas por cenário se afirma ali, inclusive recuo de 429/503, intervalo mínimo entre gatilhos e `AbortController`; uma tela nova com lista precisa do mesmo tipo de afirmação.
- **Renders**: Svelte 5 não tem `<Profiler>`; o equivalente é contar execução de `$effect` e de `$derived` com um contador no teste de componente, só onde uma lista grande re-renderiza a cada atualização. Não criar seam de produção para isso (`test-audit`, pergunta 4).

## Camada 3 — tamanho do bundle

Total comprimido por tipo (js, css), determinístico, pode virar achado (TAMANHO: +5% e +2 KB) e aceita orçamento. Medido pelo `bundle-size.sh` do plugin sobre a pasta de build (com `adapter-static`, o build é `build/`, não `dist/`); o script emite o TSV comum e é do `lead` (não editar daqui). Linhas do `risk.conf` (exemplo, com o frontend em `<frontend>`):

```ini
hot    = <frontend>/src/* -> Bundle
bench  = Bundle -> npm --prefix <frontend> ci --ignore-scripts --no-audit --no-fund && npm --prefix <frontend> run build && bash "$BENCH_SCRIPTS/bundle-size.sh" <frontend>/build > "$BENCH_TSV"
budget = total:js -> <definir depois da primeira medição>
```

Orçamento só com número de referência (a primeira medição em CI vira a base). Se a build embute versão ou hash (ex.: hash do CSP), fixar a variável de versão no comando `bench` para o resultado ser reprodutível. Métricas de laboratório (Lighthouse) são opcionais e informativas.

## Camada 3b — suíte instrumentada

Não aplicável (sem coletor para frontend).

## Camada 4 — profiling

Painel Performance do DevTools e o trace do Playwright (`context.Tracing`, gravado na pasta temporária da sessão, nunca em `test-results/`). Para investigar polling ou re-render, medir com o relógio simulado (`vi.useFakeTimers`) antes de usar navegador real.
