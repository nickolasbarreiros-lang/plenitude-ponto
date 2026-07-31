# Plenitude Ponto RC5.12 — Abertura offline rápida e barra de progresso

## Causa da demora

`navigator.onLine` pode continuar indicando conexão mesmo quando o computador está sem acesso real à internet. O sistema então tentava várias RPCs do Supabase e aguardava o timeout de cada uma, gerando demora e erros `ERR_INTERNET_DISCONNECTED`.

## Correções

- Teste real do Supabase com limite de 2,5 segundos.
- Quando o servidor não responde, o sistema entra imediatamente no estado local.
- As RPCs deixam de ser disparadas quando o servidor já foi considerado inacessível.
- Timeout máximo de segurança para RPCs.
- Service Worker não é registrado novamente durante uma queda de internet.
- Barra de progresso informa cada etapa do carregamento.
- O botão de ponto permanece oculto até 100% da preparação.
- Erros de rede esperados deixam de se acumular no console durante o modo offline.
