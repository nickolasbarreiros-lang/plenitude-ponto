# Banco de dados — Plenitude Ponto

A partir desta versão, instalações novas devem usar somente:

`supabase-baseline-plenitude-ponto-v1.0.sql`

Os arquivos antigos foram movidos para `sql-historico/` apenas como documentação
da evolução do sistema. Eles NÃO devem ser executados em uma instalação nova.

O baseline é destinado a banco Supabase vazio. O banco de produção atual não
deve receber o baseline; nele devem ser aplicadas somente novas migrações
criadas após a baseline.

Após uma instalação nova, execute
`supabase-baseline-validacao-v1.0.sql` para conferência.
