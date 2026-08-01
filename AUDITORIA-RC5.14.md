# Auditoria técnica RC5.14

## Falhas encontradas e corrigidas

1. O teste de conectividade consultava `/rest/v1/`, que retornava 401 e gerava erro no console. O teste foi removido; a própria RPC autenticada do funcionário passou a determinar se o servidor está disponível.
2. Uma falha em qualquer consulta de banco de horas fazia toda a jornada ser tratada como offline. Agora as marcações são críticas e os saldos são consultas opcionais.
3. Eventos `online` e `offline` podiam executar ao mesmo tempo e deixar `syncInProgress` travado. Foi criada uma transição única de conexão.
4. O aviso de sincronização aparecia mesmo com zero registros locais. Agora só aparece quando existe fila real.
5. O modo online podia manter o selo “Gravação local”. O estado visual agora é redefinido somente depois que as marcações oficiais são carregadas.
6. O botão podia herdar classes de bloqueio de uma transição anterior. A renderização final recalcula o estado do botão a partir da jornada real.
7. Consultas complementares de movimentações, ajustes e saldos não impedem mais a abertura do ponto.
8. Registros locais e oficiais são combinados com deduplicação básica.

## Testes estáticos executados

- Sintaxe de todos os arquivos JavaScript com `node --check`.
- Conferência de referências locais de CSS e JavaScript nos HTMLs.
- Conferência de versão única RC5.14 nos arquivos HTML.
- Conferência da lista de arquivos essenciais do Service Worker.
