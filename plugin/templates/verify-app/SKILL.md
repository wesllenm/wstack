---
name: verify-{{APP}}
description: >
  Sobe {{APP}} localmente e prova comportamento pela <superfície: API HTTP, interface web, CLI> como um usuário faria:
  subir, checar saúde, exercitar a feature, capturar evidência e desmontar. Usar para reproduzir bug na superfície real,
  verificar feature ou correção antes do commit e provar o fato de segurança de uma mudança CRITICA.
---

# Verificar {{APP}}

Esqueleto gerado pelo `/wstack:bootstrap`. O bootstrap (ou a primeira tarefa que precisar da skill) troca cada `<...>`
pelo que sai do repositório, nunca por exemplo genérico, e prova a skill de ponta a ponta uma vez (Launch, Doctor, Drive
de uma feature do mapa, Evidence, Cleanup) antes de contar com ela. Skill que nunca rodou é rascunho.

## Launch

<Comando exato que sobe a aplicação para verificação, a partir de banco e diretório de dados vazios, com migrações e
seed. Como saber que está pronta: a linha de log, o endpoint de saúde ou o estado que só aparece quando a aplicação
responde de verdade. Portas, nome do banco e projeto do Compose vêm de `.claude/worktree.env` quando ele existir, nunca
das portas fixas de desenvolvimento.>

## Doctor

<Uma checagem somente leitura que responde "esta instância merece ser dirigida?": processo vivo, versão e build certos,
porta pertencendo a esta instância, autenticação válida. Rodar antes da primeira condução, depois de qualquer condução
que falhou e sempre que algo parecer estranho.>

## Drive

<A receita com os comandos, rotas e seletores reais deste repositório. Preferir referências estáveis: rota, nome
acessível (ARIA), atributo de dados; nunca coordenada ou ordem de tabulação. Mapa de features em `features/`.>

## Evidence

<O que capturar e onde guardar (na pasta temporária da sessão, fora do Git). Exercitar o caminho real do usuário, nunca
um setter interno ou endpoint só de teste; capturar a ação e o estado resultante; conferir os efeitos colaterais (linha
gravada, mensagem publicada, arquivo escrito) além do que aparece.>

## Cleanup

<Como derrubar o que esta verificação subiu, pelo identificador guardado no Launch (nunca matar processo pelo nome). O
Cleanup remove instâncias e estado temporário, nunca a evidência.>

## Helpers

<Scripts que a skill usa, executáveis e com a chamada mostrada aqui.>
