# RC5.66 — correção do cooldown de 305 segundos

## Causa

O prazo do cooldown era criado usando o horário oficial:

`punchCooldownUntil = officialNowMs() + 5 segundos`

Porém, o tempo restante era calculado usando o relógio local:

`punchCooldownUntil - Date.now()`

Quando o computador estava aproximadamente cinco minutos atrasado, o sistema
somava essa diferença aos cinco segundos e mostrava cerca de 305 segundos.

## Correção

- criação e leitura do cooldown usam `officialNowMs()`;
- proteção contra clique permanece fixada em 5 segundos;
- intervalo de almoço permanece separado e fixado em 30 minutos;
- constantes independentes foram criadas:
  - `CLICK_COOLDOWN_MS = 5000`
  - `LUNCH_MINIMUM_MS = 1800000`

Não exige SQL novo.
