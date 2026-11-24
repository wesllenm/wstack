#!/usr/bin/env bash
# Sonda 2 do wstack, passo A: prova que uma skill do plugin chamou este script do plugin. Diz de que pasta rodou e se
# a variável CLAUDE_PLUGIN_ROOT existe no Bash da sessão (se a skill não a substituiu no texto, é dela que o caminho
# depende).
set -u
dir=$(cd "$(dirname "$0")/.." && pwd -P)
root=${CLAUDE_PLUGIN_ROOT:-}
echo "wstack-sonda-caminho: rodou de $dir; CLAUDE_PLUGIN_ROOT no Bash: ${root:-ausente}"
