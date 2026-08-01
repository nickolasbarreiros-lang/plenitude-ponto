-- Plenitude Ponto RC5.43
-- Calendário de feriados nacionais, estaduais, municipais e internos.

begin;

create table if not exists public.feriados_empresa (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  data date not null,
  nome text not null,
  abrangencia text not null default 'empresa'
    check (abrangencia in ('nacional','estadual','municipal','empresa','facultativo')),
  regra_trabalho text not null default 'banco_simples'
    check (regra_trabalho in ('banco_simples','banco_dobro','folha','normal')),
  reduz_carga boolean not null default true,
  ativo boolean not null default true,
  observacao text,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default clock_timestamp(),
  atualizado_em timestamptz not null default clock_timestamp(),
  unique (empresa_id,data)
);

create index if not exists idx_feriados_empresa_data
  on public.feriados_empresa(empresa_id,data);

alter table public.feriados_empresa enable row level security;

drop policy if exists feriados_empresa_select_admin on public.feriados_empresa;
create policy feriados_empresa_select_admin
on public.feriados_empresa
for select
to authenticated
using (
  empresa_id=public.empresa_do_usuario()
  and public.usuario_e_admin()
);

create or replace function public.listar_feriados_empresa_admin(
  p_inicio date,
  p_fim date
)
returns setof public.feriados_empresa
language sql
security definer
set search_path=public
as $$
  select fe.*
  from public.feriados_empresa fe
  where public.usuario_e_admin()
    and fe.empresa_id=public.empresa_do_usuario()
    and fe.data between p_inicio and p_fim
  order by fe.data,fe.nome;
$$;

create or replace function public.salvar_feriado_empresa_admin(
  p_id uuid,
  p_data date,
  p_nome text,
  p_abrangencia text,
  p_regra_trabalho text,
  p_reduz_carga boolean,
  p_ativo boolean,
  p_observacao text default null
)
returns public.feriados_empresa
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_result public.feriados_empresa%rowtype;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  if p_data is null or length(trim(coalesce(p_nome,'')))<2 then
    raise exception 'Informe a data e o nome do feriado.';
  end if;

  if p_abrangencia not in ('nacional','estadual','municipal','empresa','facultativo') then
    raise exception 'Abrangência inválida.';
  end if;

  if p_regra_trabalho not in ('banco_simples','banco_dobro','folha','normal') then
    raise exception 'Regra de trabalho inválida.';
  end if;

  if p_id is null then
    insert into public.feriados_empresa(
      empresa_id,data,nome,abrangencia,regra_trabalho,
      reduz_carga,ativo,observacao,criado_por
    )
    values(
      v_empresa,p_data,trim(p_nome),p_abrangencia,p_regra_trabalho,
      coalesce(p_reduz_carga,true),coalesce(p_ativo,true),
      nullif(trim(coalesce(p_observacao,'')),''),auth.uid()
    )
    on conflict (empresa_id,data)
    do update set
      nome=excluded.nome,
      abrangencia=excluded.abrangencia,
      regra_trabalho=excluded.regra_trabalho,
      reduz_carga=excluded.reduz_carga,
      ativo=excluded.ativo,
      observacao=excluded.observacao,
      atualizado_em=clock_timestamp()
    returning * into v_result;
  else
    update public.feriados_empresa fe
       set data=p_data,
           nome=trim(p_nome),
           abrangencia=p_abrangencia,
           regra_trabalho=p_regra_trabalho,
           reduz_carga=coalesce(p_reduz_carga,true),
           ativo=coalesce(p_ativo,true),
           observacao=nullif(trim(coalesce(p_observacao,'')),''),
           atualizado_em=clock_timestamp()
     where fe.id=p_id
       and fe.empresa_id=v_empresa
     returning * into v_result;
  end if;

  if v_result.id is null then
    raise exception 'Feriado não encontrado.';
  end if;

  return v_result;
end;
$$;

create or replace function public.excluir_feriado_empresa_admin(
  p_id uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  delete from public.feriados_empresa fe
  where fe.id=p_id
    and fe.empresa_id=public.empresa_do_usuario();
end;
$$;

create or replace function public.gerar_feriados_padrao_serra_admin(
  p_ano integer
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_inseridos integer:=0;
  v_row record;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if p_ano not between 2020 and 2100 then
    raise exception 'Ano inválido.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  for v_row in
    select *
    from (
      values
        (make_date(p_ano,1,1),'Confraternização Universal','nacional','banco_simples',true,true),
        (make_date(p_ano,4,3),'Paixão de Cristo','nacional','banco_simples',true,true),
        (make_date(p_ano,4,13),'Nossa Senhora da Penha','estadual','banco_simples',true,true),
        (make_date(p_ano,4,21),'Tiradentes','nacional','banco_simples',true,true),
        (make_date(p_ano,5,1),'Dia do Trabalho','nacional','banco_simples',true,true),
        (make_date(p_ano,6,29),'São Pedro','municipal','banco_simples',true,true),
        (make_date(p_ano,9,7),'Independência do Brasil','nacional','banco_simples',true,true),
        (make_date(p_ano,10,12),'Nossa Senhora Aparecida','nacional','banco_simples',true,true),
        (make_date(p_ano,11,2),'Finados','nacional','banco_simples',true,true),
        (make_date(p_ano,11,15),'Proclamação da República','nacional','banco_simples',true,true),
        (make_date(p_ano,11,20),'Consciência Negra','nacional','banco_simples',true,true),
        (make_date(p_ano,12,8),'Nossa Senhora da Conceição','municipal','banco_simples',true,true),
        (make_date(p_ano,12,25),'Natal','nacional','banco_simples',true,true),
        (make_date(p_ano,12,26),'Dia do Serrano','municipal','banco_simples',true,true),
        (make_date(p_ano,2,16),'Carnaval — segunda-feira','facultativo','normal',false,false),
        (make_date(p_ano,2,17),'Carnaval — terça-feira','facultativo','normal',false,false),
        (make_date(p_ano,2,18),'Quarta-feira de Cinzas','facultativo','normal',false,false),
        (make_date(p_ano,6,4),'Corpus Christi','facultativo','normal',false,false),
        (make_date(p_ano,12,24),'Véspera de Natal','facultativo','normal',false,false),
        (make_date(p_ano,12,31),'Véspera de Ano-Novo','facultativo','normal',false,false)
    ) as x(data,nome,abrangencia,regra,reduz,ativo)
  loop
    insert into public.feriados_empresa(
      empresa_id,data,nome,abrangencia,regra_trabalho,
      reduz_carga,ativo,observacao,criado_por
    )
    values(
      v_empresa,v_row.data,v_row.nome,v_row.abrangencia,v_row.regra,
      v_row.reduz,v_row.ativo,
      'Calendário padrão Serra/ES. Confirme a aplicabilidade à empresa.',
      auth.uid()
    )
    on conflict (empresa_id,data) do nothing;

    if found then
      v_inseridos:=v_inseridos+1;
    end if;
  end loop;

  return jsonb_build_object(
    'ano',p_ano,
    'inseridos',v_inseridos
  );
end;
$$;

-- Banco de horas atualizado para consultar o calendário da empresa.
create or replace function public._calcular_banco_horas_json(
  p_funcionario_id uuid,
  p_inicio date,
  p_fim date
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_dias jsonb := '[]'::jsonb;
  v_resumo jsonb;
  v_dia record;
  v_previsto integer;
  v_trabalhado integer;
  v_saldo integer;
  v_count integer;
  v_tipos public.tipo_marcacao[];
  v_horarios timestamptz[];
  v_ocorrencia text;
  v_status text;
  v_feriado public.feriados_empresa%rowtype;
  v_total_previsto integer := 0;
  v_total_trabalhado integer := 0;
  v_total_saldo integer := 0;
  v_total_positivo integer := 0;
  v_total_negativo integer := 0;
  v_dias_trabalhados integer := 0;
  v_faltas integer := 0;
  v_pendencias integer := 0;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Período inválido.';
  end if;

  select * into v_funcionario
  from public.funcionarios
  where id = p_funcionario_id;

  if v_funcionario.id is null then
    raise exception 'Funcionário não encontrado.';
  end if;

  for v_dia in
    select gs::date as data
    from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs
    order by gs
  loop
    select
      case
        when j.id is null or j.ativo is false or j.entrada is null then 0
        else round(extract(epoch from (
          (j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)
        ))/60)::integer
      end
    into v_previsto
    from (select 1) x
    left join public.jornadas j
      on j.funcionario_id=p_funcionario_id
     and j.dia_semana=extract(isodow from v_dia.data)::smallint
    limit 1;

    v_feriado:=null;

    select fe.*
      into v_feriado
    from public.feriados_empresa fe
    where fe.empresa_id=v_funcionario.empresa_id
      and fe.data=v_dia.data
      and fe.ativo=true
    limit 1;

    select o.tipo::text
      into v_ocorrencia
    from public.ocorrencias o
    where o.funcionario_id=p_funcionario_id
      and o.aprovado=true
      and v_dia.data between o.data_inicio and o.data_fim
    order by o.criado_em desc
    limit 1;

    if v_feriado.id is not null and v_feriado.reduz_carga then
      v_previsto:=0;
    end if;

    if v_ocorrencia in ('folga','ferias','atestado') then
      v_previsto:=0;
    end if;

    select
      count(*)::integer,
      array_agg(m.tipo order by m.registrado_em),
      array_agg(m.registrado_em order by m.registrado_em)
    into v_count,v_tipos,v_horarios
    from public.marcacoes m
    where m.funcionario_id=p_funcionario_id
      and m.data_local=v_dia.data;

    v_trabalhado:=0;
    v_saldo:=null;

    if v_count>=2 then
      v_trabalhado:=v_trabalhado+
        greatest(0,round(extract(epoch from (v_horarios[2]-v_horarios[1]))/60)::integer);
    end if;

    if v_count>=4 then
      v_trabalhado:=v_trabalhado+
        greatest(0,round(extract(epoch from (v_horarios[4]-v_horarios[3]))/60)::integer);
    end if;

    if v_feriado.id is not null then
      if v_count=4 then
        case v_feriado.regra_trabalho
          when 'banco_dobro' then
            v_saldo:=v_trabalhado*2;
            v_status:='feriado_banco_dobro';
          when 'folha' then
            v_saldo:=0;
            v_status:='feriado_folha';
          when 'normal' then
            v_saldo:=v_trabalhado-v_previsto;
            v_status:='completo';
          else
            v_saldo:=v_trabalhado;
            v_status:='feriado_trabalhado';
        end case;
        v_dias_trabalhados:=v_dias_trabalhados+1;
      elsif v_count between 1 and 3 then
        v_status:='pendente';
        v_pendencias:=v_pendencias+1;
      else
        v_saldo:=0;
        v_status:='feriado';
      end if;
    elsif v_ocorrencia in ('folga','ferias','atestado') then
      v_status:=v_ocorrencia;
      v_saldo:=case when v_count=4 then v_trabalhado else 0 end;
    elsif v_previsto=0 then
      v_status:=case when v_count>0 then 'extra' else 'sem_jornada' end;
      v_saldo:=case when v_count=4 then v_trabalhado else 0 end;
    elsif v_count=4 then
      v_status:='completo';
      v_saldo:=v_trabalhado-v_previsto;
      v_dias_trabalhados:=v_dias_trabalhados+1;
    elsif v_dia.data<(clock_timestamp() at time zone 'America/Sao_Paulo')::date
      and v_count=0 then
      v_status:='falta';
      v_saldo:=-v_previsto;
      v_faltas:=v_faltas+1;
    elsif v_dia.data<=(clock_timestamp() at time zone 'America/Sao_Paulo')::date
      and v_count between 1 and 3 then
      v_status:='pendente';
      v_pendencias:=v_pendencias+1;
    elsif v_dia.data=(clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      v_status:='aguardando';
    else
      v_status:='futuro';
    end if;

    if v_dia.data<=(clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      v_total_previsto:=v_total_previsto+v_previsto;
      v_total_trabalhado:=v_total_trabalhado+v_trabalhado;

      if v_saldo is not null then
        v_total_saldo:=v_total_saldo+v_saldo;

        if v_saldo>0 then
          v_total_positivo:=v_total_positivo+v_saldo;
        elsif v_saldo<0 then
          v_total_negativo:=v_total_negativo+abs(v_saldo);
        end if;
      end if;
    end if;

    v_dias:=v_dias||jsonb_build_array(jsonb_build_object(
      'data',v_dia.data,
      'dia_semana',extract(isodow from v_dia.data)::integer,
      'previsto_minutos',v_previsto,
      'trabalhado_minutos',v_trabalhado,
      'saldo_minutos',v_saldo,
      'quantidade_marcacoes',v_count,
      'status',v_status,
      'ocorrencia',v_ocorrencia,
      'feriado',case when v_feriado.id is null then null else
        jsonb_build_object(
          'id',v_feriado.id,
          'nome',v_feriado.nome,
          'abrangencia',v_feriado.abrangencia,
          'regra_trabalho',v_feriado.regra_trabalho,
          'reduz_carga',v_feriado.reduz_carga
        )
      end,
      'marcacoes',coalesce(to_jsonb(v_horarios),'[]'::jsonb),
      'tipos',coalesce(to_jsonb(v_tipos),'[]'::jsonb)
    ));
  end loop;

  v_resumo:=jsonb_build_object(
    'funcionario_id',v_funcionario.id,
    'funcionario_nome',v_funcionario.nome,
    'matricula',v_funcionario.matricula,
    'inicio',p_inicio,
    'fim',p_fim,
    'previsto_minutos',v_total_previsto,
    'trabalhado_minutos',v_total_trabalhado,
    'saldo_minutos',v_total_saldo,
    'credito_minutos',v_total_positivo,
    'debito_minutos',v_total_negativo,
    'dias_trabalhados',v_dias_trabalhados,
    'faltas',v_faltas,
    'pendencias',v_pendencias
  );

  return jsonb_build_object('resumo',v_resumo,'dias',v_dias);
end;
$$;

revoke all on function public.listar_feriados_empresa_admin(date,date)
  from public,anon;
grant execute on function public.listar_feriados_empresa_admin(date,date)
  to authenticated;

revoke all on function public.salvar_feriado_empresa_admin(
  uuid,date,text,text,text,boolean,boolean,text
) from public,anon;
grant execute on function public.salvar_feriado_empresa_admin(
  uuid,date,text,text,text,boolean,boolean,text
) to authenticated;

revoke all on function public.excluir_feriado_empresa_admin(uuid)
  from public,anon;
grant execute on function public.excluir_feriado_empresa_admin(uuid)
  to authenticated;

revoke all on function public.gerar_feriados_padrao_serra_admin(integer)
  from public,anon;
grant execute on function public.gerar_feriados_padrao_serra_admin(integer)
  to authenticated;

commit;

notify pgrst,'reload schema';
