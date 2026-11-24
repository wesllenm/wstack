# Sonda de instalação do wstack

| Fato | Como aparece | Se falhar |
|---|---|---|
| 1. Instala sozinho pelo `.claude/settings.json` numa sessão na nuvem | `wstack 0.0.1 carregado.` no início da sessão | instalação vira passo do setup script (`claude plugin marketplace add` + `install`) |
| 2. Os hooks do plugin rodam | pedido de aprovação do `echo wstack-sonda` | hooks ficam no projeto, gerados pelo bootstrap |
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
