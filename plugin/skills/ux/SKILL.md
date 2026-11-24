---
name: ux
description: >
  Orienta jornadas, feedback, confirmação de ações destrutivas, mensagens
  de erro, estados vazios e de carregamento, prevenção e recuperação de
  erros nas telas afetadas.
---

# UX

## Objetivo

O usuário sempre sabe o que está acontecendo, o que fazer em seguida e como se recuperar de um erro.

## Quando aplicar

Tela nova ou alterada, fluxo de formulário (cadastro, upload), ação destrutiva, mensagem de erro, estado vazio. Só nas jornadas dentro do escopo; não redesenhar o produto.

## Princípios

- Estado de processo em andamento sempre visível e, quando atualizado em tempo real, com indicação de quando a conexão cair.

## Padrões

### Ações destrutivas

Excluir, cancelar, remover vínculo, desativar ou qualquer ação com perda de dados ou efeito irreversível sempre pede confirmação explícita antes de executar:

- o diálogo nomeia o objeto afetado e a consequência ("Excluir o pedido 1234? Os itens e o histórico serão removidos.");
- o botão de confirmação usa o verbo da ação ("Excluir pedido"), nunca "OK" ou "Sim";
- a ação padrão do diálogo (Enter, foco inicial) é cancelar;
- ação em massa informa a quantidade afetada.

Decisão que registra autoria (aprovar, rejeitar) não é destrutiva, mas mostra quem está decidindo e o que exatamente (versão do item).

### Feedback

- Toda ação tem resposta visível: carregando, sucesso ou erro.
- Botão de envio desabilitado durante o processamento, para evitar envio duplo.
- Estados de carregamento, vazio e erro definidos para cada lista ou painel.

### Mensagens de erro

- Dizem o que aconteceu e o que fazer, na linguagem do usuário.
- Erro de campo aparece junto do campo; erro geral aparece no topo do formulário.
- Nunca mostrar mensagem técnica, código de exceção ou stack trace (mapear o código de erro da API para texto).
- Preservar o que o usuário digitou quando o envio falhar.

### Prevenção

Validar enquanto o usuário preenche quando a regra for conhecida no cliente; o servidor valida sempre de novo.

## Greenfield

Definir os componentes de diálogo de confirmação, toast e estado vazio uma vez e reutilizá-los.

## Brownfield

Seguir os componentes e padrões visuais existentes. Não redesenhar telas fora do escopo.

## Restrições e cuidados

O idioma da interface é definido por sistema.

## Testes obrigatórios

Diálogo de confirmação coberto em teste de componente nas ações destrutivas novas.

## Exceções e limites

Telas internas de diagnóstico podem ter UX mínima.

## Checklist de saída

- [ ] ações destrutivas com confirmação que nomeia objeto e consequência;
- [ ] feedback de carregamento, sucesso e erro;
- [ ] estados vazio e de erro definidos;
- [ ] mensagens acionáveis e sem detalhe técnico;
- [ ] dados do formulário preservados em caso de falha.
