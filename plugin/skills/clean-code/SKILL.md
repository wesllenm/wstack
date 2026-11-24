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

- nomes revelam intenção e usam a linguagem ubíqua de `docs/glossary.md`; o idioma dos identificadores é definido por sistema (padrão: inglês) e a mesma palavra vale no glossário e no código;
- nomes seguem o guia oficial da linguagem, imposto pelo linter ou formatador do projeto no build;
- funções têm responsabilidade clara;
- efeitos colaterais são explícitos (nome e assinatura deixam claro que grava, publica ou chama fora);
- erros não são engolidos: `catch` vazio ou que só loga e segue é proibido sem justificativa;
- resultados esperados de negócio (validação, regra violada) são retorno tipado, não exceção;
- dependências têm fronteiras claras e entram por parâmetro ou construtor;
- comentários explicam por quê ou restrições não óbvias; nada de narrar o código, código comentado ou `TODO`/`FIXME`/`HACK` no código (o que ficou para depois vira follow-up no relatório); o `diff-smells.mjs` aponta o que o diff adicionou;
- válvula de escape (supressão de aviso, null-forgiving, `any`, bloqueio de async, `catch` vazio) é sinal de desenho a resolver, não atalho: antes de usar uma, perguntar por que o tipo ou o fluxo a pediu;
- diagramas são código (Mermaid ou o equivalente do perfil), com descrição textual equivalente e sintaxe validada; sem link, `click` nem HTML nos rótulos;
- código morto é removido dentro do escopo.

## Greenfield

Tipagem estrita, warnings novos como erro e análise estática ligados desde o início.

## Brownfield

Seguir convenções de código não tocado.

## Restrições e cuidados

Não impor limites fixos de linhas, argumentos, exceções ou comentários sem avaliar contexto.

## Testes obrigatórios

Não se aplica diretamente; formatador em modo de verificação e análise estática no build.

## Exceções e limites

Código gerado (migrations, clientes de API) fica fora das regras de estilo.

## Checklist de saída

- [ ] nomes do glossário;
- [ ] nenhum erro engolido;
- [ ] efeitos colaterais explícitos;
- [ ] formatador sem diferenças.
