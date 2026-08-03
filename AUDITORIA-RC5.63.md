# RC5.63 — correção real do horário oficial no ponto do funcionário

## Causa encontrada

A função `horario_oficial_sistema()` estava liberada apenas para usuários
autenticados. O funcionário acessa o ponto por matrícula/PIN usando a função
anônima do Supabase, portanto a consulta era recusada e o módulo voltava para
o relógio local do computador.

Além disso, `ponto-pin.js` ainda desenhava o relógio com `new Date()` e o
contador de almoço comparava com `Date.now()`.

## Correções

- horário oficial liberado para `anon` e `authenticated`;
- relógio do funcionário usa `PlenitudeClock.now()`;
- contador do almoço usa o horário oficial;
- cooldowns usam a mesma fonte de tempo;
- registro do Service Worker atualizado de RC5.28 para RC5.63;
- online sem sincronização mostra erro, não finge que a hora local é oficial.

A migração SQL RC5.63 é obrigatória.
