# Decisões

Cada decisão: data, o que se decidiu, por quê (com a evidência) e o que muda. Decisão nova entra no fim; decisão que
muda uma anterior cita a anterior pela data, e nenhuma entrada é apagada.

## {{DATA}}: adoção do workflow do wstack

**Decisão:** o projeto usa o plugin wstack fixado em `{{WSTACK_REF}}` (`.claude/settings.json`), com o agente
`wstack:lead` como entrada da sessão. A configuração do projeto está em `.claude/risk.conf`.

**O que muda:** o nível de risco de cada mudança vem do classificador do plugin; ajustar os globs de `.claude/risk.conf`
(o que é crítico, complexo ou domínio) é decisão do desenvolvedor, registrada aqui.
