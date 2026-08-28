# Plenitude Ponto RC6.5.1

Correções de interface no painel do funcionário:

- O formulário de correção fica fechado por padrão.
- "Abrir nova solicitação" abre o formulário.
- Enquanto aberto, o botão passa a "Fechar solicitação".
- Fechar limpa o formulário.
- Após envio bem-sucedido, o formulário volta ao estado fechado.
- A opção "O horário registrado está incorreto" força a consulta do horário atual.
- O horário atual aparece antes do envio, por exemplo:
  "Horário atualmente registrado: 09:04."
- Mensagens específicas são exibidas se a marcação não existir, se estiver offline
  ou se a consulta ao servidor falhar.
- CSS reforçado para que o atributo hidden não seja sobrescrito.
- Cache e marcadores de build alterados para RC6.5.1.

Nenhum SQL novo é necessário. A RC6.5 no Supabase permanece válida.
