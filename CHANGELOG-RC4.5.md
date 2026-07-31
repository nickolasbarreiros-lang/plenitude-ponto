# Plenitude Ponto 1.0.0 RC4.5

## Estado correto de saída temporária

- Criada RPC específica para consultar o estado atual da movimentação.
- A tela deixa de depender apenas da listagem histórica.
- Quando existe saída aberta hoje, exibe **Fora da loja**.
- O formulário de nova saída é fechado.
- O botão muda para **Registrar retorno**.
- Caso o backend rejeite uma nova saída por já existir uma aberta, a interface é ressincronizada imediatamente.
- Pendências antigas continuam exibidas separadamente e não bloqueiam a saída atual.
