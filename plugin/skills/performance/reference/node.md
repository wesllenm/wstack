# Performance — Node (JavaScript e TypeScript)

Primeiro, ver onde há JS/TS no repositório: servidor Node em caminho de requisição, frontend compilado (o que é específico de tela está em `web-frontend.md`) ou só build, testes e ferramentas. Quando o Node só roda na build, nos testes e nas ferramentas, as camadas de servidor Node (contagem de comandos de banco, atraso do event loop, harness de benchmark) **não se aplicam**; não gerar `js-bench.mjs`, `cpuprofile-top.mjs` nem `perf-snapshot.mjs` enquanto nenhum caminho `hot` em JS existir. Versão alvo do Node no `.nvmrc`.

## Camada 1 — regras estáticas

`typescript-eslint` em modo com tipos (`recommendedTypeChecked`) no `eslint.config.js` pega promessa sem `await` (`no-floating-promises`, `no-misused-promises`). O check de tipos (`tsc --noEmit` ou `svelte-check --fail-on-warnings`) e o lint (`eslint --max-warnings 0` e `prettier --check`) fazem parte do CI. `no-await-in-loop` como aviso só se um script passar a ter laço de I/O. `eslint.config.js`, `tsconfig.json` e `vite.config.ts` ficam sob a mesma proteção de configuração de análise (supressão é enfraquecer teste).

## Camada 2 — contagem nos testes

- **Requisições HTTP**: nos testes de componente o `fetch` é simulado; contar as chamadas no simulador e afirmar que não crescem com a quantidade de itens e que não há URL repetida (o polling reconsulta só a primeira página). Contagem por **página** em navegador real fica nos E2E (ver `web-frontend.md`).
- **Alocação**: não medir em JS (o GC do V8 a torna instável); em JS valem contagem, tempo e escala.

## Camada 3 — benchmark

Sem caminho `hot` em JS declarado, nenhum harness. Se houver (por exemplo um parser pesado no cliente), criar o harness em tarefa própria, com aprovação, gravando o TSV comum de nove colunas do `compare-bench.sh` (alocação `-`, só tempo e escala). Para **tamanho do bundle**, ver `web-frontend.md` (`bundle-size.sh`).

## Camada 3b — suíte instrumentada

Não aplicável (sem coletor para Node).

## Camada 4 — profiling sob demanda

`node --cpu-prof` para perfil de CPU de uma ferramenta ou do Vitest; `node --heap-prof` ou snapshot de heap no DevTools para memória; `node --inspect` para investigação interativa. Perfis ficam na pasta temporária da sessão. Para o frontend em execução, o painel Performance do DevTools e o trace do Playwright (`web-frontend.md`).
