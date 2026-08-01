# RC5.33 — RPC de contingência V2

O PostgREST continuava resolvendo a assinatura antiga de
`analisar_contingencia_admin`, retornando PGRST202.

A correção cria uma RPC nova, sem conflito de cache:

- `analisar_contingencia_admin_v2`
- horário recebido como texto e convertido internamente;
- aprovação, rejeição, duplicidade e auditoria preservadas.
