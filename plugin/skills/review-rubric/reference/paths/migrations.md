# Review por caminho — migrations escritas à mão (EF Core / PostgreSQL)

Aplicar quando o grupo tocar `**/Migrations/*.cs`. Complementa o "Sempre verificar" da `SKILL.md`; o veredito sobre índice e plano é do `database-reviewer`, não da lente.

- primeira operação do `Up` e do `Down` é `SET LOCAL lock_timeout`; sem ele o `ALTER` espera na fila e bloqueia as escritas atrás de si;
- `Down` recusa rodar (`restrict_violation`) quando há dado que o `Down` apagaria; evidência imutável (ex.: `audit_events`) nunca é apagada em silêncio;
- coluna nova em tabela existente: `NOT NULL` só com default constante (só metadado no PG 18); coluna `NOT NULL` sem default em tabela com linhas falha ou reescreve a tabela;
- tabela só-inserção tem trigger: `UPDATE` de backfill exige desligar e religar o trigger (`ALTER TABLE ... DISABLE TRIGGER`); `UPDATE` que passa despercebido por um trigger de imutabilidade falha em produção;
- `CREATE INDEX` na transação toma `SHARE` e `DROP INDEX` toma `ACCESS EXCLUSIVE`; em tabela grande, `CREATE INDEX CONCURRENTLY` em migration própria com `suppressTransaction`, guarda contra índice `INVALID` e `lock_timeout` de sessão;
- o EF 9+ aplica o lote de migrations numa só transação: `SET LOCAL` e o `SHARE` valem até o `COMMIT` do lote inteiro;
- índice parcial: o predicado do `WHERE` precisa ser literal na consulta que deve usá-lo; conferir que o `HasIndex` tem nome explícito e `HasDatabaseName` (o EF funde `HasIndex` sobre as mesmas colunas);
- enum gravado como texto sem `CHECK`: renomear membro exige migration de dados; valor novo precisa de default compatível com o binário anterior (rollback é voltar o binário, antes do `Down`);
- compatibilidade N-1: o binário anterior ainda funciona com o schema novo; migrations antes do código;
- `snapshot` do modelo coerente com a migration (`dotnet ef migrations has-pending-model-changes` limpo); migration já aplicada em ambiente compartilhado nunca é editada.

Não é achado: o código gerado do `*.Designer.cs` e do `*ModelSnapshot.cs`; estilo do código da migration (a pasta é `generated_code = true`).
