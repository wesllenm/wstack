---
name: verify-{{APP}}
description: >
  Sobe {{APP}} localmente e prova comportamento pela <superfície: API HTTP, interface web, CLI> como um usuário faria:
  subir, checar saúde, exercitar a feature, capturar evidência e desmontar. Usar para reproduzir bug na superfície real,
  verificar feature ou correção antes do commit e provar o fato de segurança de uma mudança CRITICA. Com o argumento
  "manutenção", confere o mapa de features contra o código e a aplicação.
argument-hint: "[feature a verificar | manutenção]"
---

# Verificar {{APP}}

Esqueleto gerado pelo `/wstack:bootstrap`. O bootstrap (ou a primeira tarefa que precisar da skill) troca cada `<...>`
pelo que sai do repositório, nunca por exemplo genérico, e prova a skill de ponta a ponta uma vez, nesta ordem: Launch,
Doctor, Drive de uma feature do mapa, Evidence e Cleanup. Skill que nunca rodou é rascunho.

## Regras

- Exercitar o caminho real do usuário (a rota, a tela, o comando que ele usa), nunca endpoint só de teste, setter
  interno ou atalho que pula autenticação.
- Conferir o efeito colateral, não só a resposta visível: a linha gravada no banco, a mensagem publicada na fila, o
  arquivo escrito, o e-mail enviado.
- Modo dry-run ou simulação: conferir no código o que ele realmente pula antes de usá-lo como prova; o que ele pula não
  foi verificado.
- Nunca matar processo pelo nome nem por PID presumido: só pelo identificador guardado no Launch.
- Pré-condição ausente (container que não sobe, credencial, dado de seed, porta ocupada) é falha relatada com o
  motivo, nunca contornada por outro caminho que muda o que está sendo provado.

## Launch

<Comando exato que sobe a aplicação para verificação, a partir de banco e diretório de dados vazios, com migrações e
seed. Como saber que está pronta: a linha de log, o endpoint de saúde ou o estado que só aparece quando a aplicação
responde de verdade. Portas, nome do banco e projeto do Compose vêm de `.claude/worktree.env` quando ele existir, nunca
das portas fixas de desenvolvimento. Guardar o identificador do que subiu (PID, id do container, projeto do Compose)
para o Cleanup. Em .NET costuma ser `dotnet run --project <Api>` ou o AppHost do Aspire.>

## Doctor

<Uma checagem somente leitura que responde "esta instância merece ser dirigida?": processo vivo, versão e build certos,
porta pertencendo a esta instância, autenticação válida. Rodar antes da primeira condução, depois de qualquer condução
que falhou e sempre que algo parecer estranho. Em .NET, o endpoint de health check (`/health`, `/alive`).>

## Drive

<A receita com os comandos, rotas e seletores reais deste repositório. Preferir referências estáveis: rota, nome
acessível (ARIA), atributo de dados; nunca coordenada ou ordem de tabulação. Mapa de features em `features/`. Em .NET:
HTTP para a API (`curl` ou arquivo `.http`) e Playwright para a web, pelo agente `playwright-e2e`.>

## Evidence

<O que capturar e onde guardar (na pasta temporária da sessão, fora do Git): a ação e o estado resultante, e os
efeitos colaterais (consulta ao banco, mensagem na fila, log com o correlation id) além do que aparece.>

## Cleanup

<Como derrubar o que esta verificação subiu, pelo identificador guardado no Launch. O Cleanup remove só o que esta
execução criou (instâncias e estado temporário), nunca a evidência nem o que já existia.>

## Helpers

<Scripts que a skill usa, executáveis e com a chamada mostrada aqui.>

## Manutenção

Disparada pelo aviso do `map-staleness.mjs` no início da sessão (`/verify-{{APP}} manutenção`) ou a pedido do
desenvolvedor. Atualiza o mapa de features, nunca o código do produto.

1. Para cada arquivo de `features/`, um subagente somente leitura (`explore`) compara o arquivo com o código atual e
   devolve as divergências com `arquivo:linha`: rota ou seletor que mudou, subfeature nova ou removida, pegadinha que
   não vale mais.
2. Conferir os commits desde a última mudança em `features/` (`git log --format='%h %s' <sha>..HEAD`, com o SHA do aviso)
   atrás de feature visível ao usuário que falta no mapa.
3. Dirigir na aplicação (Launch, Doctor, Drive, Cleanup) cada feature que mudou, para provar a receita nova antes de
   gravá-la.
4. Só editar a pasta desta skill. Antes de terminar, `git status --porcelain` só lista caminhos em
   `.claude/skills/verify-{{APP}}/`; bug de produto encontrado vai para o relatório, nunca vira correção aqui.
5. Terminar em um dos três resultados, dito na primeira linha do relatório:
   - **limpo:** mapa em dia, sem commit nem PR;
   - **alterado:** um commit (e um PR, se o desenvolvedor pedir) com as correções provadas na aplicação;
   - **bloqueado:** sem commit, com o bloqueio descrito (pré-condição ausente, aplicação que não sobe).
