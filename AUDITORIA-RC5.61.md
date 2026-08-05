# RC5.61 — exclusão administrativa de marcações

## Nível 1 — remover do sistema

- remove a linha da tabela `marcacoes`;
- preserva uma cópia completa em `marcacoes_arquivadas`;
- exige justificativa;
- registra evento na auditoria;
- não pode ser usado em competência fechada.

## Nível 2 — exclusão definitiva

- apaga a marcação ativa ou a cópia arquivada;
- exige justificativa detalhada;
- exige digitar `EXCLUIR`;
- exige PIN Mestre de seis dígitos;
- preserva somente o evento mínimo de auditoria;
- não pode ser usado em competência fechada.

A tela administrativa está em `marcacoes.html`.
