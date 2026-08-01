# RC5.24 — permissão da sincronização de contingência

## Erro observado

A RPC `sincronizar_marcacao_contingencia` retornava HTTP 401.

## Causa

O login do funcionário não cria uma sessão Supabase Auth. Ele utiliza um token
próprio gerado por matrícula e PIN. Consequentemente, as chamadas RPC da tela
do ponto são executadas pelo papel `anon`.

Na RC5.22 a função havia recebido permissão apenas para `authenticated`.

## Correção

A execução foi concedida para:

- `anon`
- `authenticated`

A segurança continua sendo feita dentro da função `SECURITY DEFINER`, que
confere o token do dispositivo, empresa e funcionário antes de importar a
marcação.
