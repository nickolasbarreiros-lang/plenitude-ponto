# RC5.82 — centralização da tolerância de entrada

## Causa encontrada

O painel usava `profile.tolerancia_entrada_minutos || 15`.

A configuração pertence à empresa e não ao perfil administrativo. Quando o
campo não existia diretamente no perfil, o JavaScript aplicava o valor fixo
de 15 minutos, mesmo que a empresa estivesse configurada com 10.

## Correção

- criada a RPC `politicas_empresa_admin()`;
- painel consulta diretamente as políticas da empresa;
- removido o fallback fixo de 15;
- alerta mostra funcionário, horário previsto, limite da tolerância,
  horário registrado e atraso considerado.

Exemplo: prevista 09:00, tolerância até 09:10, registrada 09:22,
atraso considerado 12 minutos.
