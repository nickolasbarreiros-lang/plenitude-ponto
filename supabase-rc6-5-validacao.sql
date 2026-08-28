-- PLENITUDE PONTO RC6.5 — VALIDADOR DA CORREÇÃO DE HORÁRIO
select 'coluna modalidade' as teste,
       exists(select 1 from information_schema.columns
              where table_schema='public' and table_name='solicitacoes_ajuste' and column_name='modalidade') as ok
union all
select 'coluna horario_original',
       exists(select 1 from information_schema.columns
              where table_schema='public' and table_name='solicitacoes_ajuste' and column_name='horario_original')
union all
select 'RPC solicitar_correcao_ponto',
       to_regprocedure('public.solicitar_correcao_ponto(text,date,tipo_marcacao,time without time zone,text)') is not null
union all
select 'RPC listar_ajustes_admin_v2',
       to_regprocedure('public.listar_ajustes_admin_v2(text)') is not null
union all
select 'RPC analisar_ajuste_ponto',
       to_regprocedure('public.analisar_ajuste_ponto(uuid,text,text)') is not null;
