# Plenitude Ponto RC6.5

## Correção de ponto pelo funcionário

O formulário do funcionário passa a distinguir:
- **Não consegui registrar uma marcação** — fluxo de inclusão já existente.
- **O horário registrado está incorreto** — novo fluxo de correção.

No modo de correção, o painel consulta e mostra o horário atualmente gravado antes do envio.

## Aprovação administrativa

A tela Ajustes passa a exibir:
- modalidade da solicitação;
- horário atual;
- horário solicitado.

Ao aprovar uma correção:
- o ID original da marcação é preservado;
- `registrado_em` é alterado;
- `ajustada=true`;
- a auditoria registra valor anterior e novo;
- a sequência Entrada → Almoço → Retorno → Saída é validada;
- competência fechada não pode ser alterada.

## Instalação no banco atual

Execute somente:
`supabase-rc6-5-correcao-horario-funcionario.sql`

Depois publique os arquivos modificados do site.

A RC6.4 continua válida e foi incorporada ao novo SQL-base consolidado v1.2.
