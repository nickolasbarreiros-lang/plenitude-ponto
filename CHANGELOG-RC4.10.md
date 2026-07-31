# Plenitude Ponto 1.0.0 RC4.10

## Backup seguro

- A página Backup não consulta mais diretamente tabelas protegidas por RLS.
- Criada a RPC administrativa `exportar_backup_admin`.
- Funcionários, jornadas, marcações, ocorrências, ajustes e auditoria são exportados com escopo da empresa.
- O período continua sendo aplicado às informações mensais.
- Corrigido o erro 403 ao consultar `solicitacoes_ajuste`.
