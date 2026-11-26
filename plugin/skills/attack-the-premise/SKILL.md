---
name: attack-the-premise
description: >
  Princípio: quando correções que partem da mesma premissa falham no mesmo gate, questione a premissa em vez de escrever
  outra correção. Carregar depois de duas tentativas que falharam no mesmo teste, build ou checagem, quando o
  iteration-guard avisar do limite de edições, e no passo de causa do playbook de bug.
---

# Ataque a premissa

## Regra

Duas correções que falham no mesmo gate pela mesma razão não pedem uma terceira variação: pedem que se ataque o que as duas assumiram. A próxima ação não é editar código, é escrever a premissa e verificá-la.

## Como aplicar

1. Escrever numa frase a suposição que as tentativas que falharam têm em comum ("o valor chega preenchido aqui", "o teste roda com a configuração de produção", "o erro vem desta chamada").
2. Procurar a evidência que a confirma ou a derruba, com o degrau mais alto disponível da escada da `review-rubric`: um teste ou script que isola a suposição, um log no ponto, a leitura do código que a decide.
3. Premissa derrubada: descartar a linha de ataque inteira, não só a última tentativa, e voltar ao diagnóstico.
4. Premissa confirmada e gate ainda vermelho: o problema está em outra suposição; repetir com a próxima. Sem próxima, registrar o que foi tentado e levar a decisão ao desenvolvedor (seção Interrupções da `lead`).

## Sinais

- A mesma mensagem de erro depois de mudanças em lugares diferentes.
- A correção funciona num caso e o gate continua vermelho no mesmo ponto.
- A explicação do erro muda a cada tentativa, sem evidência nova.
