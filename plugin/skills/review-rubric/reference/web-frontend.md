# Review — Sempre verificar, frontend web (exemplos em Svelte 5 / SvelteKit)

Aplicar às linhas do diff no código de frontend (`*.svelte`, `*.svelte.ts`, `*.ts`), além de `node.md`. Os itens supõem SvelteKit como SPA estática servida pela API, Svelte 5 com runes, Vitest + Testing Library + axe (jsdom) e E2E em navegador real; em outra stack, usar o equivalente. Metas de acessibilidade e larguras suportadas em `.claude/project.md` (ex.: WCAG 2.2 AA, desktop ≥ 1280 px e tablet ≥ 768 px). Em Svelte, não cobrar hooks, `key` de JSX nem `<Profiler>`.

Segurança do cliente (texto vindo do servidor, de integração ou de pessoa é dado hostil):
- `{@html}`, `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `eval`, `new Function`, `localStorage`/`sessionStorage`, `document.cookie`, `document.write`, URL absoluta ou `//host` literal no código e `target="_blank"` sem `rel`: quando o projeto os recusa por lint ou teste de regras, contornar (comentário, concatenação, colchetes) ou enfraquecer a regra é candidato bloqueante; sem a regra, cada uso novo é candidato;
- texto vindo do servidor entra como texto puro (sem autolink, Markdown nem HTML), nunca por interpolação em atributo de URL (`href`, `src`, `action`) nem em `style`; em `<a>`, só caminho local ou esquema permitido;
- toda escrita autenticada (`POST`, `PUT`, `PATCH`, `DELETE`) leva o cabeçalho de CSRF do projeto pelo cliente HTTP único (ex.: `lib/api`); `fetch` fora dele é candidato;
- sessão, identidade e permissões lidas só do endpoint de sessão do BFF (ex.: `/bff/user`), nunca de storage nem de cookie legível; a identidade exibida é reconfirmada antes de uma decisão, e uma atualização automática confirma a sessão no mesmo ciclo;
- ação não idempotente (ex.: aprovar, pagar): nada de reenvio automático do `POST`, e o texto de erro incerto (rede, prazo, 5xx, 2xx ilegível) nunca afirma o desfecho;
- CSP: com `<meta>` gerado no build por hash, sem `unsafe-inline` nem `unsafe-eval`, atributo `style="…"` novo (inclusive de componente) viola `style-src` e é candidato;
- segredo ou chave em variável que vai ao cliente (`PUBLIC_*`, `import.meta.env`).

Svelte 5 e estado:
- `$effect` que escreve no estado que lê (laço), sem limpeza de assinatura, timer, listener ou `AbortController`; `$effect` onde `$derived` resolve;
- polling: só com aba visível, com intervalo mínimo entre gatilhos, recuo para 429/503 (`Retry-After`) e abort da requisição anterior; atualização que substitui lista exibida sem preservar a escolha ou o foco da pessoa;
- `{#each}` sem chave estável (id do item, nunca o índice) quando a lista muda; recriação de tela por `{#key}` na troca de identidade;
- estado de servidor misturado com estado de interface; tela que decide sobre um item lido antes sem comparar versão ou hash com o atual (a escolha da pessoa é zerada quando o item muda);
- link para rota nova sem tipagem do `resolve()` (o `@ts-expect-error` deve sumir quando a rota nascer).

Acessibilidade e UX (WCAG 2.2 AA):
- HTML semântico (botão é `button`, link é `a`, títulos em ordem, `<caption>` e `scope` em tabela); todo campo com label e erro ligado por `aria-describedby`/`aria-invalid`; foco movido ao `h1` na troca de rota e devolvido ao fechar diálogo (diálogo de confirmação com `<dialog>` nativo: `Esc`, `close` espontâneo, foco inicial em Cancelar); `aria-live` com moderação;
- aviso `a11y_*` do compilador é erro; contraste 4.5:1 (texto) e 3:1 (componente); alvo ≥ 24×24 px; sem rolagem horizontal na menor largura suportada; componente em coluna estreita decide colunas por `@container`, não por `@media`;
- tela nova sem teste axe nos estados principais e sem E2E quando for fluxo crítico (`testing-strategy`).

Performance (skill `performance`, camada 2): lista ou tela nova sem teste de contagem de requisições por página (E2E) ou de chamadas no simulador de `fetch` (Vitest); mesma requisição disparada por dois componentes; requisições em cascata que poderiam ser paralelas; reconsulta de toda a cadeia de cursores a cada ciclo de polling (a atualização reconsulta só a primeira página).

Camada determinística (o `lead` é dono): `svelte-check --fail-on-warnings`, `eslint-plugin-svelte` (`no-at-html-tags` como erro), `prettier-plugin-svelte`, compilador com `a11y_*` como erro, Vitest (unit e build/CSP) e E2E com axe (`color-contrast` e `target-size` ligados à mão). Introduzir biblioteca de componentes ou estado global exige decisão (`docs/decisions.md`, skill `frontend`).

Não é achado: classe CSS e ordem de propriedades, escolha de token de cor sem violar contraste, componente que poderia ser dividido sem segundo uso, falta de animação, nome de evento interno, e qualquer aviso `a11y_*` (já é erro no build).
