# RC5.21 — sincronização e deduplicação

## Falhas corrigidas

- `app.js` era carregado na página do ponto e tentava acessar componentes
  administrativos inexistentes, gerando erros no console.
- A sincronização ocultava o motivo real da falha.
- Matrículas `001`, `1` ou com espaços podiam ser tratadas como chaves diferentes.
- O mesmo funcionário podia aparecer mais de uma vez em Dispositivos.

## Mudanças

- A tela do ponto passa a usar somente o controlador `ponto-pin.js`.
- Erros da RPC de sincronização são exibidos com mensagem real.
- A fila local é preservada quando houver falha.
- Matrículas são normalizadas internamente.
- Logins offline antigos são migrados e deduplicados.
- A página Dispositivos agrupa registros pelo ID real do funcionário.
