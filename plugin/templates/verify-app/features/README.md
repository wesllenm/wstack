# Mapa de features de {{APP}}

Atualizado em {{DATA}}. Um arquivo por feature visível ao usuário, começando pelas três a cinco principais (das rotas,
comandos, menus ou documentação). O `map-staleness.mjs` do plugin avisa no início da sessão quando a superfície
(`feature_surface` no `.claude/risk.conf`) mudou depois da última mudança nesta pasta; aí a seção Manutenção da skill
(`/verify-{{APP}} manutenção`) põe o mapa em dia.

| Feature | Arquivo |
|---|---|
| <feature> | `<feature>.md` |

Cada arquivo de feature tem estas quatro seções:

```markdown
# <Feature>

## Subfeatures
<o que o usuário consegue fazer nesta feature, um item por ação>

## Como chegar (visão do usuário)
<o caminho na interface, na API ou na CLI, do ponto de partida do usuário até a feature>

## Como dirigir
<os comandos, rotas e seletores reais que a seção Drive da skill usa para exercitá-la, e o efeito colateral a conferir>

## Pegadinhas
<o que já enganou uma verificação: estado que precisa existir antes, espera assíncrona, dado de seed, permissão>
```
