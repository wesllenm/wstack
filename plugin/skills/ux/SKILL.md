---
name: ux
description: >
  Orienta jornadas, feedback, confirmação de ações destrutivas, mensagens
  de erro, estados vazios e de carregamento, prevenção e recuperação de
  erros nas telas afetadas do portal.
---

# UX

## Objetivo

O usuário sempre sabe o que está acontecendo, o que fazer em seguida e como se recuperar de um erro.

## Quando aplicar

Tela nova ou alterada do portal, fluxo de formulário (nova demanda, upload), fila de aprovações, ação destrutiva, mensagem de erro, estado vazio. Só nas jornadas dentro do escopo; não redesenhar o produto.

## Princípios

- O aprovador decide em minutos: artefato resumido primeiro, detalhe e diff sob demanda.
- Estado da demanda e do estágio sempre visível e atualizado em tempo real (SignalR), com indicação quando a conexão cair.

## Padrões

### Ações destrutivas e decisões de portão

Excluir, cancelar demanda, rejeitar em portão, remover vínculo, desativar ou qualquer ação com perda de dados ou efeito irreversível sempre pede confirmação explícita antes de executar: [UX-01]

- o diálogo nomeia o objeto afetado e a consequência ("Cancelar a demanda DEM-1234? Os PRs abertos serão fechados.");
- o botão de confirmação usa o verbo da ação ("Cancelar demanda"), nunca "OK" ou "Sim";
- a ação padrão do diálogo (Enter, foco inicial) é cancelar;
- ação em massa informa a quantidade afetada.

Aprovação em portão não é destrutiva, mas registra autoria: mostrar quem está aprovando e o que exatamente (versão do artefato).

### Feedback

- Toda ação tem resposta visível: carregando, sucesso ou erro. [UX-02]
- Botão de envio desabilitado durante o processamento, para evitar envio duplo. [UX-02]
- Estados de carregamento, vazio e erro definidos para cada lista ou painel. [UX-03]

### Mensagens de erro

- Dizem o que aconteceu e o que fazer, na linguagem do usuário. [UX-04]
- Erro de campo aparece junto do campo; erro geral aparece no topo do formulário.
- Nunca mostrar mensagem técnica, código de exceção ou stack trace (mapear o `code` do Problem Details para texto). [UX-04]
- Preservar o que o usuário digitou quando o envio falhar. [UX-04]

### Prevenção

Validar enquanto o usuário preenche quando a regra for conhecida no cliente; o servidor valida sempre de novo.

## Greenfield

Definir os componentes de diálogo de confirmação, toast e estado vazio uma vez e reutilizá-los.

## Brownfield

Seguir os componentes e padrões visuais existentes. Não redesenhar telas fora do escopo.

## Restrições e cuidados

O idioma da interface é definido por sistema; no portal do SquadOS é português brasileiro. [UX-05]

## Testes obrigatórios

Diálogo de confirmação coberto em teste de componente nas ações destrutivas novas. [UX-01]

## Exceções e limites

Telas internas de diagnóstico podem ter UX mínima.

## Checklist de saída

- [ ] ações destrutivas com confirmação que nomeia objeto e consequência;
- [ ] feedback de carregamento, sucesso e erro;
- [ ] estados vazio e de erro definidos;
- [ ] mensagens acionáveis e sem detalhe técnico;
- [ ] dados do formulário preservados em caso de falha.
