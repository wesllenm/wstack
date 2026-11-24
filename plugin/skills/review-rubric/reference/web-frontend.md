# Review — Sempre verificar, frontend web (portal Svelte 5 / SvelteKit)

Aplicar às linhas do diff em `src/portal/**` (`*.svelte`, `*.svelte.ts`, `*.ts`), além de `node.md`. Stack: SvelteKit 3 como SPA estática servida pela API, Svelte 5 com runes, Vitest + Testing Library + axe (jsdom) e E2E em Chromium real em `tests/SquadOS.E2ETests`. Metas: WCAG 2.2 AA, desktop ≥ 1280 px e tablet ≥ 768 px (`.claude/project.md`). Sem React: não cobrar hooks, `key` de JSX nem `<Profiler>`.

Segurança do cliente (o texto de agente, de issue e de pessoa é dado hostil):
- `{@html}`, `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `eval`, `new Function`, `localStorage`/`sessionStorage`, `document.cookie`, `document.write`, URL absoluta ou `//host` literal no código e `target="_blank"` sem `rel`: já são recusados por `eslint` e por `tests/frontend-rules.ts`; se o diff os contorna (comentário, concatenação, colchetes) ou enfraquece a regra, é candidato bloqueante;
- texto vindo do servidor entra por `PlainText` (texto puro, sem autolink, Markdown nem HTML), nunca por interpolação em atributo de URL (`href`, `src`, `action`) nem em `style`; em `<a>`, só caminho local ou esquema permitido;
- toda escrita autenticada (`POST`, `PUT`, `PATCH`, `DELETE`) leva `X-SquadOS-CSRF: 1` pelo cliente único de `lib/api`; `fetch` fora dele é candidato;
- sessão, identidade e permissões lidas só de `/bff/user` (nunca de storage nem de cookie legível); a identidade exibida precisa ser reconfirmada antes de decidir (etiqueta `identityTag`), e uma atualização automática confirma a sessão no mesmo ciclo;
- decisão não é idempotente: nada de reenvio automático de `POST` de decisão, e o texto de erro incerto (rede, prazo, 5xx, 2xx ilegível) nunca afirma o desfecho;
- CSP: o `<meta>` gerado no build usa hash, sem `unsafe-inline` nem `unsafe-eval`; atributo `style="…"` novo (inclusive de componente) viola `style-src` e é candidato (o do anunciador do SvelteKit está declarado por hash e testado);
- segredo ou chave em variável que vai ao cliente (`PUBLIC_*`, `import.meta.env`).

Svelte 5 e estado:
- `$effect` que escreve no estado que lê (laço), sem limpeza de assinatura, timer, listener ou `AbortController`; `$effect` onde `$derived` resolve;
- polling: só com aba visível, com intervalo mínimo entre gatilhos, recuo para 429/503 (`Retry-After`) e abort da requisição anterior; atualização que substitui lista exibida sem preservar a escolha ou o foco da pessoa;
- `{#each}` sem chave estável (id da demanda, nunca o índice) quando a lista muda; recriação de tela por `{#key}` na troca de identidade;
- estado de servidor misturado com estado de interface; tela que decide com versão ou hash de artefato lido antes sem comparar com o atual (a escolha "Aprovar" precisa ser zerada quando versão ou hash mudam);
- link para rota nova sem tipagem do `resolve()` (o `@ts-expect-error` deve sumir quando a rota nascer).

Acessibilidade e UX (WCAG 2.2 AA):
- HTML semântico (botão é `button`, link é `a`, títulos em ordem, `<caption>` e `scope` em tabela); todo campo com label e erro ligado por `aria-describedby`/`aria-invalid`; foco movido ao `h1` na troca de rota e devolvido ao fechar diálogo (`ConfirmDialog` nativo: `Esc`, `close` espontâneo, foco inicial em Cancelar); `aria-live` com moderação;
- aviso `a11y_*` do compilador é erro; contraste 4.5:1 (texto) e 3:1 (componente); alvo ≥ 24×24 px; sem rolagem horizontal a 768 px; componente em coluna estreita decide colunas por `@container`, não por `@media`;
- tela nova sem teste axe nos estados principais e sem E2E quando for fluxo crítico (`testing-strategy`).

Performance (skill `performance`, camada 2): lista ou tela nova sem teste de contagem de requisições por página (E2E) ou de chamadas no simulador de `fetch` (Vitest); mesma requisição disparada por dois componentes; requisições em cascata que poderiam ser paralelas; reconsulta de toda a cadeia de cursores a cada ciclo de polling (a atualização reconsulta só a primeira página).

Camada determinística (o `lead` é dono): `svelte-check --fail-on-warnings`, `eslint-plugin-svelte` (`no-at-html-tags` como erro), `prettier-plugin-svelte`, compilador com `a11y_*` como erro, Vitest (unit e build/CSP) e E2E com axe (`color-contrast` e `target-size` ligados à mão). Sem biblioteca de componentes e sem estado global: introduzir exige decisão (`docs/decisions.md`, skill `frontend`).

Não é achado: classe CSS e ordem de propriedades, escolha de token de cor sem violar contraste, componente que poderia ser dividido sem segundo uso, falta de animação, nome de evento interno, e qualquer aviso `a11y_*` (já é erro no build).
