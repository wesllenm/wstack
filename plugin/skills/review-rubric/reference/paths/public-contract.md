# Review por caminho — controllers e contrato público

Aplicar quando o grupo tocar `**/Controllers/**` ou `*Controller.cs`. Complementa o "Sempre verificar" da `SKILL.md`.

- controller fino: só recebe, chama a service e devolve o resultado; sem `DbContext`, repositório nem regra de negócio (imposto por teste de arquitetura, ex.: NetArchTest);
- contrato HTTP: status, `code` do Problem Details e corpo não mudam sem decisão; campo novo de corpo é opcional ou o cliente anterior quebra; documentar o status novo no OpenAPI (inclusive `429` com `Retry-After`);
- ordem das recusas é parte do contrato (ex.: 401 → 403 permissão → corpo → 404 → 403 papel → 409 estado): uma checagem nova que vem antes de outra pode enumerar recursos ou mudar o status esperado;
- autorização: política declarada no endpoint (nunca só pela ausência de `AllowAnonymous`); acesso ao tenant ou recurso pai provado antes de qualquer leitura de objeto ou consulta cara; 404 uniforme para "não existe" e "sem acesso";
- endpoint que lê o banco por requisição autenticada precisa de limitador por ator e teto global (ex.: rate limiter por ator); sem ele o pool do Npgsql esgota;
- escrita autenticada por cookie exige o cabeçalho de CSRF; nenhum CORS;
- erro inesperado vira 500 genérico com `code` estável: a mensagem nunca ecoa conteúdo de arquivo, nome, token, `sub` nem ator;
- `Cache-Control: no-store` em resposta com dado de negócio ou de decisão;
- parâmetro de query repetido ou desconhecido é recusado (400), não ignorado; paginação por cursor com `limit` máximo;
- teste de contrato e de negação cobrem o caso novo (permissão em A, envio para B → 403).
