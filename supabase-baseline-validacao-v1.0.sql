-- PLENITUDE PONTO — validação pós-baseline
-- Somente leitura.

select
  n.nspname as schema,
  c.relname as tabela,
  c.relrowsecurity as rls_habilitado
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
  and c.relkind='r'
order by c.relname;

select
  p.proname as funcao,
  pg_get_function_identity_arguments(p.oid) as argumentos,
  case when p.prosecdef then 'DEFINER' else 'INVOKER' end as seguranca
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
order by p.proname,argumentos;

select schemaname,tablename,policyname,roles,cmd
from pg_policies
where schemaname='public'
order by tablename,policyname;

select
  'banco acumulado' as teste,
  to_regprocedure('public.banco_horas_acumulado_admin(uuid,integer,integer)') is not null as ok
union all
select
  'politicas empresa',
  to_regprocedure('public.politicas_empresa_admin()') is not null
union all
select
  'registro com pin',
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='registrar_ponto_com_pin'
  )
union all
select
  'fechamento master',
  to_regprocedure('public.fechar_competencia_master_admin(integer,integer,text,text)') is not null;
