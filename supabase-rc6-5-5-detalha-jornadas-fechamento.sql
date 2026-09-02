-- ============================================================
-- PLENITUDE PONTO RC6.5.5
-- FECHAMENTO: DETALHAMENTO E ENCAMINHAMENTO DE JORNADAS INCOMPLETAS
-- ============================================================

begin;

create or replace function public.auditar_competencia_admin(
  p_ano integer,
  p_mes integer
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_inicio date;
  v_fim date;
  v_timezone text:='America/Sao_Paulo';
  v_hoje date;
  v_jornadas integer:=0;
  v_jornadas_detalhes jsonb:='[]'::jsonb;
  v_ajustes integer:=0;
  v_contingencias integer:=0;
  v_movimentacoes integer:=0;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if p_ano not between 2020 and 2100 or p_mes not between 1 and 12 then
    raise exception 'Competência inválida.';
  end if;

  v_empresa:=public.empresa_do_usuario();
  v_inicio:=make_date(p_ano,p_mes,1);
  v_fim:=(v_inicio+interval '1 month - 1 day')::date;

  select coalesce(e.timezone,'America/Sao_Paulo')
    into v_timezone
  from public.empresas e
  where e.id=v_empresa;

  v_hoje:=(clock_timestamp() at time zone v_timezone)::date;

  with jornadas as (
    select
      m.funcionario_id,
      f.nome as funcionario_nome,
      f.matricula,
      m.data_local,
      count(*)::integer as quantidade_marcacoes,
      case
        when count(*) filter(where m.tipo='entrada')=0 then 'entrada'
        when count(*) filter(where m.tipo='inicio_intervalo')=0 then 'inicio_intervalo'
        when count(*) filter(where m.tipo='fim_intervalo')=0 then 'fim_intervalo'
        when count(*) filter(where m.tipo='saida')=0 then 'saida'
        else public.tipo_marcacao_faltante_jornada(count(*)::integer)
      end as marcacao_faltante
    from public.marcacoes m
    join public.funcionarios f on f.id=m.funcionario_id
    where f.empresa_id=v_empresa
      and coalesce(f.ativo,false)=true
      and coalesce(f.status,'ativo')<>'inativo'
      and coalesce(f.acesso_ponto_ativo,true)=true
      and m.data_local between v_inicio and v_fim
      and m.data_local<v_hoje
    group by m.funcionario_id,f.nome,f.matricula,m.data_local
    having count(*) between 1 and 3
  )
  select
    count(*)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'funcionario_id',j.funcionario_id,
          'funcionario_nome',j.funcionario_nome,
          'matricula',j.matricula,
          'data_local',j.data_local,
          'quantidade_marcacoes',j.quantidade_marcacoes,
          'marcacao_faltante',j.marcacao_faltante,
          'marcacao_faltante_label',public.rotulo_marcacao_jornada(j.marcacao_faltante)
        )
        order by j.data_local,j.funcionario_nome
      ),
      '[]'::jsonb
    )
    into v_jornadas,v_jornadas_detalhes
  from jornadas j;

  if to_regclass('public.solicitacoes_ajuste') is not null then
    execute
      'select count(*) from public.solicitacoes_ajuste
       where empresa_id=$1
         and data_marcacao between $2 and $3
         and status=''pendente'''
    into v_ajustes
    using v_empresa,v_inicio,v_fim;
  end if;

  if to_regclass('public.marcacoes_contingencia') is not null then
    execute
      'select count(*) from public.marcacoes_contingencia
       where empresa_id=$1
         and data_local between $2 and $3
         and status in (''pendente'',''conflitante'')'
    into v_contingencias
    using v_empresa,v_inicio,v_fim;
  end if;

  if to_regclass('public.movimentacoes_jornada') is not null then
    execute
      'select count(*) from public.movimentacoes_jornada
       where empresa_id=$1
         and data_local between $2 and $3
         and (status=''aberta'' or fim_em is null)'
    into v_movimentacoes
    using v_empresa,v_inicio,v_fim;
  end if;

  return jsonb_build_object(
    'ano',p_ano,
    'mes',p_mes,
    'inicio',v_inicio,
    'fim',v_fim,
    'jornadas_incompletas',coalesce(v_jornadas,0),
    'jornadas_detalhes',coalesce(v_jornadas_detalhes,'[]'::jsonb),
    'ajustes_pendentes',coalesce(v_ajustes,0),
    'contingencias_pendentes',coalesce(v_contingencias,0),
    'movimentacoes_abertas',coalesce(v_movimentacoes,0),
    'total_bloqueios',coalesce(v_jornadas,0)+coalesce(v_ajustes,0)+coalesce(v_contingencias,0)+coalesce(v_movimentacoes,0),
    'pronta',(coalesce(v_jornadas,0)+coalesce(v_ajustes,0)+coalesce(v_contingencias,0)+coalesce(v_movimentacoes,0))=0,
    'auditada_em',clock_timestamp()
  );
end;
$$;

revoke all on function public.auditar_competencia_admin(integer,integer) from public,anon;
grant execute on function public.auditar_competencia_admin(integer,integer) to authenticated;

commit;
notify pgrst,'reload schema';
