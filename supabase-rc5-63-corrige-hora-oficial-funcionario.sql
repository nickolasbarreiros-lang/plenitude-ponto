-- Plenitude Ponto RC5.63
-- Corrige o acesso ao horário oficial na tela do funcionário.

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
    'America/Sao_Paulo'::text,
    (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
$$;

revoke all on function public.horario_oficial_sistema()
  from public;

grant execute on function public.horario_oficial_sistema()
  to anon,authenticated;

commit;

notify pgrst,'reload schema';
