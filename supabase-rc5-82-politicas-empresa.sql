-- ============================================================
-- PLENITUDE PONTO RC5.82
-- FONTE ÚNICA DAS POLÍTICAS DA EMPRESA
-- ============================================================

begin;

create or replace function public.politicas_empresa_admin()
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa_id uuid;
  v_empresa public.empresas%rowtype;
begin
  select p.empresa_id
    into v_empresa_id
  from public.perfis p
  where p.id=auth.uid()
    and p.papel='administrador'
    and p.ativo=true;

  if v_empresa_id is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  select e.*
    into v_empresa
  from public.empresas e
  where e.id=v_empresa_id;

  if v_empresa.id is null then
    raise exception 'Empresa não encontrada.';
  end if;

  return jsonb_build_object(
    'empresa_id',v_empresa.id,
    'timezone',coalesce(v_empresa.timezone,'America/Sao_Paulo'),
    'tolerancia_entrada_minutos',coalesce(v_empresa.tolerancia_entrada_minutos,0),
    'tolerancia_saida_minutos',coalesce(v_empresa.tolerancia_saida_minutos,0),
    'intervalo_minimo_minutos',coalesce(v_empresa.intervalo_minimo_minutos,30),
    'intervalo_maximo_minutos',coalesce(v_empresa.intervalo_maximo_minutos,120),
    'horas_extras_automaticas',coalesce(v_empresa.horas_extras_automaticas,false),
    'limite_banco_horas_minutos',coalesce(v_empresa.limite_banco_horas_minutos,2400),
    'atualizada_em',v_empresa.atualizada_em
  );
end;
$$;

revoke all on function public.politicas_empresa_admin()
from public,anon;

grant execute on function public.politicas_empresa_admin()
to authenticated;

commit;

notify pgrst,'reload schema';
