# RC5.81 — correção do estado do switch

## Causa

O script da RC5.80 procurava IDs inexistentes:

- `config-horas-extras`;
- `horas-extras-automaticas`.

O ID real do campo era `extras-auto`. Por isso o texto permanecia
"Desativado" mesmo com o switch marcado.

## Correção

- atualização ligada diretamente ao campo `extras-auto`;
- estado visual atualizado após carregar os dados do Supabase;
- atualização imediata ao clicar no switch;
- atualização após salvar;
- verde e texto "Ativado" quando ligado;
- cinza e texto "Desativado" quando desligado;
- descrição dinâmica conforme o estado.
