-- Plenitude Ponto RC5.26B
-- Corrige a consulta das pendências de jornada no ponto do funcionário.

begin;

create or replace function public.listar_minhas_pendencias_jornada(
  p_token text
)
returns table(
  id uuid,
  data_local date,
  quantidade_marcacoes integer,
  marcacao_faltante text,
  marcacao_faltante_label text,
  status text,
  detectada_em timestamptz
)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  perform public.atualizar_pendencias_jornada_empresa(
    v_funcionario.empresa_id,
    v_funcionario.id
  );

  return query
  select
    pj.id,
    pj.data_local,
    pj.quantidade_marcacoes,
    pj.marcacao_faltante,
    public.rotulo_marcacao_jornada(pj.marcacao_faltante),
    pj.status,
    pj.detectada_em
  from public.pendencias_jornada pj
  where pj.empresa_id=v_funcionario.empresa_id
    and pj.funcionario_id=v_funcionario.id
    and pj.status='pendente'
  order by pj.data_local,pj.detectada_em;
end;
$$;

revoke all on function public.listar_minhas_pendencias_jornada(text)
  from public;

grant execute on function public.listar_minhas_pendencias_jornada(text)
  to anon,authenticated;

commit;

notify pgrst,'reload schema';
