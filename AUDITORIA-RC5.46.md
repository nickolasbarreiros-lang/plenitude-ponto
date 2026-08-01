# RC5.46 — registro de ponto pelo painel administrativo

## Causa do erro

A página `ponto.html` carregava apenas `ponto-pin.js`. Esse módulo é exclusivo
do funcionário e exige um token PIN armazenado em
`plenitude-employee-session`.

Quando o administrador abria a mesma página pelo painel, um token antigo do
funcionário podia ser lido. A RPC `dados_funcionario_token` retornava 400 e a
tela informava “Sessão expirada”.

## Correção

- a página identifica primeiro a sessão autenticada do Supabase;
- administrador entra no modo administrativo de `initPonto()`;
- o seletor de funcionários é exibido;
- a sessão PIN antiga é removida apenas do `sessionStorage`;
- funcionário continua usando `ponto-pin.js`;
- contingência offline do funcionário foi preservada;
- somente um dos dois módulos é executado em cada acesso.
