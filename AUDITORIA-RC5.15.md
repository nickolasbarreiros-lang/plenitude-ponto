# Auditoria RC5.15 — estabilidade online/offline

## Falhas encontradas

1. O teste `/rest/v1/` considerava qualquer resposta HTTP, inclusive `401`, como conexão válida.
2. O evento `online` podia ativar sincronização mesmo sem acesso real às RPCs.
3. Registros locais já sincronizados continuavam sendo mesclados à jornada.
4. O aviso “Conexão restabelecida” podia permanecer visível com fila zerada.
5. Classes de bloqueio offline podiam permanecer no botão após voltar ao modo online.
6. Uma falha secundária de banco de horas podia contaminar o estado principal da jornada.

## Correções

- A conectividade agora é confirmada pela RPC real `dados_funcionario_token`.
- Removida a chamada direta para `/rest/v1/`.
- Transições online/offline são serializadas.
- O aviso de sincronização só aparece se houver fila real.
- Somente registros locais pendentes entram na jornada.
- Registros sincronizados são removidos do IndexedDB.
- A marcação oficial é carregada antes dos saldos e ferramentas complementares.
- O modo online força a remoção de todas as travas visuais.
- O botão é liberado somente após a definição segura da próxima etapa.
