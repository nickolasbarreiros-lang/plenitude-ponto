# RC5.57 — contagem correta de pendências no painel

## Problema

O painel somava:

- jornada incompleta;
- solicitação de ajuste pendente.

Quando a solicitação correspondia à própria jornada incompleta, o mesmo caso
era contado duas vezes.

## Correção

A jornada incompleta é removida da contagem quando existe solicitação pendente
para o mesmo funcionário, data e marcação. Também foi adicionada compatibilidade
por funcionário + data para registros antigos.

O card do painel, o badge lateral e os alertas passam a mostrar somente ações
distintas que realmente exigem análise.
