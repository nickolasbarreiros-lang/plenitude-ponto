# Plenitude Ponto RC5.9 — Carregamento atômico da tela de ponto

- Eliminados os três estados visuais intermediários.
- A fila offline agora é sincronizada antes da primeira renderização da jornada.
- O botão Registrar ponto permanece oculto durante todo o carregamento.
- A tela somente é liberada depois de:
  - validar o funcionário;
  - sincronizar completamente a fila local;
  - carregar as marcações oficiais ou o estado offline;
  - definir a próxima etapa;
  - carregar os recursos complementares disponíveis.
- Em falha ou sincronização incompleta, o ponto permanece bloqueado.
