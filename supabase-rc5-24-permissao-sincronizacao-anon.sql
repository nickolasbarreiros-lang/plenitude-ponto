-- Plenitude Ponto RC5.24
-- Corrige a autorização da sincronização de contingência.
--
-- Causa:
-- O funcionário usa sessão própria por matrícula/PIN e não uma sessão
-- Supabase Auth. Por isso as RPCs da tela do ponto são executadas pelo papel
-- `anon`. A RC5.22 havia concedido execução somente a `authenticated`,
-- provocando erro HTTP 401.
--
-- A função permanece SECURITY DEFINER e valida internamente:
-- - token do computador autorizado;
-- - empresa do dispositivo;
-- - funcionário ativo da mesma empresa;
-- - evento e tipo da marcação.

begin;

revoke all on function public.sincronizar_marcacao_contingencia(
  text,
  uuid,
  uuid,
  text,
  timestamptz,
  date,
  text,
  integer,
  timestamptz,
  text,
  text,
  text
) from public;

grant execute on function public.sincronizar_marcacao_contingencia(
  text,
  uuid,
  uuid,
  text,
  timestamptz,
  date,
  text,
  integer,
  timestamptz,
  text,
  text,
  text
) to anon, authenticated;

commit;

notify pgrst, 'reload schema';
