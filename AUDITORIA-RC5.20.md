# RC5.20 — reautenticação após uso offline

## Problema

O login offline reutiliza uma sessão previamente armazenada. Durante uma queda prolongada, o token dessa sessão pode expirar no servidor.

Quando a internet retornava, a RPC `dados_funcionario_token` respondia com erro 400 e a tela ficava bloqueada em:

`Sessão expirada. Entre novamente.`

Além disso, o objeto bruto do Supabase podia aparecer como `[object Object]`.

## Correção

- Erros do Supabase agora são normalizados.
- Sessão expirada é diferenciada de falta de internet.
- A fila offline é preservada.
- O sistema redireciona para o login do funcionário.
- Matrícula é preenchida automaticamente.
- O funcionário informa apenas o PIN novamente.
- Após o novo login online, um token válido é criado.
- Ao abrir o ponto, a fila offline é sincronizada automaticamente.
- O marcador de reautenticação é apagado após o login bem-sucedido.

Nenhuma marcação offline é apagada durante esse processo.
