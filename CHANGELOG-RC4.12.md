# Plenitude Ponto 1.0.0 RC4.12

## Correção da página Configurações

Causa:
- o JavaScript tentava atualizar elementos do bloco de PIN Mestre;
- esses elementos não existem mais em `configuracoes.html`;
- `document.getElementById(...)` retornava `null`;
- o código tentava definir `textContent` em `null`.

Correções:
- bloco do PIN Mestre agora só é inicializado quando os elementos existem;
- campos opcionais usam acesso seguro;
- botão de backup também passou a ser opcional;
- eliminada a exceção `Cannot set properties of null`.
