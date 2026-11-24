---
name: commit
description: >
  Cria commits atômicos com título e descrição bem escritos, em Conventional
  Commits com assunto e corpo em português. Carregar sempre que for commitar,
  separar mudanças em commits ou escrever mensagem de commit.
allowed-tools: Bash(git status:*)
---

# Commit

## Objetivo

Um histórico que explica por que o código mudou, legível em `git log --oneline`, revertível commit a commit e útil para review, `git bisect` e changelog.

## Quando aplicar

- Ao final de uma unidade que passou nos gates do plano, quando o plano prevê commits.
- Um commit por lote coerente na `test-audit`.
- Nunca commitar estado com build quebrado ou testes relevantes falhando, salvo commit de handoff explicitamente pedido.

## Convenção do projeto

Decidida no bootstrap (`docs/decisions.md`): **Conventional Commits com assunto e corpo em português brasileiro**. Types e scopes em inglês minúsculo (são identificadores); assunto no infinitivo. [GIT-02]

## Antes de escrever

1. `git status` e `git diff`: entender tudo o que mudou, inclusive arquivos não rastreados.
2. Conferir o `git log --oneline -30` para manter consistência de scopes e estilo.
3. Separar em commits atômicos: uma mudança lógica por commit. Refatoração, formatação em massa e mudança de comportamento vão em commits separados. Teste vai no mesmo commit do código que ele cobre. [GIT-01]
4. Fazer staging explícito por caminho (`git add <caminhos>`). Nunca `git add -A` ou `git add .` sem revisar o status.
5. Conferir `git diff --staged`: nada de segredo, `.env`, credencial, dump, arquivo temporário, código de debug ou mudança fora do escopo aprovado. Mudanças alheias no working tree ficam de fora e são reportadas. [GIT-05]

## Título

Formato: `<type>(<scope>)!: <assunto>`

Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`, `style`, `revert`.

Scopes: os domínios e áreas do projeto, consistentes com o `git log` (ex.: `orders`, `billing`, `api`, `web`, `observability`, `ci`, `claude` para o workflow de desenvolvimento).

- `scope` é opcional e nomeia o módulo, domínio ou slice afetado;
- `!` indica quebra de compatibilidade (detalhada no rodapé);
- assunto no infinitivo: "adicionar", "corrigir", "remover" (não "adicionado", "corrige");
- idealmente até 50 caracteres, no máximo 72;
- sem ponto final; minúscula após o type, salvo nomes próprios;
- descreve o efeito, não a atividade: "impedir cobrança duplicada no reenvio do webhook", não "atualizar serviço de aprovação";
- proibido título genérico: "fix bug", "wip", "ajustes", "alterações", "diversos", "update".

Teste do título: ele completa a frase "Se aplicado, este commit vai ___"?

## Descrição

- linha em branco entre título e corpo; quebrar linhas em 72 colunas;
- explica o porquê e o quê, não o como (o diff mostra o como); [GIT-03]
- traz contexto: problema, causa raiz, alternativa descartada quando relevante, efeitos colaterais e riscos;
- usa lista com `-` quando há vários pontos;
- omitir o corpo só em mudança trivial e autoexplicativa;
- não narra o processo ("rodei os testes", "o agente fez"), não cola log nem diff.

## Pull request

Quando o plano prevê PR, a descrição é um resumo de um minuto para quem tem o diff na tela, não um diário. Seções `##` nesta ordem, omitindo a que não tiver o que dizer:

- `## Por quê`: o problema e a abordagem, em uma a três frases;
- `## O que mudou`: uma a três linhas, nomeando símbolo ou caminho só quando ele carrega a mudança;
- `## Escopo`: o que cobre e o que ficou de fora de propósito (follow-up, lacuna conhecida);
- `## O que pode quebrar`: quem ou o que a mudança toca, e por que é seguro ou arriscado; em CRITICA, o fato de segurança e o degrau de prova;
- `## Verificação`: cada linha um caminho real e o resultado (gates, testes novos, condução na aplicação com o caminho da evidência); número de performance com unidade, antes e depois.

Logs, tabelas de achados e listas de arquivos vão para o relatório, não para o PR.

Abrir com `gh pr create --title "<título do commit principal>" --body-file <arquivo na pasta temporária>` e rotular com o nível de risco do `classify-diff.sh` (`--label risco:<trivial|simples|complexa|critica>`): o rótulo decide quantas aprovações humanas o PR exige e se ele pode entrar sozinho quando os checks ficarem verdes (workflow `merge-por-risco`).

Antes de abrir, conferir se a branch já tem PR aberto (`gh pr list --head <branch> --state open`): se tiver, atualizar a descrição dele em vez de abrir outro. Depois de abrir, conferir o que o GitHub recebeu (`gh pr view <branch> --json url,headRefOid,baseRefName`): o `headRefOid` precisa ser o SHA verificado, e a base, a pretendida; divergência é reportada, não corrigida às cegas. O resultado da CI do GitHub é reportado separado das checagens locais.

## Rodapé

- `BREAKING CHANGE: <o que quebra e como migrar>` (token em inglês, exigido pela especificação);
- `Refs: #123` ou `Closes: #123`, conforme o tracker;
- `Co-Authored-By:` e outros trailers conforme a política do projeto.

## Como executar

Mensagem multilinha via heredoc, sem editor interativo:

```bash
git commit -F - <<'EOF'
fix(billing): impedir cobrança duplicada no reenvio do webhook

O webhook de confirmação de pagamento não era deduplicado pelo id de
entrega, e o pedido era cobrado duas vezes quando o provedor reenviava
a notificação após um timeout.

- ignorar entregas com id de entrega já processado
- adicionar teste de regressão que reproduz a cobrança duplicada

Refs: #42
EOF
```

A forma é exata e vai sozinha numa chamada: `git add <caminhos>` numa e o `git commit -F - <<'EOF'` noutra, sem `&&`, sem `-m` e sem `$(cat ...)`. Só ela (ou `git commit -F <arquivo na pasta temporária>`) roda sem pedido de permissão: o hook `git-read-allow` não libera outra forma de commit.

Depois do commit, conferir com `git log -1 --stat`.

## Exemplos

- Bom: `feat(orders): adicionar modelo canônico do pedido`
- Ruim: `Adicionado modelo e testes.`
- Bom: `refactor(adapters): extrair validação de assinatura de webhook`
- Ruim: `refactor + fix login + format`
- Bom: `test(billing): cobrir corte por limite de crédito`
- Ruim: `mais testes`

## Restrições

- checkpoint de sessão na nuvem (skill `lead`, Execução na nuvem) não é commit desta skill: é um objeto avulso numa ref `wip/`, fora de qualquer branch, e não segue estas regras de título nem de testes verdes;
- nunca usar `--no-verify`; se um hook de pre-commit falhar, corrigir a causa e commitar de novo; [GIT-07]
- nunca `--amend`, rebase ou reescrita de histórico em commit já publicado; [GIT-07]
- nunca push, force push, reset ou alteração de histórico sem pedido explícito; o push da branch de atividade (`git push -u origin <chore|feat|fix|task|claude>/...`) está no `allow` e só acontece quando o plano o prevê, e o hook `push-guard` pergunta ou recusa o resto (force, `main`, apagar ref);
- não commitar direto em `main`; criar a branch `feat/<id>-<slug>`, `fix/...` ou `chore/...`.

## Greenfield

Esta convenção vale desde o primeiro commit.

## Brownfield

Não se aplica: se o projeto mudar de convenção, registrar em `docs/decisions.md` e não reescrever histórico para padronizar.

## Checklist de saída

- [ ] convenção do projeto verificada;
- [ ] um propósito por commit;
- [ ] staging revisado com `git diff --staged`;
- [ ] sem segredo, debug, temporário ou arquivo fora do escopo;
- [ ] título no infinitivo, específico e com até 72 caracteres;
- [ ] corpo explica o porquê quando a mudança não é trivial;
- [ ] quebra de compatibilidade e referências no rodapé;
- [ ] build e testes relevantes passando no estado commitado.
