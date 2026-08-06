# RC5.79 — ambiguidade definitiva da variável status

## Erro

`column reference "status" is ambiguous`

## Causa

A função `_calcular_banco_horas_json()` declarava uma variável PL/pgSQL
chamada `status`. O banco também possui tabelas com colunas chamadas `status`.

Mesmo depois de qualificar `movimentacoes_jornada.status` como `mj.status`,
o nome da variável ainda podia entrar em conflito durante a compilação ou
execução das expressões SQL internas da função.

## Correção

A variável foi renomeada para:

`v_status_dia`

Também foram atualizadas todas as atribuições e o JSON diário retornado pela
função.

A correção dos créditos positivos e a tolerância de entrada foram preservadas.
