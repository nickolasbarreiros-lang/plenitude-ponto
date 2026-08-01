# RC5.18 — Liberação definitiva do botão online

## Causa

O botão nasce no HTML com `disabled`. Durante o carregamento, várias rotinas alteravam esse estado antes de `pointReady` tornar-se verdadeiro. Quando a tela era revelada, não havia uma nova avaliação definitiva, permitindo que o atributo `disabled` permanecesse.

## Correção

- Criada uma única função `refreshPunchAvailability()`.
- A função considera:
  - tela completamente pronta;
  - jornada ainda não concluída;
  - ausência de sincronização;
  - ausência de gravação em andamento;
  - fim do cooldown;
  - servidor online ou contingência válida.
- O botão é reavaliado:
  - no fim da renderização;
  - após remover o loading;
  - no próximo frame do navegador;
  - após o cooldown;
  - ao restaurar o modo online.
- O atributo `disabled` é removido explicitamente quando o registro é permitido.
