# Mudança mecânica em lote

Lido pelo `lead` quando a mesma transformação for se repetir em uns dez arquivos ou mais, ou não for óbvia de olhar.

Quando a mesma transformação se repete em muitos arquivos (renomear símbolo que o IDE não renomeia, migrar chamadas de uma API, trocar padrão de log, ajustar assinatura em dezenas de controllers ou testes), construa a alavanca em vez de editar um a um:

1. faça uma unidade à mão, verifique com build e testes e guarde o resultado como oráculo;
2. escreva o script ou codemod na pasta temporária da sessão, nunca no repositório (`sed`/`awk` para casos textuais simples; Roslyn, `ts-morph` ou `ast-grep` quando a mudança depende da estrutura do código);
3. rode o script sobre a versão original da unidade feita à mão (`git stash` ou cópia) e confira que o resultado é idêntico ao oráculo; divergência significa script errado, não exceção a tratar à mão;
4. aplique no restante, revise o `git diff --stat` e uma amostra do diff, rode build e testes e commite como uma unidade.

É o princípio da skill `build-the-lever`: carregá-la antes do passo 1. Prefira o script determinístico a dividir a mesma transformação entre vários subagentes, que decidem os casos de borda cada um do seu jeito.

A regra vale a partir de uns dez arquivos ou quando a transformação não é óbvia de olhar; abaixo disso, editar direto custa menos. Edições feitas por script passam por `Bash` e não contam no `iteration-guard.sh`; o commit por unidade continua valendo. Mudança em teste existente por script continua exigindo a autorização do sprint contract.
