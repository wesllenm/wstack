# Performance — Bash (scripts de CI e hooks do projeto)

Raramente se aplica. Só quando o script estiver num caminho quente: hook `Stop` (roda a cada turno), `ci/in-container.sh` ou laço sobre milhares de arquivos.

- Medir com `time` ou `hyperfine` (não instalado) antes e depois; tempo varia por máquina e é só informativo.
- Anti-padrões típicos: processo por iteração em laço grande (`$(...)` dentro de `for`), cadeias `cat | grep | awk` que um `awk` resolve, `while read` sem `-r`, `git` chamado uma vez por arquivo.
- No Git Bash do Windows, criar processo é caro (~dezenas de ms): reduzir `fork`/`exec` em hooks vale mais que em Linux.
- Sem camadas 2, 3 e 3b.
