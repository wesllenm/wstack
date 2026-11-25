# Arquitetura

O que o código não mostra de uma vez: as fronteiras, o caminho de uma requisição e as regras que valem em todo lugar.
Mapa de pastas e lista de stack o agente descobre sozinho; não repetir aqui.

## Estrutura

<slices por feature (skill vertical-slice do wstack) | estrutura existente do projeto, descrita em poucas linhas>

## Fronteiras e dependências

- <módulo ou serviço> depende de <...>; nunca o contrário.

## Persistência e integrações

- <banco, ORM, filas, serviços externos e como são acessados>

## Observabilidade

<padrão detectado (biblioteca de log, traces, métricas, destino) | a definir>

## Regras verificáveis

- <regra de arquitetura e onde ela é verificada: teste de arquitetura, analisador, revisão>
