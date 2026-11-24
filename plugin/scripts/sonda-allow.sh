#!/usr/bin/env bash
# Sonda 2 do wstack, passo B: alvo das regras allow. Cada número é casado por uma forma de regra diferente (ou por
# nenhuma, no controle); se rodou sem pedido de aprovação, a regra daquele número casou.
set -u
echo "wstack-sonda-allow: ${1:-sem número} rodou"
