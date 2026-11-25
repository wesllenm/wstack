---
name: bootstrap
description: >
  Adota o workflow do wstack num repositório: diagnostica o projeto, apresenta um único "Bootstrap proposto" para
  aprovação e cria os arquivos do projeto a partir dos modelos do plugin (.claude/settings.json com o plugin fixado,
  .claude/risk.conf, CLAUDE.md, .claude/project.md e architecture.md, docs de calibração, rubrica, gotchas e decisões,
  e a skill verify-<app> quando houver aplicação para subir), sem sobrescrever o que já existe.
disable-model-invocation: true
---

# Bootstrap do wstack

Roda uma vez por repositório (e de novo para conferir um repositório que já adotou: o script lista o que falta). Os
hooks, scripts, skills e agentes são do plugin e não são copiados; o projeto recebe só a configuração e os documentos
que ele mantém. Sem `.claude/risk.conf`, o plugin fica inerte no repositório, salvo as travas de segurança.

## 1. Diagnóstico (somente leitura)

Antes de propor qualquer arquivo, responder pelo repositório, não pelo desenvolvedor:

- Estado: repositório vazio, greenfield ou brownfield; `.claude/`, `CLAUDE.md`, `AGENTS.md` ou workflow anterior
  existentes (preservar o que é válido; não apagar nada sem análise).
- Stacks por pasta ou projeto, e os comandos de build, testes (todos e os rápidos, sem integração e E2E), formato e
  arquitetura; o que já existe de análise estática e quantos avisos há hoje.
- Branch padrão (`origin/HEAD`) e convenção de branches e commits (`git log`).
- Domínios de negócio e seus globs; caminhos críticos de verdade (autenticação, autorização, segredos, dados pessoais,
  custo de IA, migrations, contratos públicos) e o que pede plano completo (`complex`).
- Superfície do usuário (API, web, CLI) e se a aplicação sobe localmente: decide se gera a `verify-<app>`.
- Nuvem: `bash ${CLAUDE_PLUGIN_ROOT}/cloud/setup.sh --plan` mostra stacks detectadas, o que instalaria e os hosts.
- O que o bootstrap criaria e os conflitos: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh --plan` (com `--app <nome>`
  se houver aplicação). Não grava nada.
- Versão do plugin: o modelo fixa `v<versão deste plugin>`, a tag do wstack. Conferir que a tag existe com
  `git ls-remote --tags https://github.com/wesllenm/wstack v<versão>`; se não existir, fixar no commit do plugin
  instalado (`gitCommitSha` em `~/.claude/plugins/installed_plugins.json`) com `--ref <sha>`, e dizer isso na proposta.

Greenfield sem informação essencial (objetivo, usuários, stack, domínios): perguntar. Não inventar decisão.

## 2. Proposta e aprovação única

```text
## Bootstrap proposto

Modo: criação | atualização (arquivos existentes listados)
Entendimento: ...
Domínios: domínio — glob — skill
Stacks e comandos: build | testes (rápidos) | formato | arquitetura
Classificação de risco (.claude/risk.conf): critical | complex | domain | limites
Gates do Stop: verify_solution | verify_build | verify_lint | verify_test
Travas: default_branch | activity_branch | protected além do núcleo | allow_module
Permissões (.claude/settings.json): comandos exatos no allow; ask e deny da stack; WebFetch de documentação
Plugin fixado: <tag ou commit>
verify-<app>: gerar (superfície, como sobe) | não aplicável — motivo
Arquivos a criar: (saída do bootstrap.sh --plan)
Conflitos (já existem, não sobrescritos): arquivo — o que será mesclado à mão
Suposições e ambiguidades: ...

Posso executar o bootstrap?
```

Esperar uma aprovação. Depois, executar tudo sem pedir confirmação arquivo por arquivo; interromper só por decisão
de produto, arquitetura, segurança ou escopo que não dê para inferir.

## 3. Execução

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh [--projeto <nome>] [--app <nome>] [--ref <ref>]` (pede aprovação
   de propósito: grava no projeto). Ele acrescenta ao `.gitignore` o estado local do workflow, cria os arquivos que não
   existem e lista como `existe:` ou `link:` o que não tocou. Código 1 é esperado quando havia arquivos.
2. Preencher cada `<...>` dos arquivos criados com o que o diagnóstico achou, nunca com exemplo genérico:
   - `CLAUDE.md`: comandos e fatos que o código não mostra (curto: o arquivo é lido em toda sessão);
   - `.claude/risk.conf`: `critical`, `complex`, `domain`, `verify_*` e, quando couber, `allow_module`, `edit_check`,
     `checkpoint`, `feature_surface`, `cloud_*`; descomentar só o que se aplica;
   - `.claude/settings.json`: os comandos de build, teste e lint do `CLAUDE.md` no `allow` como regra exata (sem `:*`),
     o `ask` e o `deny` da stack (aplicar migration, publicar pacote, deploy) e o `WebFetch(domain:...)` da documentação
     oficial dos motores em uso; cada glob de `Edit(...)` novo no `ask` ou `deny` precisa de regra no path-guard do
     plugin (pedir no wstack, não acrescentar só aqui);
   - `.claude/project.md` (a tabela Domínios, que a skill `lead` lê) e `.claude/architecture.md`;
   - `verify-<app>`: escrever a receita real e prová-la de ponta a ponta uma vez antes de entregar.
3. Arquivo que já existia: mesclar à mão o que o modelo traz e ele não tem (no `settings.json`: `agent`,
   `worktree.baseRef`, o marketplace fixado, `enabledPlugins`, as regras de `Edit` do `ask` e do `deny`), sem apagar o
   que é do projeto. Depois de criado, `.claude/settings.json` e `.claude/risk.conf` pedem aprovação a cada edição: é
   a trava funcionando.
4. Conferir:
   - `jq . .claude/settings.json` (JSON válido);
   - `${CLAUDE_PLUGIN_ROOT}/scripts/classify-diff.sh --paths .claude/settings.json CLAUDE.md` devolve CRITICA, e um
     arquivo comum de código, SIMPLES;
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/calibrate-risk.sh` no histórico, quando houver: CRITICA acima de ~15% pede
     globs mais estreitos;
   - os comandos de `verify_*` rodam e passam no código atual (falha preexistente vai para o relatório, não para o
     `risk.conf`).
5. Commitar pela skill `commit` numa branch `chore/bootstrap-wstack`. Push e PR só com o pedido do desenvolvedor.

## Atualizar a versão do plugin

A versão vale pelo `ref` do marketplace `wstack` no `.claude/settings.json` (mudança CRITICA, com aprovação). Na nuvem,
o `setup.sh` do plugin instala essa referência quando o ambiente monta o container; para valer na sessão em curso,
rodar `bash ${CLAUDE_PLUGIN_ROOT}/cloud/setup.sh` e abrir sessão nova. Localmente, `/plugin` atualiza o marketplace.

## Checklist de saída

- [ ] Proposta aprovada antes da primeira gravação.
- [ ] Nenhum arquivo existente sobrescrito; conflitos mesclados à mão ou listados.
- [ ] Nenhum `<...>` sobrando nos arquivos criados, salvo o que ficou explicitamente a definir no relatório.
- [ ] Classificador devolve CRITICA para as defesas; gates do Stop rodam.
- [ ] Commit na branch de bootstrap; relatório com o plugin fixado e o que ficou para o desenvolvedor.
