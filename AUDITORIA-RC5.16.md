# Auditoria RC5.16

## Erro principal

A RC5.15 chamava:

- `cacheEmployeeProfile()`
- `restoreEmployeeProfile()`

mas essas funções não estavam presentes no arquivo final. Isso causava:

`ReferenceError: cacheEmployeeProfile is not defined`

e interrompia a abertura em 10%.

## Correções

- Funções de cache e restauração incluídas.
- Abertura online usa texto neutro: **Abrindo ponto**.
- Recursos complementares carregam em segundo plano.
- Selo **Gravação local** é ocultado obrigatoriamente no modo online.
- Travas visuais de sincronização são removidas ao confirmar conexão online.
