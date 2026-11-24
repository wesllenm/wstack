# Performance — Node (JavaScript e TypeScript no SquadOS)

Onde há JS/TS no repositório: o portal (`src/portal`, SvelteKit 3 compilado para SPA estática; o que é específico de tela está em `web-frontend.md`) e scripts de ferramenta em `.claude/scripts/*.mjs`. **Não há código Node em caminho de requisição**: a API é .NET e o Node só roda na build, nos testes e nas ferramentas. Por isso as camadas de servidor Node (contagem de comandos de banco, atraso do event loop, harness de benchmark) **não se aplicam**; não gerar `js-bench.mjs`, `cpuprofile-top.mjs` nem `perf-snapshot.mjs` enquanto nenhum caminho `hot` em JS existir. Alvo Node 24 (`.nvmrc`); testes com Vitest 5.

## Camada 1 — regras estáticas

`typescript-eslint` em modo com tipos (`recommendedTypeChecked`) já está no `src/portal/eslint.config.js` e pega promessa sem `await` (`no-floating-promises`, `no-misused-promises`). `npm --prefix src/portal run check` (`svelte-check --fail-on-warnings`) e `npm --prefix src/portal run lint` (`eslint --max-warnings 0` e `prettier --check`) fazem parte do modo `portal` do CI. `no-await-in-loop` como aviso só se um script passar a ter laço de I/O. `eslint.config.js`, `tsconfig.json` e `vite.config.ts` ficam sob a mesma proteção de configuração de análise (supressão é enfraquecer teste).

## Camada 2 — contagem nos testes

- **Requisições HTTP**: nos testes de componente do portal o `fetch` é simulado (`tests/fetch.ts`, `tests/*-server.ts`); contar as chamadas no simulador e afirmar que não crescem com a quantidade de itens e que não há URL repetida (o polling reconsulta só a primeira página: o teste de fila já protege isso). Contagem por **página** em navegador real fica nos E2E em `tests/SquadOS.E2ETests` (ver `web-frontend.md`).
- **Alocação**: não medir em JS (o GC do V8 a torna instável); em JS valem contagem, tempo e escala.

## Camada 3 — benchmark

Nenhum caminho `hot` em JS declarado, logo nenhum harness. Se um dia houver (por exemplo um parser pesado de artefato no cliente), criar o harness em tarefa própria, com aprovação, gravando o TSV comum de nove colunas do `compare-bench.sh` (alocação `-`, só tempo e escala). Para **tamanho do bundle**, ver `web-frontend.md` (`bundle-size.sh`).

## Camada 3b — suíte instrumentada

Não aplicável por ora (sem coletor para Node; a suíte do portal roda em ~1 min e não executa código de servidor).

## Camada 4 — profiling sob demanda

`node --cpu-prof` para perfil de CPU de uma ferramenta ou do Vitest; `node --heap-prof` ou snapshot de heap no DevTools para memória; `node --inspect` para investigação interativa. Perfis ficam na pasta temporária da sessão. Para o portal em execução, o painel Performance do DevTools e o trace do Playwright (`web-frontend.md`).
