# Sonda de instalação do wstack

Registro das sondas 1 e 2. As peças delas (skills `sonda` e `sonda-caminhos`, hooks e scripts `sonda-*`, as regras
`allow` de teste do `.claude/settings.json`) saíram na versão 0.0.4, quando os hooks reais entraram no plugin.

| Fato | Como aparece | Se falhar |
|---|---|---|
| 1. Instala sozinho pelo `.claude/settings.json` numa sessão na nuvem | `wstack <versão> carregado.` no início da sessão | instalação vira passo do setup script (`claude plugin marketplace add` + `install`) |
| 2. Os hooks do plugin rodam | `ask` do hook no registro da sessão para o `echo wstack-sonda` (o diálogo só aparece fora do modo automático) | hooks ficam no projeto, gerados pelo bootstrap |
| 3. Os hooks leem a configuração do PROJETO | `sonda = projeto-wstack` no pedido e na mensagem | o caminho do projeto vem de outro jeito (cwd do payload) |
| 4. Funciona com o repositório privado | os três acima com o repositório privado | o repositório fica público, ou o ambiente recebe acesso |

Roteiro: depois do push na main, abrir uma sessão NOVA neste repositório e pedir "rode a sonda do wstack"; trazer a
linha final `sonda: ...`.

## Resultado da primeira rodada (2026-11-24)

Sessão na nuvem, repositório público, `main` em `9ecae8c`: **`sonda: falhou em 1`**.

- **Fato 1 falhou.** O `.claude/settings.json` declara o marketplace e o `enabledPlugins`, mas a sessão começou sem
  nenhum plugin instalado (`claude plugin list`: "No plugins installed"). Sem plugin, a skill e os dois hooks não
  carregaram, e os fatos 2 e 3 não tiveram como ser testados.
- **Fato 4 não é a causa.** O repositório é público e `claude plugin marketplace add wesllenm/wstack` clonou do
  GitHub sem problema.
- **A alternativa da tabela funciona.** Na mesma sessão, `claude plugin marketplace add wesllenm/wstack` e
  `claude plugin install wstack@wstack` instalaram o `wstack@wstack` 0.0.1 (escopo user, ativo). Os dois comandos
  podem rodar de novo sem erro.

Mudança feita: o ambiente de nuvem `wstack` (pessoal) ganhou este setup script, que roda quando um container é
criado do zero:

```bash
claude plugin marketplace add wesllenm/wstack
claude plugin install wstack@wstack
```

Próximo passo: abrir uma sessão NOVA no ambiente `wstack`, pedir "rode a sonda do wstack" e conferir os fatos 1 a 3
com o plugin instalado pelo setup script.

## Resultado da segunda rodada (2026-11-24)

Sessão nova no ambiente `wstack`, plugin 0.0.1 instalado pelo setup script, modo de permissão automático:
**`sonda: ok`** depois de conferir o registro da sessão (a skill 0.0.1 tinha dito `falhou em 3`).

- **Fato 1 ok.** `wstack 0.0.1 carregado.` no início da sessão, com plugin e projeto definidos.
- **Fato 2 ok.** O hook `PreToolUse:Bash` rodou no `echo wstack-sonda` e devolveu `ask`. No modo automático o
  classificador responde ao `ask` sem mostrar diálogo, e o comando rodou sem pedido visível. Por isso a skill 0.0.1,
  que esperava o diálogo, deu falso negativo.
- **Fato 3 ok.** `sonda = projeto-wstack` na mensagem do `SessionStart`, no `ask` do `PreToolUse` e no
  `.claude/risk.conf`.

Mudança feita (0.0.2): o passo 3 da skill confere o `ask` do hook no registro da sessão
(`~/.claude/projects/*/<sessão>.jsonl`) em vez de esperar o diálogo.

# Sonda 2: caminhos

Decide onde ficam os scripts que as skills e os hooks rodam: **A**, dentro do plugin, chamados por
`${CLAUDE_PLUGIN_ROOT}`; ou **B**, copiados para o `.claude/` do projeto pelo bootstrap, chamados por caminho relativo
(`bash .claude/scripts/<nome>.sh`), com regras `allow` que já sabemos que casam.

| Fato | Como a sonda prova | Peças |
|---|---|---|
| a. Uma skill do plugin chama um script do plugin por `${CLAUDE_PLUGIN_ROOT}` | o texto da skill mostra a variável trocada pelo caminho, ou o Bash tem a variável; o script imprime de que pasta rodou | `skills/sonda-caminhos`, `scripts/sonda-caminho.sh` |
| b. Uma regra `allow` do `.claude/settings.json` do projeto casa com o caminho do script | no modo que pede aprovação, o desenvolvedor nega todo pedido; o número que rodou mesmo assim foi liberado pela sua regra | `scripts/sonda-allow.sh`, regras 1 a 3 no `.claude/settings.json` |
| c. Um hook Node do plugin importa outros módulos do plugin | o hook nega `echo wstack-sonda-node` com um motivo montado por um módulo da mesma pasta e um de `lib/` | `hooks/sonda-node.sh`, `hooks/sonda-node.mjs`, `hooks/sonda-modulo.mjs`, `lib/sonda-comum.mjs` |

Os números do passo B:

| Número | O que libera | Só se aplica se | Lê-se, se rodou |
|---|---|---|---|
| 4 | nada (controle) | sempre | a sessão não está no modo que pede aprovação: o passo B não vale |
| 1 | `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-allow.sh 1)` | a = variável só no Bash | a regra libera comando com a variável escrita |
| 2 | `Bash(bash /root/.claude/plugins/cache/wstack/wstack/*/scripts/sonda-allow.sh 2)` | a = variável trocada no texto | caminho absoluto com `*` na versão casa (só serve onde a home é `/root`) |
| 3 | `Bash(bash */.claude/plugins/cache/wstack/wstack/*/scripts/sonda-allow.sh 3)` | a = variável trocada no texto | `*` no começo casa (serve em qualquer home, mas casa com qualquer pasta que termine assim) |
| 5 | o hook `sonda-node` devolve `allow` para o comando exato | sempre | a aprovação vinda de hook dispensa a regra |

A regra é comparada com o texto do comando que o agente manda, não com o caminho que o bash expande; por isso a coluna
"só se aplica se". Um 1 negado não prova que a forma da regra está errada: o Claude Code pode pedir aprovação para
todo comando com `${...}`, mesmo com regra que casa. Para o workflow, a leitura é a mesma: comando com a variável
escrita não roda sem pedido por regra.

Regra de decisão:
- **A** se a e c deram certo e rodou o 1 ou o 3 (uma regra que não depende da home). Se foi o 1, A depende de a
  variável existir no Bash, o que só esta sessão mediu.
- **A com hook aprovador** se a e c deram certo, o 1 e o 3 não rodaram e o 5 rodou. É outro desenho: o plugin aprova
  os próprios scripts por hook, comparando o comando exato (nunca um padrão). Fica para o desenvolvedor decidir.
- **B** nos outros casos. Se só o 2 rodou, B: a regra amarra o projeto à home da nuvem.

Roteiro, depois do merge na main:

1. Abrir uma sessão NOVA no ambiente `wstack` (o setup script instala o plugin da main) e trocar o modo de permissão
   para o que pede aprovação antes de cada ação (não o automático: nele um classificador responde aos pedidos e o
   passo B não mede nada).
2. Pedir "rode a sonda de caminhos do wstack". No passo A, aprovar só desta vez (nunca "não perguntar de novo": a regra
   gravada liberaria números do passo B). No passo B, negar todo pedido que aparecer com um "No" simples, sem dizer
   ao agente o que fazer diferente; se ele parar depois de uma negação, responder "continue a sonda". No passo C,
   aprovar só desta vez se aparecer pedido (não deve aparecer: o hook nega sozinho).
3. Trazer a tabela e a linha final `sonda-caminhos: a=... b=... c=...`.

## Resultado da sonda 2 (2026-11-24)

Primeira tentativa sem valor: a sessão restaurou o container guardado pelo ambiente antes da 0.0.3 ("Restored saved
setup"; o setup script não rodou), carregou o plugin 0.0.1, que não tem a skill, e estava no modo automático. A
correção do setup script está em `docs/decisions.md` (plugin atualizado ao iniciar a sessão na nuvem).

Segunda tentativa: container novo, plugin 0.0.3, modo "Accept edits". Linha da skill:
`sonda-caminhos: a=variável trocada no texto b=1,2,3,4,5 (controle 4 rodou: passo B não vale); não se aplica: 1 c=ok`.
O registro da sessão diz quem liberou cada comando (`permission_decision` no resultado de cada ferramenta):

| Passo | Veio | `permission_decision` |
|---|---|---|
| A | o texto da skill chegou com `/root/.claude/plugins/cache/wstack/wstack/0.0.3` no lugar de `${CLAUDE_PLUGIN_ROOT}`, em todas as ocorrências (até na frase que explicava a variável); o script imprimiu `rodou de /root/.claude/plugins/cache/wstack/wstack/0.0.3; CLAUDE_PLUGIN_ROOT no Bash: ausente` | `accept`, `rule`, `config` |
| B, números 4, 1, 2, 3 | rodaram | `accept`, `rule`, `config` em todos, inclusive no controle 4, que não tem regra no projeto |
| B, número 5 | rodou | `accept`, `hook`, `hook` |
| C | negado com `wstack-sonda-node: hook Node rodou; módulo da mesma pasta: ok; módulo de outra pasta: ok` | `reject`, `hook`, `hook` |

Leitura:
- **a ok:** a variável é trocada no texto da skill ao carregar; o Bash não a tem.
- **b não mensurável na nuvem:** uma regra de configuração que não é do projeto libera todo Bash (o controle saiu
  igual às regras testadas), e o registro não diz qual regra casou. As configurações da plataforma não são legíveis
  pela sessão.
- **aprovação por hook ok:** o 5 foi liberado pelo hook, não por regra.
- **c ok:** o hook Node do plugin importou um módulo da mesma pasta e um de `lib/`.

A regra de decisão não previa um passo B sem valor (o controle rodou), então ela não decide sozinha. Com a e c
certos, o 5 aprovado por hook e nenhuma regra mensurável, o desenvolvedor escolheu "A com hook aprovador"
(`docs/decisions.md`, scripts no plugin, aprovados por hook).
