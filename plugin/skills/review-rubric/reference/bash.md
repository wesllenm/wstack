# Review — Sempre verificar, Bash (scripts de CI e hooks do projeto)

Aplicar às linhas do diff em `*.sh`.

- `set -euo pipefail` (ou motivo para não usar); variável sem aspas; `rm -rf "$dir/"` com variável que pode estar vazia (usar `${dir:?}`);
- `cd` sem `|| exit`; parsing de `ls`; `for f in $(find ...)` quebrando em espaço (usar `-print0` e `read -d ''`);
- arquivo temporário sem `mktemp` e sem `trap` de limpeza; `eval` com entrada externa;
- opção que muda entre GNU, BSD e o Git Bash do Windows (`sed -i`, `date -d`, `readlink -f`); fim de linha CRLF; caminho POSIX convertido pelo MSYS antes de chegar ao `docker`; `> nul` em vez de `/dev/null`;
- dependência de versão do Bash: `mapfile -d` e recursos equivalentes exigem Bash >= 4.4 (o Git Bash do Windows e o Linux do CI têm; não assumir o Bash 3.2 do macOS);
- teste com caminho com espaço, nome UTF-8, arquivo vazio ou binário e arquivo staged, não rastreado, renomeado ou removido, e comparadores `awk` com fixture conhecida (o `tests/test-classify.sh` do wstack é o modelo);
- script que sobe processo (`dotnet`, `docker`) sem prazo, ou que não encerra a árvore de processos ao sair;
- validação com `jq` por `test("^...$")`: o `$` do Oniguruma casa antes de `\n` final; validar com classe negada (`test("[^...]") | not`) e `length`;
- hook ou script de `ci/` que contorna uma verificação (`--no-verify`, `|| true` escondendo falha) ou que escreve no repositório.

Camada determinística: ShellCheck sem supressão nova (`# shellcheck disable=` é supressão e exige autorização). Sinais de qualidade: só duplicação (`jscpd --format bash`); CRAP não se aplica a Bash. `shfmt -d` e `bats-core` (script com lógica) ainda não estão instalados: adotar só com aprovação. Em `ask`: `.shellcheckrc`, `.editorconfig`.
