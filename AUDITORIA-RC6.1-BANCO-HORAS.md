# RC6.1 — Banco de horas acumulado

## Nova regra

O sistema passa a separar:

- **Saldo da competência:** resultado somente do mês selecionado.
- **Banco acumulado:** saldo das competências fechadas anteriores + saldo da competência atual.

## Fechamento

Ao fechar um mês, o saldo de cada funcionário é congelado em
`banco_horas_competencias`.

Esse snapshot é histórico e não altera as marcações originais.

## Reabertura

Ao reabrir uma competência, o snapshot daquele mês é removido. Após os ajustes,
um novo fechamento recalcula e grava o saldo atualizado.

## Migração de meses já fechados

O próprio SQL RC6.1 reconstrói automaticamente os snapshots de todas as
competências que já estiverem com status `fechado`.

Portanto, basta executar o arquivo SQL uma única vez. Não é necessário
reabrir e fechar meses antigos manualmente.
