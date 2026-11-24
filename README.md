# wstack

Plugin do Claude Code com um workflow de desenvolvimento com agentes para qualquer projeto: revisão proporcional ao
risco, travas de permissão e portões em que uma pessoa aprova.

**Estado: versão 0.0.4, em migração.** Já tem os hooks e os scripts do harness (`plugin/hooks`, `plugin/scripts`,
`plugin/cloud`) com os testes (`plugin/tests`, rodados no CI); as skills, os agentes e o `/wstack:bootstrap` vêm a
seguir. O plano e o destino de cada arquivo estão em `docs/migracao.md`; as decisões, em `docs/decisions.md`; o
resultado das sondas de instalação e de caminhos, em `docs/sonda.md`.

Rodar os testes: `for t in plugin/tests/test-*.sh; do bash "$t" || exit 1; done` (precisa de bash, git, jq e node).

Instalar num projeto: no `.claude/settings.json`, `extraKnownMarketplaces` com `wstack` apontando para o GitHub
`wesllenm/wstack` e `enabledPlugins` com `"wstack@wstack": true` (como o `.claude/settings.json` deste repositório),
ou numa sessão `/plugin marketplace add wesllenm/wstack` e `/plugin install wstack@wstack`.
