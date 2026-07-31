# Plenitude Ponto RC5.8 — Bloqueio durante sincronização

- O botão de ponto é bloqueado assim que a internet retorna.
- Exibe **Sincronizando registros...** durante o processo.
- Só é liberado depois que:
  - a fila local estiver zerada;
  - todos os registros forem enviados;
  - a jornada oficial for recarregada do servidor.
- Se a sincronização falhar ou permanecer incompleta, o botão continua bloqueado.
- Cliques durante a sincronização são recusados com aviso.
