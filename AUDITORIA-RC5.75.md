# RC5.75 — tolerância de entrada no cálculo

## Causa

A política estava salva corretamente, mas a função ativa de banco de horas no
Supabase não estava aplicando a tolerância de entrada na versão efetivamente
instalada. O relatório usava a entrada real, debitando 8 minutos na segunda e
4 minutos na terça.

## Correção

- horário real permanece visível;
- entrada de 09:00:01 até 09:10:59, com tolerância de 10 minutos, é considerada
  09:00 para cálculo;
- a partir de 09:11:00, o horário real é usado;
- a função completa de banco de horas foi redefinida sobre a versão com
  movimentações, feriados e demais regras atuais.

## Efeito esperado nos exemplos

Segunda:
- entrada 09:08 deixa de gerar débito de 8 minutos;
- ainda permanece eventual diferença causada pelo intervalo real ou saída.

Terça:
- entrada 09:04 deixa de gerar débito de 4 minutos;
- a saída 18:30 para jornada prevista até 19:00 continua gerando diferença,
  salvo se a tolerância de saída também a neutralizar conforme a política.
