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
que ele mantém. Sem `.claude/risk.conf`, o plugin fica inerte no repositório, salvo as travas de segurança. Na nuvem,
num projeto que ainda não adotou o wstack, o `setup.sh` do plugin já instalou a maior tag publicada: é a versão deste
plugin, e a mesma que o modelo fixa, então a sessão seguinte ao merge não troca de versão.

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
- Revisão por outro fornecedor (`interrogate_cmd`, revisão de COMPLEXA e CRITICA): quais CLIs de modelo de outro
  fornecedor existem na máquina (`command -v` de cada uma) e se o repositório é de cliente, com contrato ou política
  sobre mandar código para terceiros. O diagnóstico só levanta; ligar é decisão do desenvolvedor, na proposta.
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
Revisão por outro fornecedor: ligar com <CLI> (o diff de COMPLEXA e CRITICA sai para <fornecedor>) | não ligar — motivo
verify-<app>: gerar (superfície, como sobe) | não aplicável — motivo
Arquivos a criar: (saída do bootstrap.sh --plan)
Conflitos (já existem, não sobrescritos): arquivo — o que será mesclado à mão
Suposições e ambiguidades: ...

Posso executar o bootstrap?
```

A linha de revisão por outro fornecedor nunca fica de fora nem vem marcada por padrão: ela pergunta, com o custo dito
por extenso (o diff sai da máquina para o fornecedor do modelo). Sem CLI disponível, a proposta diz isso e o que
instalar, e a resposta padrão é não ligar.

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
   - revisão por outro fornecedor: se aprovada, `interrogate_cmd = <nome> <comando>` no `.claude/risk.conf`, com a CLI
     em modo não interativo, lendo da entrada padrão, sem ferramentas de escrita nem de execução, e a chave dela fora
     do repositório (variável de ambiente; na nuvem, credencial do ambiente e o host do fornecedor liberado na rede).
     Rodar uma vez com um pacote de teste (`node ${CLAUDE_PLUGIN_ROOT}/scripts/interrogate.mjs <pacote> <saída>`) e ver
     sair 0. Aprovada ou não, a escolha vai para `docs/decisions.md` do projeto, com o motivo;
   - `.claude/project.md` (a tabela Domínios, que a skill `lead` lê) e `.claude/architecture.md`;
   - `verify-<app>`: escrever a receita real nas seis seções do modelo (Launch, Doctor, Drive, Evidence, Cleanup,
     Helpers), o mapa de `features/` com as três a cinco features principais, cada uma nas quatro seções do
     `features/README.md`, e o `feature_surface` do `.claude/risk.conf` com os caminhos dessas features. Provar de
     ponta a ponta uma vez antes de entregar, nesta ordem: Launch, Doctor, Drive de uma feature do mapa, Evidence e
     Cleanup.
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
- [ ] Revisão por outro fornecedor decidida na proposta e registrada em `docs/decisions.md`, ligada ou não.
- [ ] Commit na branch de bootstrap; relatório com o plugin fixado e o que ficou para o desenvolvedor.
