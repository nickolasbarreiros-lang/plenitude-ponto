# Plenitude Ponto RC5.14 — Auditoria e estabilidade online/offline

- Removido o teste REST que gerava 401.
- Estado online/offline baseado na RPC real do funcionário.
- Marcações separadas das consultas opcionais de saldo.
- Transições de conexão serializadas.
- Sincronização exibida somente quando existe fila local.
- Correção do selo local e do botão bloqueado no modo online.
- Consultas complementares não bloqueiam a tela de ponto.
