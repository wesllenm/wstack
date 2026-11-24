# wstack

Plugin do Claude Code com um workflow de desenvolvimento com agentes para qualquer projeto: revisão proporcional ao
risco, travas de permissão e portões em que uma pessoa aprova.

**Estado: versão 0.0.1, só a sonda de instalação.** Roteiro em `docs/sonda.md`.

Instalar num projeto: no `.claude/settings.json`, `extraKnownMarketplaces` com `wstack` apontando para o GitHub
`wesllenm/wstack` e `enabledPlugins` com `"wstack@wstack": true` (como o `.claude/settings.json` deste repositório),
ou numa sessão `/plugin marketplace add wesllenm/wstack` e `/plugin install wstack@wstack`.
