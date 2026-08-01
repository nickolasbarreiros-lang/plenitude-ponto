# RC5.22 — importação automática da contingência

## Causa confirmada

A sincronização anterior não alimentava a jornada oficial por definição.

A função `sincronizar_marcacao_contingencia()` gravava somente na tabela
`marcacoes_contingencia` com status `pendente`.

A tela online consulta a tabela `marcacoes`. Por isso, mesmo com a sincronização
concluída, a entrada não aparecia até que o administrador aprovasse manualmente.

## Novo comportamento

- Marcações offline válidas são inseridas imediatamente em `public.marcacoes`.
- A origem fica registrada como `contingencia`.
- O registro auxiliar fica como `aprovado`.
- O evento continua registrado na auditoria.
- O mesmo evento é idempotente e não pode ser importado duas vezes.
- Duplicidades são classificadas automaticamente como `duplicado`.
- Horários futuros ou com diferença superior a sete dias continuam
  `conflitantes` e exigem análise administrativa.
