# Plenitude Ponto RC5.10 — Correção do carregamento offline

## Causa do erro

Os arquivos estavam armazenados no cache sem parâmetro de versão, por exemplo:

`assets/js/ponto-pin.js`

Mas a página solicitava:

`assets/js/ponto-pin.js?v=1.0.0-rc5.9`

Sem internet, o Service Worker tratava essas URLs como diferentes e devolvia erro 503. Como o JavaScript principal não carregava, a tela permanecia indefinidamente em **Carregando jornada**.

## Correções

- O Service Worker agora localiza arquivos ignorando parâmetros de versão.
- Cada recurso é salvo também com uma URL limpa, sem query string.
- Navegações offline procuram `ponto.html` e `index.html` ignorando versões.
- Incluído aviso de falha após 20 segundos caso um arquivo essencial não carregue.
- O aviso não libera o botão de ponto; apenas explica como recuperar o terminal.
