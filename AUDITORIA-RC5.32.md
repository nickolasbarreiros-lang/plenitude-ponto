# RC5.32 — análise administrativa da contingência

## Erro

PostgREST retornava 404 porque não encontrava no cache a função
`analisar_contingencia_admin`.

## Correções

- A função foi recriada com a assinatura esperada pelo frontend.
- Permissão concedida ao papel `authenticated`.
- Rejeição deixa de enviar `p_horario_corrigido` desnecessariamente.
- Aprovação continua permitindo correção do horário.
- Duplicidades são detectadas antes de criar marcação oficial.
- Aprovação e rejeição permanecem registradas na auditoria.
