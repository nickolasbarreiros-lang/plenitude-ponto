# RC5.76 — erro 400 no banco de horas

## Causa encontrada

A função `_calcular_banco_horas_json()` declarava uma variável chamada
`status`. A consulta da tabela `movimentacoes_jornada` também utilizava uma
coluna chamada `status` sem alias:

```sql
... and status <> 'cancelada'
```

O PostgreSQL não conseguia decidir se `status` era a variável PL/pgSQL ou a
coluna da tabela, gerando erro durante a execução de `banco_horas_admin()`.

## Correção

Todas as colunas da consulta passaram a utilizar o alias `mj`, inclusive:

```sql
mj.status
mj.aprovado
mj.efeito_calculo
mj.inicio_em
mj.fim_em
```

A tolerância de entrada implementada na RC5.75 foi preservada.
