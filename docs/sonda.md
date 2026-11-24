# Sonda de instalação do wstack

| Fato | Como aparece | Se falhar |
|---|---|---|
| 1. Instala sozinho pelo `.claude/settings.json` numa sessão na nuvem | `wstack 0.0.1 carregado.` no início da sessão | instalação vira passo do setup script (`claude plugin marketplace add` + `install`) |
| 2. Os hooks do plugin rodam | pedido de aprovação do `echo wstack-sonda` | hooks ficam no projeto, gerados pelo bootstrap |
| 3. Os hooks leem a configuração do PROJETO | `sonda = projeto-wstack` no pedido e na mensagem | o caminho do projeto vem de outro jeito (cwd do payload) |
| 4. Funciona com o repositório privado | os três acima com o repositório privado | o repositório fica público, ou o ambiente recebe acesso |

Roteiro: depois do push na main, abrir uma sessão NOVA neste repositório e pedir "rode a sonda do wstack"; trazer a
linha final `sonda: ...`.
