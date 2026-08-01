# RC5.40 — correção da ambiguidade em espelhos mensais

## Erro encontrado

`column reference "funcionario_id" is ambiguous`

A função `listar_espelhos_competencia_admin()` possui uma coluna de saída
chamada `funcionario_id`. No PL/pgSQL, essa coluna também vira uma variável.
O alvo abreviado do `ON CONFLICT` podia ser interpretado como variável ou
como coluna da tabela.

## Correção

- aplicada a diretiva `#variable_conflict use_column`;
- substituído o alvo abreviado por `ON CONFLICT ON CONSTRAINT`;
- aplicada a mesma proteção à função de atualização do status;
- nenhuma alteração de interface foi necessária.
