# wstack

Plugin do Claude Code com um workflow de desenvolvimento com agentes para qualquer projeto: revisão proporcional ao
risco, travas de permissão e portões em que uma pessoa aprova.

**Estado: versão 0.0.11, migração concluída até a 2.4.** Tem os hooks, os scripts e o setup da nuvem do harness
(`plugin/hooks`, `plugin/scripts`, `plugin/cloud`), as skills e os agentes (`plugin/skills`, `plugin/agents`), e o
`/wstack:bootstrap` com os modelos do projeto (`plugin/templates`), com os testes (`plugin/tests`, rodados no CI). O
plano e o destino de cada arquivo estão em `docs/migracao.md`; as decisões, em `docs/decisions.md`; as garantias de
cada mecanismo, em `docs/harness-capabilities.md`; o resultado das sondas, em `docs/sonda.md`.

Rodar os testes: `for t in plugin/tests/test-*.sh; do bash "$t" || exit 1; done` (precisa de bash, git, jq e node).

Adotar num projeto:
1. Instalar o plugin numa sessão: `/plugin marketplace add wesllenm/wstack` e `/plugin install wstack@wstack`.
2. Rodar `/wstack:bootstrap`: ele diagnostica o repositório, propõe os arquivos e, com a aprovação, cria o
   `.claude/settings.json` (agente `wstack:lead` e o plugin fixado numa versão), o `.claude/risk.conf`, o `CLAUDE.md` e
   os documentos que o projeto mantém, sem sobrescrever o que já existe.
3. Na nuvem, colar `plugin/cloud/setup.sh` no setup script do ambiente: ele instala o plugin na versão que o
   `.claude/settings.json` do projeto fixa.

Sem `.claude/risk.conf` o plugin fica inerte no repositório, salvo as travas de segurança.

Publicar uma versão: subir `version` em `plugin/.claude-plugin/plugin.json` no PR e, depois do merge, criar a tag
`v<versão>` na `main` (`git tag v0.0.11 <commit> && git push origin v0.0.11`): é a referência que os projetos fixam.
