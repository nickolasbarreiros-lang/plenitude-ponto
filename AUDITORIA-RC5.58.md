# RC5.58 — abrir o ponto do funcionário selecionado

## Problema

A página de ponto administrativo sempre selecionava o primeiro funcionário da
lista. Por isso, mesmo escolhendo outro funcionário no painel, a nova aba abria
na Roseli.

## Correção

- o painel inclui o funcionário selecionado na URL de `ponto.html`;
- a página de ponto lê o parâmetro `funcionario`;
- se não houver parâmetro, usa o funcionário salvo no painel;
- só então usa o primeiro funcionário como alternativa;
- a troca de funcionário dentro da página atualiza a URL e a preferência salva.
