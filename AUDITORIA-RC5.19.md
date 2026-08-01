# RC5.19 — remoção de bloqueio indevido do botão

## Verificação sobre horário

Não existe regra de faixa de horário para impedir:

- entrada antes do horário previsto;
- entrada após o horário previsto;
- marcação em sábado, domingo ou folga;
- saída fora da escala.

A jornada é apenas informativa.

## Correção

Foi adicionada uma liberação online direta e independente das regras de contingência.

Quando:

- o servidor está confirmado online;
- a tela terminou de carregar;
- existem menos de quatro marcações;
- não há gravação ou sincronização em andamento;

o atributo `disabled` é removido explicitamente.

A liberação é repetida:

- ao terminar a carga da jornada;
- ao revelar a tela;
- no próximo frame;
- 100 ms depois;
- ao restaurar o estado visual online.
