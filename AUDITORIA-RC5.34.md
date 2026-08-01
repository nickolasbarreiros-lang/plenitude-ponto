# RC5.34 — correção do ID da contingência

## Causa

Os botões usam:

- `data-approve`
- `data-reject`

Mas o JavaScript tentava acessar:

- `button.dataset.aprovar`
- `button.dataset.rejeitar`

Como essas propriedades não existem, `p_id` ficava `undefined` e era removido
do JSON enviado ao Supabase. Por isso o PostgREST procurava uma função apenas
com `p_acao` e `p_observacao`.

## Correção

O código agora lê explicitamente:

- `button.dataset.approve`
- `button.dataset.reject`

e valida o ID antes de chamar a RPC.
