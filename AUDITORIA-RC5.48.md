# RC5.48 — ponto administrativo em nova aba

## Causa

A nova aba abria corretamente, mas `ponto.html` ainda carregava diretamente
`ponto-pin.js`. Esse módulo é exclusivo do funcionário e tentava validar um
token PIN inexistente, retornando HTTP 400 e “Sessão expirada”.

## Correção

- `ponto.html` identifica primeiro a sessão Supabase;
- administrador executa `initPonto()` pelo módulo administrativo;
- `ponto-pin.js` só é carregado quando não existe sessão administrativa;
- a sessão Supabase funciona normalmente entre abas pelo localStorage;
- acesso do funcionário e contingência offline permanecem preservados.
