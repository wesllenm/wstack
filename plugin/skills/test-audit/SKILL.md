---
name: test-audit
description: >
  Carregar sempre que escrever, alterar, remover, revisar ou varrer testes.
  Gate de autoria para testes novos ou alterados, proteção do oráculo para
  testes existentes e fluxo de auditoria para testes de baixo valor, acoplados
  à implementação ou duplicados, e para seams de produção que só existem por
  causa de testes.
---

# Test Audit

## Objetivo

Garantir que cada teste justifique seu custo de manutenção protegendo comportamento, uma regressão plausível ou um contrato independente, e que a suíte continue sendo um oráculo confiável.

Dois modos, uma mesma régua de valor:

- **Modo autoria**: gate aplicado a todo teste novo ou alterado, no momento em que é escrito.
- **Modo auditoria**: varredura focada de testes que re-afirmam o código-fonte, duplicam provas mais fortes, acoplam comportamento à implementação ou mantêm vivos seams de produção criados só para teste.

Otimize por confiança, não por quantidade de testes removidos.

## Quando aplicar

- Modo autoria: sempre que `lead`, `implementer` ou `playwright-e2e` criar ou alterar teste, e sempre que `review-agent` revisar um diff que contenha testes.
- Modo auditoria: somente quando a auditoria for a própria tarefa aprovada. Durante uma feature, nunca varrer ou remover testes de forma oportunista; registrar candidatos como follow-up.

## Gate de autoria

Antes de adicionar qualquer teste, responda às cinco perguntas. Resposta faltando significa não adicionar ainda: [TST-05]

1. Qual comportamento observável, invariante ou contrato independente ele protege?
2. Qual regressão plausível o faz falhar?
3. Por que a cobertura existente ainda não pega essa falha? Prefira estender um caso parametrizado (`[Theory]`) ou uma fixture compartilhada a criar um teste quase duplicado; consolide setup duplicado na mesma mudança.
4. Ele exige um seam de produção (export, flag, wrapper, hook de injeção, visibilidade ampliada, `InternalsVisibleTo` novo) que nenhum chamador de produção precisa? Se sim, mova o teste para a fronteira real.
5. Quebrando o comportamento de propósito (valor errado, efeito pulado ou duplicado), o teste falha? O valor esperado vem do critério de aceite ou do requisito, nunca de uma chamada ao código testado nem de dados montados pelo próprio teste (oráculo circular). Sem ferramenta de mutação configurada no projeto, esta pergunta é a única checagem disso.

Teste que quebraria numa refatoração que preserva comportamento está afirmando implementação, não comportamento. Reescreva-o na fronteira dona antes de entregar.

Teste de regressão de bug precisa falhar no código anterior à correção, pelo motivo esperado, e passar depois da correção na fronteira dona. Regressão que nunca falhou de forma demonstrada prova o mock, não a correção. Registre a execução que falhou como evidência. [TST-04]

Quando o projeto tiver portão de rastreabilidade, todo teste de aceitação referencia o critério de aceite que cobre, e teste sem critério é sinalizado. [TST-01]

## Proteção do oráculo

Os testes existentes são a especificação contra a qual a mudança é julgada. O agente que altera a implementação não pode, na mesma mudança, redefinir silenciosamente o que é correto. [TST-02]

Sem autorização explícita no plano ou no sprint contract, e sem a evidência de candidato descrita abaixo, não:

- remover teste;
- marcar teste como skip (`Skip =`), ignore, pending ou quarentena;
- enfraquecer asserção (trocar igualdade por "contém", deixar de verificar campos, ampliar tolerância);
- atualizar snapshot (Verify `.verified.*`), golden file ou baseline para fazer passar;
- alterar teste E2E, de contrato ou de arquitetura (NetArchTest) para acomodar o novo comportamento;
- aplicar label, flag ou exceção que desative um check de CI (inclusive limiar do Stryker). [GIT-07]

Se um teste existente falhar após a mudança, a hipótese padrão é regressão na implementação, não teste errado. Mudança intencional de comportamento que exige alterar teste existente é decisão de escopo e precisa constar do plano aprovado.

## Régua de valor

Um teste justifica seu custo protegendo comportamento, regressão plausível ou contrato com significado independente. Teste que precisa mudar numa reorganização de código que preserva comportamento é suspeito, mas não automaticamente removível.

Antes de julgar um candidato, leia o teste completo e o código de produção dono, o ponto de entrada, chamadores, chamados, implementações irmãs, testes sobrepostos, o roteamento de CI e o histórico relevante (`git log`, `git blame`). Leia `CLAUDE.md` e as regras escopadas primeiro. Quando o teste afirma comportamento de uma dependência, inspecione o código ou os tipos da dependência diretamente.

## Descoberta (modo auditoria)

Descoberta é somente leitura, e a evidência é reportada antes de qualquer edição. Para escopo amplo, dispare `explore` em paralelo, uma trilha por área, por exemplo:

- domínio e orquestração (agregados, workflows);
- integrações e adaptadores;
- frontend, scripts e tooling;
- varredura transversal de padrões.

Prefira poucos candidatos de alta confiança a um inventário especulativo grande. Procure:

- testes sem asserção, que só executam código para gerar cobertura;
- auto-comparações e cópias de identidade (valor comparado com ele mesmo);
- fixtures, inventários, manifestos ou listas de export copiados do código;
- greps exatos de código-fonte, import ou string;
- testes de predicado privado ou formato de chamada já cobertos na fronteira real;
- invocações duplicadas do mesmo contrato;
- repetições locais de helpers compartilhados;
- testes cujo único propósito é preservar exports, globais ou wrappers só de teste;
- código de produção morto cujos únicos chamadores são testes.

## Régua de retenção

Mantenha o teste quando ele impõe de forma independente um contrato de API pública, SDK, protocolo, configuração, migration, armazenamento, segurança, plataforma, valor default, formato serializado (ex.: JSON Schema), contrato entre serviços ou linguagens, pacote, release ou arquitetura. Mantenha também:

- ordem de chamadas, quando a ordem é comportamento observável;
- regressões com modo de falha plausível;
- inspeção de código-fonte, quando for a guarda independente mais barata.

Ser estático ou lento não é motivo de remoção. Um teste parecido com a implementação ainda pode ser o contrato independente; prove o contrário antes de remover.

## Evidência do candidato

Registre todos os campos antes de editar. Campo faltando significa candidato não pronto para remoção:

- nome exato e localização do teste;
- qual falha ele realmente consegue detectar;
- chamadores fora de teste do seam de produção ou de suporte coberto;
- prova mais forte que permanece na fronteira dona, ou por que não é necessária;
- histórico relevante e motivo de o teste ou seam existir;
- remoção de produção ou de suporte de teste que isso destrava;
- risco e comando focado de validação.

## Forma da edição

Escolha um lote coerente por fronteira dona. Remova exports, globais, wrappers e caminhos de produção mortos que só existiam para teste, em vez de preservar aliases. Mova regressões retidas para seus donos canônicos. Consolide asserções repetidas de pacote ou dependência em um único contrato genérico.

Prefira saldo negativo de linhas de produção. Não adicione testes substitutos que re-afirmam a mesma implementação, e não converta candidatos incertos em limpeza para aumentar a contagem de remoções.

## Validação

Não editar código ou testes enquanto a suíte estiver rodando no mesmo checkout, inclusive em watch mode.

1. Rode os menores testes do dono e dos irmãos: `dotnet test <projeto> --filter "FullyQualifiedName~<Dono>"`.
2. Para greps de código ou asserções de plano removidos, rode o script, build ou dry-run que é dono do contrato real.
3. Rode `dotnet format --verify-no-changes` focado e `git diff --check`.
4. Rode o gate de mudanças do projeto (build, testes relevantes, lint).
5. Inspecione `git diff --numstat` e reporte produção e tooling separados de testes e suporte de teste.
6. Após as edições finais, a revisão da skill `lead` (seção Revisão) é obrigatória; remoção de teste de contrato, segurança ou arquitetura aciona `review-critical`.

## Entrega e continuação

Commits pela skill `commit`, um lote coerente por commit. Push e PR somente se autorizados. Depois de entregar um lote, atualize a partir da branch principal e refaça a descoberta somente leitura para o próximo lote de alta confiança.

## Mutação

Cobertura mostra que a linha rodou; mutação mostra se algum teste falharia se a linha estivesse errada. É a evidência objetiva para o gate de autoria em código crítico.

Quando rodar:

- o projeto tem ferramenta de mutação configurada (ex.: Stryker.NET, StrykerJS);
- o diff toca código coberto pelos critérios do `review-critical` (os globs `critical` do `.claude/risk.conf`, por exemplo autenticação, autorização, segredos, dados pessoais, migrations, contratos públicos) ou regra de domínio do agregado;
- no modo auditoria, sobre a fronteira dona do lote, para provar que um teste candidato não mata nenhum mutante que os outros não matem.

Como rodar:

- sempre incremental, só sobre o que mudou em relação à branch base (Stryker.NET tem a opção `since`); confirmar a sintaxe da versão instalada com `--help`;
- limitar `mutate` aos arquivos de produção do diff e excluir migrations e código gerado;
- relatórios na pasta temporária da sessão (`--output`), nunca no repositório (`StrykerOutput/` conta como saída criada por você).

Como ler:

- não existe meta de score; o que importa é cada mutante sobrevivente numa linha alterada pelo diff;
- mutante sobrevivente em linha do diff vira candidato de revisão na categoria `tests`, com severidade importante, e é enviado às lentes;
- mutante sem cobertura (`NoCoverage`) em linha do diff é tratado igual ao sobrevivente, com uma pergunta antes: algum chamador de produção alcança essa linha? Se sim, falta teste; se não, é código morto e a correção é removê-lo, não testá-lo;
- mutante equivalente (a mudança não altera comportamento observável) é descartado com justificativa de uma linha;
- matar mutante com asserção que só re-afirma a implementação não vale: o teste novo passa pelas cinco perguntas do gate de autoria.

Se a mutação incremental passar de alguns minutos, restringir o escopo aos arquivos críticos e registrar a decisão em `docs/decisions.md`. Adicionar a ferramenta ao projeto é mudança de dependência e exige aprovação. Sem ferramenta local, o relatório registra `mutação — não aplicável`.

## Greenfield

Aplicar o gate de autoria desde o primeiro teste; a suíte nasce sem testes de baixo valor.

## Brownfield

Em legado sem testes, caracterização vale mais que pureza: um teste acoplado à implementação pode ser a única rede enquanto a fronteira real não é testável. Não auditar a suíte legada sem tarefa aprovada.

## Exceções e limites

- Testes de caracterização temporários podem ser acoplados à implementação, desde que marcados como tal e com follow-up para migrá-los à fronteira real.
- Nada nesta skill autoriza remover testes fora do escopo aprovado.

## Checklist de saída

Modo autoria:

- [ ] as cinco perguntas respondidas para cada teste novo;
- [ ] nenhum seam de produção criado só para teste;
- [ ] regressão de bug falhou antes da correção (evidência) e passa depois;
- [ ] nenhum teste existente removido, pulado ou enfraquecido, e nenhum snapshot ou baseline atualizado, sem autorização;
- [ ] em código crítico com mutação configurada: nenhum mutante sobrevivente ou sem cobertura em linha do diff sem teste novo, remoção de código morto ou justificativa de equivalência.

Modo auditoria (handoff):

- causa raiz e categorias de baixo valor removidas;
- simplificações de produção destravadas;
- falsos positivos mantidos e por que continuam valiosos;
- provas focadas e completas efetivamente executadas;
- linhas de produção versus linhas de teste;
- commits e estado de PR;
- follow-ups nomeados.
