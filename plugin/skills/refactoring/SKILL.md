---
name: refactoring
description: >
  Melhora a estrutura interna sem alterar comportamento, tratando duplicação,
  acoplamento, legibilidade e code smells dentro do escopo aprovado.
---

# Refactoring

## Objetivo

Deixar o código tocado pela tarefa mais fácil de entender e mudar, sem alterar comportamento observável.

## Quando aplicar

Nomes ruins, duplicação real, baixa coesão, acoplamento ou complexidade que afete a tarefa em curso. Refatoração ampla é tarefa própria, pedida e aprovada como tal.

## Processo

1. identificar o comportamento protegido;
2. obter testes ou caracterização que o cubram;
3. fazer uma mudança pequena (renomear, extrair, mover, inline);
4. executar os testes;
5. manter ou desfazer;
6. repetir.

## Princípios

- refatoração e mudança de comportamento em commits separados (skill `commit`);
- preferir refatorações automáticas do IDE ou da ferramenta da stack a edição manual quando disponíveis;
- duplicação acidental em dois slices é aceitável (skill `vertical-slice`); extrair só o que muda pelos mesmos motivos;
- contratos públicos e schema não mudam em refatoração;
- API interna substituída: migrar todos os chamadores e apagar a antiga no mesmo commit, sem alias, wrapper ou sobrecarga de compatibilidade para chamador interno (o próximo agente copia o alias que encontrar). Contrato público segue a skill `api-design`; nome persistido ou registrado (enum gravado como texto, nome de workflow ou de tarefa registrada em motor de orquestração, tipo de evento do outbox) segue `db-evolution` e a skill de workflow do projeto (Versionamento), que mantêm o antigo até drenar.

## Greenfield

Refatorar continuamente no passo REFACTOR do TDD.

## Brownfield

Respeitar convenções existentes e não reescrever fora do escopo. Problemas fora do escopo vão para `docs/gotchas.md`.

## Restrições e cuidados

Função longa, muitos argumentos, comentários e duplicação são sinais de investigação, não violações automáticas. Não alterar testes existentes para acomodar refatoração: se um teste quebra, ou a refatoração mudou comportamento ou o teste afirmava implementação (registrar como candidato de `test-audit`).

## Testes obrigatórios

Suíte relevante verde antes e depois. Sem cobertura, criar caracterização antes de mexer.

## Exceções e limites

Renomeação local trivial dispensa caracterização se o compilador garante a correção.

## Checklist de saída

- [ ] comportamento protegido por teste;
- [ ] mudanças pequenas e verificadas;
- [ ] nenhum contrato alterado;
- [ ] commit separado da mudança de comportamento.
