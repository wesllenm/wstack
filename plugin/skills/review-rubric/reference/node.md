# Review — Sempre verificar, JavaScript e TypeScript (portal e scripts Node)

Aplicar às linhas do diff em `*.ts`, `*.js` e `*.mjs` (`src/portal/**` e `.claude/scripts/*.mjs`). Código de tela Svelte tem a referência própria `web-frontend.md`. No SquadOS o Node roda na build, nos testes e em ferramentas; **não há servidor Node** (a API é .NET), então itens de servidor Node só valem para script.

- promessa sem `await` nem tratamento; `async` dentro de `forEach`; `await` em laço onde a ordem não importa; `.catch(() => {})` que engole;
- `fetch` sem `AbortController` quando a tela pode sair antes da resposta, sem checar `response.ok` ou sem tratar corpo que não é JSON (o portal trata resposta ilegível como resultado incerto, não como sucesso);
- regex com backtracking catastrófico aplicada a entrada do usuário (ReDoS), e regex de validação de identificador sem âncora completa (`$` casa antes de `\n` final em .NET e em jq; no JS use `^…$` sem a flag `m` e confirme);
- estado em nível de módulo compartilhado entre telas ou testes; listener, timer ou assinatura registrado sem remoção;
- `Number` para dinheiro; data sem fuso explícito;
- merge de objeto vindo do servidor ou do usuário sem checar chaves (prototype pollution); `JSON.parse` sem tratar exceção;
- em script `.mjs`: `fs.*Sync` em laço sobre muitos arquivos aceitável, mas `process.env` lido sem validação, comando montado por concatenação de string (usar argv), caminho vindo de entrada sem normalização e `child_process` com `shell: true`;
- `any` explícito ou `as` que cala o compilador (a regra `no-explicit-any` já é erro no portal; `@ts-expect-error` precisa de motivo e só vale para rota ainda inexistente);
- dependência nova em `package.json`: versão exata, `--ignore-scripts`, licença conferida; runtime do portal tem **zero** dependências, então qualquer uma em `dependencies` é achado.

Camada determinística (o `lead` e o `risk.conf` são donos): `npm --prefix src/portal run check` (`svelte-check`, `tsc`), `run lint` (ESLint com `recommendedTypeChecked`, `prettier --check`), `npm test` (Vitest, inclui o teste de arquitetura do front em `tests/architecture.test.ts` e o de build/CSP), `npm audit --audit-level=high` no modo `portal` do CI. Arquitetura por varredura própria (`tests/frontend-rules.ts`), não por dependency-cruiser. StrykerJS **não** adotado. Sinais de qualidade (`quality-signals.sh`), se ligados: cobertura Istanbul (`vitest run --coverage` com reporter `json`) + ESLint `complexity` com máximo 0 + `jscpd`. Em `ask`: `eslint.config.js`, `tsconfig.json`, `vite.config.ts`, `.prettierrc*`.

Não é achado (o ESLint, o Prettier e o `svelte-check` já cobrem): ponto e vírgula, aspas, ordem de import, `let` que poderia ser `const`, nome de variável curto em escopo pequeno, `for` vs `map` sem impacto de leitura, falta de JSDoc.
