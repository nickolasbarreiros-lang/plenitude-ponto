# Plenitude Ponto RC6.5.4

Correção do fluxo administrativo de aprovação/rejeição de solicitações de ajuste.

## Causa

O handler dos botões consultava a constante `card` antes da declaração `const card=...`, causando `ReferenceError: Cannot access 'card' before initialization` e interrompendo a ação antes da chamada ao Supabase.

## Correção

A referência ao card agora é obtida antes da confirmação e de qualquer uso. Aprovação e rejeição voltam a alcançar `decideAdjustment`.

## Banco

Nenhum SQL novo. O SQL da RC6.5.3 permanece válido.
