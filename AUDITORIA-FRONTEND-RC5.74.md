# Auditoria frontend RC5.74 — pendência fantasma

## Causa confirmada

O Supabase retornou zero pendências para os funcionários ativos. Porém, o
arquivo `assets/js/app.js` publicado ainda era RC5.67 e o painel fazia três
consultas independentes:

- `listar_ajustes_admin`;
- `listar_pendencias_jornada_admin`;
- `listar_pendencias_retorno_admin`.

A página Ajustes mostrava apenas solicitações de ajuste. Já o painel exibia
também jornadas incompletas. Por isso existia a divergência visual.

Além disso, o resultado de `listar_pendencias_jornada_admin()` era usado sem
verificar se `funcionario_id` ainda pertencia a um funcionário ativo.

## Correção implementada

Antes de contar ou exibir qualquer ocorrência, o painel cria um conjunto com
os IDs de `activeEmployees` e filtra:

- ajustes;
- jornadas incompletas;
- retornos temporários.

Funcionários com `ativo=false`, `status=inativo` ou acesso ao ponto desligado
não podem mais alimentar:

- card Pendências;
- badge do menu;
- Notificações;
- quantidade de ações pendentes.

## Cache

Todos os recursos foram alterados para RC5.74 e o Service Worker usa o cache
`plenitude-ponto-rc5-74`.

## SQL

Nenhum SQL novo é necessário. O diagnóstico já comprovou que o banco possui
zero pendências dos funcionários ativos.
