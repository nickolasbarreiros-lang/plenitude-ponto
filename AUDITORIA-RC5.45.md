# RC5.45 — localização da funcionária no SQL Editor

## Causa do erro

O SQL RC5.44 utilizava `empresa_do_usuario()`. No SQL Editor do Supabase não
existe a sessão autenticada do administrador do site, portanto a empresa não
era localizada e a busca pela matrícula 001 falhava.

## Correção

- busca prioritária pelo nome completo da Roseli;
- alternativa por matrícula 1, 01, 001 etc.;
- não depende da sessão do site;
- se a funcionária não for encontrada, a migração não é interrompida;
- a função de cálculo é atualizada mesmo assim.
