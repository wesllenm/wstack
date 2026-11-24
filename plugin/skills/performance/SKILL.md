---
name: performance
description: >
  Medição de performance em camadas, em qualquer stack: regras estáticas,
  contagem de comandos de banco, chamadas externas, requisições e renders nos testes,
  benchmark base contra diff com escala, orçamento e perfil de CPU em caminho
  quente, suíte instrumentada e profiling sob demanda; inclui custo de tokens
  das chamadas de modelo. Carregar ao escrever acesso a dados, chamada externa,
  componente de frontend com lista, código em caminho quente, ou ao investigar latência, memória, CPU, tamanho
  de bundle ou custo de tokens.
---

# Performance

## Objetivo

Pegar regressão de performance com evidência medida, no ponto mais barato possível, e nunca otimizar sem número antes e depois. [PRF-01]

## Referências

Ferramentas, exemplos e comandos da stack em `reference/<stack>.md` nesta pasta: `dotnet.md` (backend .NET), `node.md` (JavaScript e TypeScript: servidor, build e scripts Node), `web-frontend.md` (frontend web, com exemplos em Svelte 5/SvelteKit) e `bash.md` (scripts de CI e hooks). Ler a referência da stack do arquivo alterado antes de escrever teste ou benchmark.

## Quando aplicar

- Camada 1: sempre (está no build ou no lint).
- Camada 2: todo diff que cria ou altera leitura de banco, laço sobre dados persistidos, chamada a integração externa, ou tela do frontend que renderiza lista ou faz requisições.
- Camada 3: quando o `classify-diff.sh` devolver linha `quente:`, inclusive em código novo.
- Camada 3b: no caminho pesado de COMPLEXA e CRITICA, quando houver o coletor da stack.
- Camada 4: quando houver um problema para investigar, pedido pelo desenvolvedor ou apontado pelas camadas 3 e 3b.
- Custo de tokens: sempre que o diff mexer em prompt, contexto ou escolha de modelo de uma chamada de modelo de IA do produto.

## Princípios

- O que é estável entre execuções pode virar achado (alocação contada, quantidade de comandos, renders, bytes de bundle); o que oscila só informa (tempo medido na máquina local).
- Comparar a operação com ela mesma em dois volumes é mais robusto que fixar um número: pega N+1 e crescimento quadrático sem depender de versão anterior.
- O plano de execução diz se uma query é boa; a contagem diz quantas vezes ela roda. Acesso a banco passa sempre pela skill `query-plan`.
- Profiling sem pergunta gera dado e não decisão.
- Não adicionar cache, paralelismo, memoização ou índice sem explicar custo, consistência, invalidação e medição antes e depois. [PRF-02]
- Em chamadas de modelo, o maior custo costuma ser contexto: medir tokens (registro de execuções e métricas `gen_ai.*` do projeto) antes de otimizar código; cache de contexto e modelo menor por etapa são as alavancas usuais.

## Camada 1 — regras estáticas

Regras de performance do analisador da stack como erro (build com avisos tratados como erro; as regras de cada stack estão na referência dela). Pegam no build, sem revisão.

## Camada 2 — contagem nos testes

- **Comandos de banco**: o teste de integração mede quantos comandos a operação dispara com poucos e com muitos itens, e afirma que o número não cresce. Fixar o número exato quebra quando alguém adiciona uma query legítima. [PRF-04]
- **Chamadas externas**: mesmo raciocínio para integração HTTP, e retry não multiplica chamadas além do configurado.
- **Frontend**: quantidade de requisições por página ou interação (teste E2E) e, onde a stack mede, quantidade de renders por componente com lista (teste de componente) não crescem com os itens; nenhuma requisição duplicada.
- **Alocação**: onde a stack conta alocação de forma confiável (referência da stack), o teste afirma que ela não cresce com o volume.

## Camada 3 — benchmark comparativo, escala e perfil de CPU

Cada categoria `hot` do `risk.conf` tem benchmark e uma linha `bench` com o comando da stack (`.claude/risk.conf`). Onde o custo depende do volume, o benchmark roda com pelo menos dois tamanhos de entrada, distantes entre si (coluna `size`).

Quando o diff toca uma categoria quente, rodar `${CLAUDE_PLUGIN_ROOT}/scripts/bench-compare.sh <categorias>`. O que vira achado:

**Base contra diff** (precisa de versão anterior):

- **ALOCAÇÃO**: mais de 5% e mais de 32 bytes por operação a mais que a base. Importante.
- **TAMANHO**: bundle mais de 5% e mais de 2 KB maior que a base. Importante.
- **REMOVIDO**: benchmark que existia na base e sumiu. Achado, como teste removido.
- **TEMPO**: variação acima de 10%. Informativo, nunca bloqueia.

**Sem depender de base** (vale para código novo desde o primeiro commit):

- **ESCALA**: entre o menor e o maior tamanho, tempo ou alocação crescem mais que o dobro do crescimento da entrada. Entrada x100 com custo x90 é linear e passa; custo x9.000 é quadrático. Importante.
- **ORÇAMENTO**: alocação ou bundle acima do `budget` declarado. Usar só onde há número de referência (a meta do cliente, [PRF-03]). Orçamento de tempo não existe, porque tempo absoluto muda de máquina para máquina.
- **EXCEÇÃO**: exceções por operação, novas ou em maior número que na base (onde a stack mede).
- **NOVO**: medição sem base; vira a base da próxima mudança.

**Perfil de CPU**: lista, por categoria, os métodos com mais tempo exclusivo (onde o trabalho acontece) e inclusivo (o que custa contando o que chama). Gera hipótese de melhoria, não achado: uma melhoria só entra se a mudança medir melhor no `bench-compare` seguinte.

Destino:

- ALOCAÇÃO, TAMANHO, ESCALA, ORÇAMENTO e EXCEÇÃO: corrigir, ou justificar em uma linha no relatório quando é consequência esperada da feature. A justificativa é decisão do desenvolvedor no relatório, não do agente.
- REMOVIDO: só com autorização no plano, como teste removido.
- Perfil de CPU: o `lead` envia ao `performance-agent` quando houver achado acima sem causa óbvia no diff, ou quando um método do próprio projeto aparecer no top 5 exclusivo com mais de 20% do tempo. Os pontos de melhoria vão para o relatório e só são aplicados se estiverem no escopo e medirem melhor.

Caminho quente tocado sem benchmark (`SEM BENCHMARK` na saída): criar o benchmark na mesma tarefa quando o plano previr; senão, follow-up. Benchmark novo passa pelo gate de autoria da `test-audit`.

Roda no caminho pesado da revisão (skill `lead`, Duas velocidades), nunca no rápido.

## Camada 3b — suíte instrumentada

Uma rodada da suíte de integração com o coletor de runtime da stack (em .NET, `PerfSnapshot` na suíte de integração, inerte sem `PERF_SNAPSHOT_OUT`; ver a referência da stack). Não mede velocidade (teste roda com pouco dado e aquecimento frio), mas pega anomalias que nenhum teste afirma:

| Sinal | Onde a stack mede | Causa provável |
|---|---|---|
| Runtime sem conseguir atender trabalho | .NET: fila do thread pool cheia por mais de 1 s; Node: atraso do event loop p99 acima de 50 ms | trabalho síncrono bloqueante no caminho assíncrono |
| Exceções em volume | .NET: tipo do projeto ou de I/O com centenas de ocorrências; Node: exceções não tratadas | exceção como fluxo de controle, ou erro engolido em laço |
| GC pesado | coletas de geração alta em relação às de geração baixa; tempo de GC alto | objetos grandes ou retidos tempo demais |
| Contenção | contagem de contenção de lock alta | lock disputado em código compartilhado |
| Crescimento | alocação total e CPU muito acima da rodada anterior na mesma máquina | regressão a investigar; só informativo |

Ignorar o que os próprios testes provocam de propósito. Anomalia não é achado sozinha: vai ao `performance-agent`, que localiza a causa com a camada 4 e devolve achado com trecho e número, ou descarta.

## Camada 4 — profiling sob demanda

1. Escrever a pergunta: "por que `GET /v1/orders/summary` leva 6 s com 50 mil pedidos?".
2. Reproduzir com carga controlada: teste de integração em laço, script de requisições ou o seed escalado do ambiente local.
3. Medir baseline com a ferramenta de contadores da stack; aprofundar com perfil de CPU ou de memória só na direção que os contadores indicarem.
4. Formular hipótese com o trecho de código e o número que a sustenta.
5. Aplicar a menor mudança e medir de novo, com a mesma carga.
6. Reportar antes e depois. Coletas brutas ficam na pasta temporária da sessão.

Conferir a sintaxe das ferramentas com `--help` na versão instalada.

## Antes de reportar um número

Vale para todo tempo, vazão ou percentual medido à mão: o antes e depois de uma mudança, uma regressão alegada, a escolha entre duas bibliotecas. As linhas do `bench-compare.sh` já passam por parte disso; o resto é do `lead` ou do `performance-agent`.

Antes de rodar, escrever a frase que se pretende afirmar ("a exportação ficou 30% mais rápida no p50 com 60 mil linhas"). As perguntas testam essa frase:

1. **Por que não o dobro?** Nomear o recurso que limita o resultado (um núcleo, um lock, o disco, a rede, o próprio gerador de carga), tirado de perfil ou contador, não de leitura do código.
2. **Os dois lados rodaram como em produção?** Build Release, mesmas flags, pool de conexões, cache no estado que a produção vê, mesmos dados.
3. **Passa de algum limite físico?** Fazer a conta: bytes por segundo contra a banda do disco ou da rede, operações por segundo contra os núcleos. Remover um trecho que pesa 10% da execução deixa a execução no máximo uns 11% mais rápida.
4. **Houve erro?** Contar falhas e respostas não bem-sucedidas, e conferir que a saída está certa. Rejeição costuma ser rápida.
5. **Repete?** Pelo menos cinco execuções por lado, intercaladas, com mediana e intervalo. Diferença menor que a variação entre execuções não é diferença.
6. **Importa?** Medir também o caminho que o usuário espera, com dados e concorrência realistas, e dar o resultado micro como fração do total.
7. **O trabalho aconteceu?** Conferir que a requisição chegou, as linhas foram gravadas, o resultado foi usado. Código adiado (`IEnumerable` não enumerado, promise sem `await`) produz número para trabalho que não existiu.

O veredito é mais rápido, mais lento, sem diferença mensurável ou inconclusivo; inconclusivo quando não há limitador nomeado, quando um lado rodou sem configuração de produção ou quando as perguntas 4 e 7 não foram respondidas, dizendo qual lacuna.

## Greenfield

Camadas 1 e 2 e o coletor da camada 3b desde o primeiro endpoint; benchmark criado quando o primeiro caminho `hot` for declarado. Registrar metas de latência e de volume em `.claude/project.md` quando o produto as definir.

## Brownfield

- Camada 1 com baseline de avisos, sem corrigir legado de forma oportunista.
- Contagem nos testes novos e nos alterados; não escrever para código antigo fora do escopo.
- Primeiro caminho `hot` declarado sem benchmark: criar o benchmark da base numa tarefa própria, antes, para haver contra o que comparar.

## Restrições e cuidados

- Não comparar tempo entre máquinas diferentes, nem entre execuções em momentos diferentes.
- Não rodar benchmark ou profiling contra produção, nem com dado pessoal real.
- Benchmark sempre em build de release; saídas na pasta temporária da sessão.
- Forçar coleta de lixo em código de produção para "melhorar" memória é achado, não correção.

## Testes obrigatórios

- Leitura nova ou alterada de banco: contagem de comandos.
- Integração externa nova ou alterada: contagem de chamadas.
- Componente ou tela com lista: contagem de requisições e, onde a stack mede, de renders.
- Caminho quente: benchmark da categoria, com dois tamanhos onde o custo depende do volume.

## Exceções e limites

- Ajuste óbvio sem custo (ex.: `AsNoTracking` em leitura) dispensa benchmark, mas não a `query-plan`. [PRF-01]
- Script, ferramenta interna e job raro sem SLA dispensam as camadas 2 e 3, com o motivo no plano.
- Esta skill não define SLA: o SLA vem do produto e fica em `.claude/project.md`.

## Checklist de saída

- [ ] build e lint sem aviso novo de performance;
- [ ] contagem de comandos, chamadas, requisições e renders onde o diff pede;
- [ ] `bench-compare.sh` rodado quando houve `quente:`, sem ALOCAÇÃO, TAMANHO, ESCALA, ORÇAMENTO, EXCEÇÃO ou REMOVIDO sem correção ou justificativa;
- [ ] pontos de melhoria do perfil de CPU no relatório, aplicados só se no escopo e medidos;
- [ ] em COMPLEXA e CRITICA com coletor: anomalias investigadas ou descartadas com motivo;
- [ ] toda otimização com número antes e depois;
- [ ] todo número medido à mão passou por Antes de reportar um número, com limitador nomeado, execuções e intervalo;
- [ ] custo e consistência explicados quando houver cache, paralelismo ou índice;
- [ ] coletas e resultados fora do repositório.
