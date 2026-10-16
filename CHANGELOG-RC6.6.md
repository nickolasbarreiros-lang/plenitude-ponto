# RC6.6 — Jornadas nomeadas

## Instalação
1. Backup do Supabase.
2. Execute `supabase-rc6-6-jornadas-nomeadas.sql` no SQL Editor.
3. Publique os arquivos do site e recarregue.
4. Em **Jornada**, crie um modelo com horários dos sete dias e salve.
5. Escolha o funcionário e atribua o modelo; alternativamente, selecione-o em **Funcionário**.

## Limites de segurança
- Atribuição apenas com vigência no dia atual; não agenda mudanças futuras.
- O modelo é imutável depois de atribuído; crie um novo modelo para alterar horários.
- A atribuição atualiza `public.jornadas`, que continua sendo a fonte dos cálculos legados.
- **O motor histórico de apuração ainda não consulta as versões das jornadas**: mudar a jornada de funcionário com histórico pode alterar recálculos de períodos anteriores. Antes de atribuir a quem já tem marcações, valide fechamento/espelhos e faça backup.
- Os vínculos são registrados em `atribuicoes_modelo_jornada`, mas não substituem uma migração futura do cálculo por vigência.
- Não altera automaticamente o campo `carga_semanal_minutos` de funcionários.
- SQL-base consolidado deve ser atualizado após homologação.

## Testes
- Criar dois modelos com jornadas distintas.
- Vincular modelo à Tallia; conferir 7 dias em `public.jornadas`.
- Conferir o banco de horas do mês e períodos anteriores.
- Verificar acesso administrativo e RLS.
