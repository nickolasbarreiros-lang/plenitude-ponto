# RC5.62 — tempo oficial centralizado

## Online

- relógio visual sincronizado com `clock_timestamp()` do Supabase;
- offset calculado considerando a latência da consulta;
- ressincronização ao abrir, reconectar, voltar à aba e a cada 5 minutos;
- relógio grande, data atual e contadores usam a mesma fonte oficial.

## Offline

- usa o relógio local apenas na contingência;
- exibe indicador amarelo informando a origem local;
- ao reconectar, volta automaticamente ao horário oficial.

## Diagnóstico

Se o relógio do Windows diferir mais de 1 minuto do servidor, a tela informa
quantos minutos o computador está adiantado ou atrasado.

A migração SQL RC5.62 é obrigatória.
