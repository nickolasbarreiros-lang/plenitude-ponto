# RC5.77 — crédito positivo do banco de horas

Função-base: `supabase-v28-movimentacoes-jornada.sql`.

A função calculava +00:04, mas zerava o crédito quando `horas_extras_automaticas` estava desabilitado.

Com a política marcada, créditos positivos passam a integrar o banco. Com ela desmarcada, só entram mediante autorização.
