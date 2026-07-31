begin;

-- RC4.10 — backup seguro via RPC administrativa
-- Evita consultas diretas às tabelas protegidas por RLS.

create or replace function public.exportar_backup_admin(
  p_inicio date,
  p_fim date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_resultado jsonb;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis as p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if p_inicio is null or p_fim is null then
    raise exception 'Informe a data inicial e a data final.';
  end if;

  if p_fim < p_inicio then
    raise exception 'O período informado é inválido.';
  end if;

  select jsonb_build_object(
    'funcionarios',
      coalesce((
        select jsonb_agg(to_jsonb(f) order by f.nome)
        from public.funcionarios f
        where f.empresa_id = v_empresa
      ), '[]'::jsonb),

    'jornadas',
      coalesce((
        select jsonb_agg(to_jsonb(j) order by j.funcionario_id, j.dia_semana)
        from public.jornadas j
        where j.empresa_id = v_empresa
      ), '[]'::jsonb),

    'marcacoes',
      coalesce((
        select jsonb_agg(to_jsonb(m) order by m.registrado_em)
        from public.marcacoes m
        where m.empresa_id = v_empresa
          and m.data_local between p_inicio and p_fim
      ), '[]'::jsonb),

    'ocorrencias',
      coalesce((
        select jsonb_agg(to_jsonb(o) order by o.data_inicio)
        from public.ocorrencias o
        where o.empresa_id = v_empresa
          and o.data_inicio <= p_fim
          and o.data_fim >= p_inicio
      ), '[]'::jsonb),

    'ajustes',
      coalesce((
        select jsonb_agg(to_jsonb(sa) order by sa.criado_em)
        from public.solicitacoes_ajuste sa
        where sa.empresa_id = v_empresa
          and sa.data_marcacao between p_inicio and p_fim
      ), '[]'::jsonb),

    'auditoria',
      coalesce((
        select jsonb_agg(to_jsonb(la) order by la.criado_em)
        from public.logs_auditoria la
        where la.empresa_id = v_empresa
          and la.criado_em >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
          and la.criado_em < ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
      ), '[]'::jsonb)
  )
  into v_resultado;

  return v_resultado;
end;
$$;

revoke all on function public.exportar_backup_admin(date,date)
from public, anon;

grant execute on function public.exportar_backup_admin(date,date)
to authenticated;

commit;

notify pgrst, 'reload schema';
