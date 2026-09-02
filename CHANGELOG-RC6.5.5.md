# Plenitude Ponto RC6.5.5

- Fechamento mensal passa a identificar nominalmente cada jornada incompleta.
- Exibe funcionário, matrícula, data, quantidade de marcações e marcação faltante.
- O botão geral deixa de enviar toda pendência para Ajustes e passa a respeitar o tipo real do bloqueio.
- Cada jornada incompleta possui botão Regularizar.
- Regularizar abre o ponto do funcionário correto com data e tipo da marcação ausente pré-selecionados.
- Funcionários operacionais inativos não geram bloqueio fantasma no fechamento.
- Banco atual: executar `supabase-rc6-5-5-detalha-jornadas-fechamento.sql`.
- Instalações novas: baseline `supabase-baseline-plenitude-ponto-v1.4-rc6.5.5.sql`.
