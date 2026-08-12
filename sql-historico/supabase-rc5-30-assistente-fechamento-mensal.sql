-- Plenitude Ponto RC5.30
-- Auditoria obrigatória e bloqueio inteligente do fechamento mensal.

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
  v_jornadas integer:=0;
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

  -- Jornadas incompletas: qualquer dia da competência com 1 a 3 marcações.
  select count(*)
    into v_jornadas
  from (
    select m.funcionario_id,m.data_local
    from public.marcacoes m
    join public.funcionarios f on f.id=m.funcionario_id
    where f.empresa_id=v_empresa
      and m.data_local between v_inicio and v_fim
      and m.data_local<current_date
    group by m.funcionario_id,m.data_local
    having count(*) between 1 and 3
  ) jornadas;

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
    'ajustes_pendentes',coalesce(v_ajustes,0),
    'contingencias_pendentes',coalesce(v_contingencias,0),
    'movimentacoes_abertas',coalesce(v_movimentacoes,0),
    'total_bloqueios',
      coalesce(v_jornadas,0)+
      coalesce(v_ajustes,0)+
      coalesce(v_contingencias,0)+
      coalesce(v_movimentacoes,0),
    'pronta',
      (
       coalesce(v_jornadas,0)+
       coalesce(v_ajustes,0)+
       coalesce(v_contingencias,0)+
       coalesce(v_movimentacoes,0)
      )=0,
    'auditada_em',clock_timestamp()
  );
end;
$$;

-- Defesa no servidor: não depende apenas do botão do navegador.
create or replace function public.fechar_competencia_master_admin(
  p_ano integer,
  p_mes integer,
  p_observacao text default null,
  p_master_pin text default null
)
returns public.fechamentos_mensais
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result public.fechamentos_mensais%rowtype;
  v_audit jsonb;
  v_total integer;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso negado.';
  end if;

  perform public.validar_pin_mestre_interno(
    public.empresa_do_usuario(),
    p_master_pin
  );

  v_audit:=public.auditar_competencia_admin(p_ano,p_mes);
  v_total:=coalesce((v_audit->>'total_bloqueios')::integer,0);

  if v_total>0 then
    raise exception
      'Fechamento bloqueado: existem % pendências na competência. Jornadas incompletas: %, ajustes: %, contingências: %, saídas temporárias: %.',
      v_total,
      v_audit->>'jornadas_incompletas',
      v_audit->>'ajustes_pendentes',
      v_audit->>'contingencias_pendentes',
      v_audit->>'movimentacoes_abertas';
  end if;

  v_result:=public.fechar_competencia_admin(
    p_ano,
    p_mes,
    p_observacao
  );

  return v_result;
end;
$$;

revoke all on function public.auditar_competencia_admin(integer,integer)
  from public,anon;

grant execute on function public.auditar_competencia_admin(integer,integer)
  to authenticated;

revoke all on function public.fechar_competencia_master_admin(
  integer,integer,text,text
) from public,anon;

grant execute on function public.fechar_competencia_master_admin(
  integer,integer,text,text
) to authenticated;

commit;

notify pgrst,'reload schema';
