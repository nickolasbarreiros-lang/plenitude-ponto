# Plenitude Ponto RC5.6 — Estado diário das marcações no modo offline

## Correção

Ao carregar o ponto com internet, o sistema armazena localmente o estado oficial das marcações daquele funcionário e daquele dia.

Quando a internet cai ou a página é reaberta offline:

- recupera Entrada, Almoço e Retorno já registrados;
- combina essas marcações com os novos registros locais;
- libera somente a próxima etapa correta;
- evita reiniciar a jornada como se nenhuma marcação existisse.

## Segurança

Se o computador não tiver recebido o estado do dia antes da queda:

- as quatro etapas não são liberadas;
- o botão de ponto fica bloqueado;
- o sistema solicita uma reconexão para atualizar a jornada.

## Diagnóstico

A página Dispositivos agora verifica também se a **Jornada de hoje** foi preparada para uso offline.
