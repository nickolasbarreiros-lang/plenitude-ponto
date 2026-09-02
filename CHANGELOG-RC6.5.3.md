# Plenitude Ponto RC6.5.5

Correção estrutural dos botões laterais da tela `ponto.html` quando ela é aberta a partir de uma sessão administrativa.

## Causa confirmada

A RC6.5.2 corrigiu os listeners dentro de `ponto-pin.js`. Porém, ao abrir o ponto pelo painel administrativo, `ponto.html` detecta a sessão de administrador e, propositalmente, **não carrega `ponto-pin.js`**. Nesse contexto a página usa `initPonto()` de `app.js`.

Por isso os botões apareciam, mas não recebiam os listeners do módulo do funcionário. A captura do Console também confirma isso: apareciam os logs de `app.js` e do Version Guard, mas não o log de inicialização de `ponto-pin.js`.

## Correção

- `Registrar saída temporária` agora funciona também no modo administrativo da tela de ponto;
- o formulário de motivo abre e fecha corretamente;
- saída e retorno temporários são registrados por RPC administrativa própria, com auditoria;
- `Abrir nova solicitação` agora abre/fecha o formulário no modo administrativo;
- inclusão de marcação ausente e correção de horário podem ser solicitadas em nome do funcionário selecionado;
- o horário atual é consultado antes de uma correção;
- histórico lateral de movimentações e ajustes é atualizado ao trocar o funcionário selecionado;
- novas ações administrativas ficam registradas em `logs_auditoria`;
- cache, Version Guard e referências de build atualizados para RC6.5.5.

## Banco

Executar em produção apenas:

`supabase-rc6-5-5-admin-autoatendimento-ponto.sql`

A baseline de instalação limpa foi consolidada como:

`supabase-baseline-plenitude-ponto-v1.3-rc6.5.3.sql`
