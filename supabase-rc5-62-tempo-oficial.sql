-- Plenitude Ponto RC5.62
-- Hora oficial centralizada para o frontend.

begin;

create or replace function public.horario_oficial_sistema()
returns table(
  agora timestamptz,
  timezone text,
  data_local date
)
language sql
security definer
set search_path=public
as $$
  select
    clock_timestamp(),
    coalesce(
      (
        select e.timezone
        from public.empresas e
        where e.id=public.empresa_do_usuario()
        limit 1
      ),
      'America/Sao_Paulo'
    )::text,
    (
      clock_timestamp() at time zone coalesce(
        (
          select e.timezone
          from public.empresas e
          where e.id=public.empresa_do_usuario()
          limit 1
        ),
        'America/Sao_Paulo'
      )
    )::date;
$$;

revoke all on function public.horario_oficial_sistema()
  from public,anon;

grant execute on function public.horario_oficial_sistema()
  to authenticated;

commit;

notify pgrst,'reload schema';
