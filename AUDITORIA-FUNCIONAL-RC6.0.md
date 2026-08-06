# Auditoria funcional Plenitude Ponto — RC6.0

## Base auditada

RC5.83 baixada diretamente do repositório.

## Verificações concluídas

- 20 páginas HTML;
- 24 módulos JavaScript;
- 53 arquivos SQL;
- validação sintática de todos os JavaScripts;
- cache e atualização do Service Worker;
- dashboard, políticas, notificações e funcionários ativos;
- referências às RPCs e funções SQL duplicadas.

## Resultado

Não foram encontrados erros de sintaxe JavaScript.

A estrutura publicada estava consistente com a RC5.83. Foram encontradas 24
funções SQL redefinidas em diferentes migrações. Isso não impede o uso atual,
mas continua sendo um risco de manutenção: um SQL antigo executado fora da
ordem pode restaurar uma função antiga.

## Correções implementadas na RC6.0

### 1. Funcionários ativos

O dashboard agora considera ativo somente quem cumpre simultaneamente:

- `ativo = true`;
- `status = ativo`;
- acesso ao ponto não desabilitado.

### 2. Cálculo e notificação de atrasos

A jornada de cada funcionário é consultada apenas uma vez por atualização.

Antes, a jornada era consultada para contar o atraso e novamente para montar a
notificação. Isso podia gerar divergência e duplicava chamadas ao Supabase.

Agora o cálculo produz uma estrutura única com:

- horário previsto;
- limite da tolerância;
- entrada registrada;
- minutos considerados.

O contador e a notificação usam os mesmos dados.

### 3. Ausências

Eliminada uma expressão redundante que recalculava ausências lendo e filtrando
o próprio DOM. O painel usa diretamente o valor já apurado.

### 4. Proteção das notificações

Nomes e textos exibidos por `innerHTML` passaram por escape de HTML. Isso evita
que conteúdos cadastrados sejam interpretados como marcação HTML.

### 5. Atualização e identificação

- cache alterado para `plenitude-ponto-rc6-0`;
- recursos alterados para `1.0.0-rc6.0`;
- Version Guard atualizado para RC6.0;
- badge discreto de versão no painel administrativo.

## Pontos ainda recomendados

### Alta prioridade

Criar uma baseline SQL consolidada. Existem múltiplas definições históricas
para funções críticas, incluindo registro de ponto e banco de horas.

### Média prioridade

Substituir gradualmente as três fontes legadas de pendências por uma única RPC
operacional no Supabase.

### Testes que exigem ambiente real

A auditoria estática não substitui testes conectados ao Supabase. Devem ser
executados no ambiente:

- registro completo de jornada;
- clique duplo;
- intervalo mínimo;
- contingência e sincronização;
- ajuste aprovado e rejeitado;
- fechamento e reabertura;
- exclusão lógica e física;
- funcionário inativo;
- dispositivo não autorizado;
- expiração de sessão.
