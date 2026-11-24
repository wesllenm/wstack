# Sonda de instalação do wstack

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

| Número | O que libera | Lê-se, se rodou |
|---|---|---|
| 4 | nada (controle) | a sessão não está no modo que pede aprovação: o passo B não vale |
| 1 | `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/sonda-allow.sh 1)` | a regra aceita a variável, escrita do mesmo jeito que na skill |
| 2 | `Bash(bash /root/.claude/plugins/cache/wstack/wstack/*/scripts/sonda-allow.sh 2)` | caminho absoluto com `*` na versão casa (só serve onde a home é `/root`) |
| 3 | `Bash(bash */.claude/plugins/cache/wstack/wstack/*/scripts/sonda-allow.sh 3)` | `*` no começo casa (serve em qualquer home, mas casa com qualquer pasta que termine assim) |
| 5 | o hook `sonda-node` devolve `allow` | a aprovação vinda de hook dispensa a regra |

Regra de decisão: **A** se a e c deram certo e rodou o 1, o 3 ou o 5 (uma forma que não depende da home); senão,
**B**. Se só o 2 rodou, B: a regra amarra o projeto à home da nuvem.

Roteiro, depois do merge na main:

1. Abrir uma sessão NOVA no ambiente `wstack` (o setup script instala o plugin da main) e trocar o modo de permissão
   para o que pede aprovação antes de cada ação (não o automático: nele um classificador responde aos pedidos e o
   passo B não mede nada).
2. Pedir "rode a sonda de caminhos do wstack". No passo A, aprovar; no passo B, negar todo pedido que aparecer; no
   passo C, aprovar se aparecer pedido (não deve aparecer: o hook nega sozinho).
3. Trazer a tabela e a linha final `sonda-caminhos: a=... b=... c=...`.
