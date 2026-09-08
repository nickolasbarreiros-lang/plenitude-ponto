# Plenitude Ponto RC6.5.5-HF1

Hotfix visual do espelho mensal após a reintegração de `feriados_empresa` no cálculo.

## Correções

- Dias sem jornada continuam ocultos quando não possuem evento relevante.
- Feriados cadastrados em `feriados_empresa` passam a aparecer na Apuração diária mesmo com `previsto_minutos = 0` e sem marcações.
- O nome do feriado é exibido ao lado do status.
- A mesma regra foi aplicada ao espelho mensal de impressão/PDF.
- Acrescentados rótulos amigáveis para feriado trabalhado, banco em dobro, folha e abonado.
- Nenhuma alteração de banco de dados é necessária neste hotfix.

## Exemplo esperado

07/09/2026 | — | — | — | — | 00:00 | 00:00 | +00:00 | Feriado · Independência do Brasil
