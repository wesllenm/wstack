---
name: clean-code
description: >
  Orienta código legível, explícito e coeso por meio de nomes, funções,
  tratamento de erros, baixo acoplamento e complexidade controlada.
---

# Clean Code

## Objetivo

Código que outra pessoa (ou outro agente) entende na primeira leitura.

## Quando aplicar

Todo código novo ou alterado.

## Princípios

- nomes revelam intenção e usam a linguagem ubíqua de `docs/glossary.md` (em inglês no código: `Demand`, `Artifact`, `Stage`, `Gate`, `Approval`); o idioma dos identificadores é definido por sistema (padrão: inglês) e a mesma palavra vale no glossário e no código; [NOM-06]
- nomes seguem o guia oficial da linguagem (.NET: guia de design da Microsoft), imposto pelo `.editorconfig` raiz no build: tipos, métodos e propriedades em PascalCase, interfaces com `I`, parâmetros e locais em camelCase, campos de instância privados em `_camelCase` e estáticos em PascalCase, métodos `async` terminando em `Async` (fora de `tests/`); [NOM-01]
- funções têm responsabilidade clara;
- efeitos colaterais são explícitos (nome e assinatura deixam claro que grava, publica ou chama fora);
- erros não são engolidos: `catch` vazio ou que só loga e segue é proibido sem justificativa; [QLT-01]
- resultados esperados de negócio (validação, regra violada) são retorno tipado, não exceção; [QLT-01]
- dependências têm fronteiras claras e entram pelo construtor;
- comentários explicam por quê ou restrições não óbvias; [DOC-04] nada de narrar o código, código comentado ou `TODO`/`FIXME`/`HACK` no código (o que ficou para depois vira follow-up no relatório); o `diff-smells.mjs` aponta o que o diff adicionou;
- válvula de escape (supressão de aviso, null-forgiving `!`, `dynamic`, `.Result`/`.Wait()`, `catch` vazio; `any` e `@ts-ignore` no portal) é sinal de desenho a resolver, não atalho: antes de usar uma, perguntar por que o tipo ou o fluxo a pediu;
- diagramas são código (Mermaid ou o equivalente do perfil), com descrição textual equivalente e sintaxe validada; sem link, `click` nem HTML nos rótulos [DOC-05]
- código morto é removido dentro do escopo;
- C# moderno: `record` para dados imutáveis, `required`, nullable reference types ligado, `sealed` por padrão em classes que não foram desenhadas para herança;
- async até o fim: nada de `.Result`, `.Wait()` ou `async void`; propagar `CancellationToken`.

## Greenfield

Nullable, `TreatWarningsAsErrors` para warnings novos e analisadores Roslyn ligados em `Directory.Build.props` desde o início.

## Brownfield

Seguir convenções de código não tocado.

## Restrições e cuidados

Não impor limites fixos de linhas, argumentos, exceções ou comentários sem avaliar contexto.

## Testes obrigatórios

Não se aplica diretamente; `dotnet format --verify-no-changes` e analisadores no build. [GIT-04]

## Exceções e limites

Código gerado (migrations, clientes OpenAPI) fica fora das regras de estilo.

## Checklist de saída

- [ ] nomes do glossário;
- [ ] nenhum erro engolido;
- [ ] efeitos colaterais explícitos;
- [ ] async correto com cancelamento;
- [ ] `dotnet format` sem diferenças.
