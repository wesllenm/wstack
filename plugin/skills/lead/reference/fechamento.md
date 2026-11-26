# Fechamento: clean state, Registro e relatório

Lido pelo `lead` ao fechar a tarefa, antes do relatório final (também ao interromper, para o Registro). A linha de Registro, a escada e a stop condition ficam no núcleo; aqui estão a lista de conferência, os dois scripts que completam a linha de Registro e o formato do relatório.

Os scripts aparecem como `<plugin>/scripts/<nome>`: `<plugin>` é a pasta do plugin que o núcleo da skill dá na seção Scripts do plugin (o Read não troca variável neste arquivo). Chamar pelo caminho inteiro, como o núcleo manda.

## Clean state check

Antes do relatório final:

1. build;
2. testes relevantes;
3. tracking (`features.json`), se usado;
4. ausência de debug, scripts avulsos e saídas de teste no repositório;
5. documentação factual atualizada, com o texto passado pela skill `unslop`;
6. skills de domínio respeitadas;
7. nenhuma decisão tomada sem aprovação;
8. diff dentro do escopo;
9. nenhum teste existente removido, pulado ou enfraquecido, e nenhum snapshot ou baseline atualizado, sem autorização (`git diff` nos arquivos de teste);
10. commits atômicos e mensagens conforme a skill `commit`;
11. working tree sem mudanças esquecidas fora dos commits;
12. aprendizado promovido ou proposto, nenhuma linha de Correções do `SESSION.md` sem destino, e a tarefa tem a sua linha em Registro de `docs/review-calibration.md` (inclusive sem commit);
13. `.claude/verify-blocked.md` ausente, salvo quando a tarefa termina bloqueada;
14. limpeza comparada com o estado inicial;
15. nada que já existia removido sem pergunta;
16. todo comando de banco do diff com veredito da `query-plan`, nenhum **bloqueia** em aberto e planos brutos fora do repositório;
17. nenhuma supressão nova de analisador (`#pragma warning disable`, `[SuppressMessage]`, `NoWarn`, regra rebaixada no `.editorconfig`) sem autorização;
18. todo candidato de revisão tem veredito do `review-verifier` e todo confirmado tem destino (corrigido, recusado com motivo, não aplicável); nenhum bloqueante confirmado em aberto;
19. em código crítico com mutação configurada, nenhum mutante sobrevivente em linha do diff sem teste ou justificativa de equivalência; relatórios de mutação fora do repositório;
20. Totais de `docs/review-calibration.md` atualizados com os achados desta revisão e, na primeira tarefa da sessão, o feedback de PR lido ou registrado como não aplicável;
21. leitura de banco e integração externa do diff com teste de contagem; quando houve `quente:`, `bench-compare.sh` rodado e nenhuma linha ALOCAÇÃO, ESCALA, ORÇAMENTO, EXCEÇÃO, TAMANHO ou REMOVIDO sem correção ou justificativa no relatório; anomalias da suíte instrumentada com destino; resultados, perfis e snapshots fora do repositório;
22. em SIMPLES e COMPLEXA, o caminho pesado voltou e foi triado, ou a pendência está em `SESSION.md` (`revisão pesada pendente`); linhas `CRAP` e `DUPLICADO` do `quality-signals.sh` com destino.

## Completar a linha de Registro

Ao fechar a tarefa, rodar `node <plugin>/scripts/permission-asks.mjs <transcrição da sessão em ~/.claude/projects/<projeto>/<sessão>.jsonl> [<pasta subagents da sessão>]` e acrescentar `— pedidos: N (hooks)` ao fim da linha; pedido novo (hook que perguntou onde não devia) vira correção do mecanismo na escada, não aprovação repetida.

Na mesma hora, gravar o relatório num arquivo da pasta temporária e rodar `node <plugin>/scripts/principles.mjs <transcrição> [<pasta subagents>] --report <relatório>`. Ele lista as skills carregadas de fato (ferramenta Skill, `/comando` e pré-carga dos agentes) e as referências lidas, e sai 3 quando o relatório cita princípio ou referência sem leitura: tirar a citação, nunca ler a skill depois só para citá-la. Acrescentar `— princípios: <citadas, separadas por vírgula | nenhum> (carregadas: N)` ao fim da linha. Uma skill carregada e nunca citada, e uma citada e nunca carregada, são os dois sinais que a manutenção usa.

## Relatório

**Princípios aplicados.** O campo diz qual regra de qual skill mudou qual decisão: `skill — regra (seção ou item) — decisão que mudou (item do plano, arquivo:linha ou achado)`, um por linha. Só vale skill carregada nesta sessão (ferramenta Skill, `/comando` ou pré-carga de agente) e regra que fez o plano ou o código sair diferente do que sairia sem ela; skill carregada que não mudou nada não entra, e `nenhum` é resposta válida. O `principles.mjs` confere no fechamento (seção Aprendizado, Registro). Isso deixa o raciocínio auditável e mostra quais regras nunca mudam decisão.

```text
# Resultado

Status: implementado | verificado | bloqueado | ativo
Tipo: feature | bug | performance | refatoração | auditoria de testes | manutenção do aprendizado — playbook lido

Resumo:
Objetivo e menor mudança: as duas linhas da primeira mensagem — entregue além delas: nada | item — motivo
Arquivos alterados: caminho — mudança
Testes e verificações: comando — resultado
Testes existentes alterados: nenhum | teste — motivo — autorização
Commits: <hash curto> <título>
Agentes utilizados: agente (modelo) — finalidade — resultado
Princípios aplicados: nenhum | skill — regra (seção ou item) — decisão que mudou (item do plano, arquivo:linha ou achado)
Referências lidas: nenhuma | reference/<arquivo> | playbooks/<arquivo> (do lead) | <skill>/reference/<arquivo> (de outra skill) — momento
Performance: camada 2 (testes de contagem) — quais | camada 3: não aplicável (sem `quente:`) ou categorias — linha por benchmark (OK | NOVO | TEMPO | ALOCAÇÃO | ESCALA | ORÇAMENTO | EXCEÇÃO | TAMANHO | REMOVIDO) — destino de cada achado | pontos de melhoria do perfil de CPU: método — % do tempo — proposta — aplicado e medido | follow-up | camada 3b: não aplicável ou anomalias — destino (achado | descartada: motivo) | camada 4: não executada | pergunta — antes — depois
Camada determinística: build com analisadores, formato, arquitetura — resultado; dependências vulneráveis e segredos — resultado ou não aplicável; mutação — mutantes sobreviventes no diff: N (mortos com teste | código morto removido | equivalentes) ou não aplicável (sem ferramenta local); qualidade — `CRAP`: N (testado | dividido | preexistente, follow-up), `DUPLICADO`: N (reusado | extraído | acidental) ou não aplicável
Classificação: nível (TRIVIAL | SIMPLES | COMPLEXA | CRITICA) — motivos do classificador — subiu durante a execução: não | de X para Y
Revisões:
- caminho rápido: review-agent → review-verifier — resultado
- caminho pesado: na sessão | segundo plano (concluído | pendente em SESSION.md: `revisão pesada pendente`) | adiado por SKIP_HEAVY_REVIEW
- lentes: review-simplicity (obrigatória); review-failures, review-domain — executada ou não aplicável — motivo
- review-verifier (Opus) — candidatos: N — confirmados: N — plausíveis: N — refutados: N
- review-critical (Opus) — executado ou não — motivo
- interrogate — não configurado | não aplicável (nível) | modelo — candidatos: N — descartados na ancoragem: N — confirmados: N | falhou: motivo
- security-agent (Opus) — executado ou não aplicável
- rodadas de correção: N
Achados confirmados: id — severidade — categoria — arquivo:linha — destino (corrigido | recusado: motivo | não aplicável)
Preexistentes (follow-up): arquivo:linha — problema
Calibração: nenhuma | categoria — refutados/recusados — proposta para Não reportar de docs/review-rubric.md
Segunda opinião: não aplicável | sugestão de `/code-review ultra` antes do PR — critério do review-critical atendido
Queries (query-plan): não aplicável | comando (arquivo:método) — veredito — evidência — referência oficial
Decisões: nenhuma | aguardando aprovação
Arena: não aplicável | pergunta — propostas — escolhida — critério decisivo
Aprendizado: nenhum | falha recorrente — onde foi promovida | proposta; correções na sessão: nenhuma | fato — degrau — aplicado | proposta | recusado; linha adicionada em docs/review-calibration.md; feedback de PR: não lido | PRs #… — N comentários — escaparam: categorias — recusados: categorias; manutenção: não necessária | sugerida — motivo
Limpeza: removido / mantido (motivo) / preexistente aguardando decisão
Riscos e limitações:
Follow-ups: candidatos de test-audit e itens fora do escopo
Stop condition: [x] critério ...
🎯 Resultado final:
```

Não usar `verificado` sem evidência. `implementado` não significa `ativo` em produção.
