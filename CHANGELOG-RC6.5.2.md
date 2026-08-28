# Plenitude Ponto RC6.5.2

Correção dos dois botões laterais do painel do funcionário.

Causa encontrada:
- `.movement-exit-form` possuía `display:grid` no CSS.
- Esse `display` de autor podia sobrescrever o atributo HTML `hidden`.
- Na captura, o campo vazio da saída temporária já estava aparecendo mesmo
  antes do clique, confirmando a inconsistência de estado visual.
- Os controles também dependiam de atribuições `onclick`; foram reforçados
  com `addEventListener` e estado visual explícito.

Correções:
- formulário de saída temporária realmente fechado por padrão;
- botão Registrar saída temporária abre o formulário;
- Cancelar volta ao estado fechado;
- botão Abrir nova solicitação abre o formulário de correção;
- botão passa para Fechar solicitação enquanto aberto;
- hidden recebe regra CSS específica com `!important`;
- `style.display` é sincronizado pelo JavaScript;
- mensagens explícitas quando a ação estiver bloqueada por modo offline;
- log de diagnóstico RC6.5.2 no Console.

Nenhum SQL novo é necessário.
