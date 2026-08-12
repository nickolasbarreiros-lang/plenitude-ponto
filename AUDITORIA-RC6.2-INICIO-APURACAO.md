# RC6.2 — início real da apuração

## Causa confirmada

Julho/2026 foi consolidado como -200:09 porque cada dia útil sem marcação foi
tratado como falta integral.

## Regra corrigida

Roseli (matrícula 001) passa a participar da apuração em 03/08/2026.

Dias anteriores ficam com status `pre_apuracao` e saldo zero.

Para funcionários futuros, `data_inicio_apuracao` recebe por padrão a data do
cadastro/instalação. Se estiver vazia, o motor usa a primeira marcação e depois
a data de admissão como fallback.

## Efeito esperado

O snapshot incorreto de julho será reconstruído como 00:00 para Roseli.
O banco acumulado passará a refletir somente agosto/2026 em diante.
