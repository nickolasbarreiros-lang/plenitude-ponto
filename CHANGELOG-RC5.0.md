# Plenitude Ponto RC5.0 — Contingência Offline

- Entrada automática em contingência quando a comunicação com o Supabase falha.
- O funcionário não escolhe o modo; apenas recebe aviso visual.
- Registros locais em IndexedDB com UUID, horário, fuso e cadeia de hashes.
- Service Worker mantém a tela do ponto disponível sem internet após o primeiro carregamento.
- Contagem permanente de registros aguardando sincronização.
- Sincronização automática quando a conexão retorna.
- Registros enviados entram em tabela separada e não viram ponto oficial automaticamente.
- Nova página administrativa **Contingência** para aprovar, corrigir horário ou rejeitar.
- Detecção de duplicidade e divergências relevantes de relógio.
- Intervalo mínimo de 30 minutos também é aplicado offline.
