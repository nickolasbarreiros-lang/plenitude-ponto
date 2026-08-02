# RC5.56 — correção do botão Sair na contingência

## Causa

A página de contingência não possuía um manipulador próprio para o botão
`#sair`, e o carregamento do script específico da página podia impedir o
comportamento global de logout.

## Correção

- adicionada ação de logout diretamente na página de contingência;
- encerra a sessão Supabase;
- limpa os dados temporários da sessão;
- redireciona para `index.html`;
- o botão é desabilitado durante o encerramento para evitar cliques duplicados.
