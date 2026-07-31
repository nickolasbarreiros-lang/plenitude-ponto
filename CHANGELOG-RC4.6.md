# Plenitude Ponto 1.0.0 RC4.6

## Auditoria da movimentação temporária

Causa encontrada:
- `ponto-pin.js` procurava o elemento `movement-pending-alert`;
- esse elemento não existia no `ponto.html`;
- a função interrompia com erro JavaScript antes de mudar o status para
  **Fora da loja** e exibir **Registrar retorno**.

Correções:
- elemento ausente incluído;
- consultas independentes com `Promise.allSettled`;
- fallback pela listagem do dia;
- verificação segura de todos os elementos do DOM;
- atualização visual imediata quando o banco informa saída aberta;
- histórico e estado atual deixam de depender um do outro.
