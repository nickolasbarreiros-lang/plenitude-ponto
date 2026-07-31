# Plenitude Ponto RC5.13 — Liberação correta do ponto offline

## Problema corrigido

O navegador pode emitir o evento `online` ao detectar uma rede local, mesmo sem acesso real ao Supabase.

Nesse cenário, o sistema mostrava **Conexão restabelecida**, iniciava uma trava de sincronização e depois abria a jornada local sem remover completamente essa trava. Por isso o botão de ponto aparecia desabilitado.

## Correções

- Confirma o acesso real ao servidor antes de considerar a conexão restabelecida.
- Quando o servidor não está acessível:
  - cancela o estado de sincronização;
  - esconde o aviso de conexão restabelecida;
  - recarrega a jornada local;
  - remove as classes de bloqueio;
  - libera a próxima marcação offline válida.
- O evento `offline` também recarrega o estado local de forma controlada.
- A tela só libera o botão quando a jornada local foi recuperada com sucesso.

## Console

O erro relacionado a `ext-cdn.cuponomia.com.br` pertence a uma extensão do navegador e não ao Plenitude Ponto.
