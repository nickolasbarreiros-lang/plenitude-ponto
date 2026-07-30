# Plenitude Ponto 1.0.0 RC3

## Validação automática da homologação

- Novo botão **Validar automaticamente**.
- O Supabase verifica automaticamente os itens que podem ser comprovados por dados.
- São analisados:
  - diagnóstico técnico;
  - funcionário 999, PIN, acesso e dispositivo;
  - marcações e ordem da jornada;
  - jornada concluída e limite de quatro marcações;
  - movimentações temporárias;
  - ajustes pendentes, aprovados e rejeitados;
  - marcação gerada por ajuste;
  - auditoria;
  - estruturas de banco de horas e backup;
  - fechamento e reabertura de competência.
- Testes visuais, de impressão, F5, duas abas, internet e experiência continuam manuais.
- Cada validação automática grava data, resultado e detalhe no campo de observação.
