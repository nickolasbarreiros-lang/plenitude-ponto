-- Plenitude Ponto RC5.45
-- Corrige a jornada semanal da funcionária matrícula 001 e torna o cálculo
-- explícito: segunda=1 ... domingo=7 (ISO).

begin;

-- 1) Garante a escala informada para a funcionária de matrícula 001.
do $$
declare
  v_empresa uuid;
  v_funcionario uuid;
  v_nome text;
  v_matricula text;
begin
  -- O SQL Editor do Supabase não executa com a sessão do administrador do site.
  -- Por isso, não usamos empresa_do_usuario() nesta migração.
  select
    f.id,
    f.empresa_id,
    f.nome,
    f.matricula
  into
    v_funcionario,
    v_empresa,
    v_nome,
    v_matricula
  from public.funcionarios f
  where upper(trim(f.nome))='ROSELI DAS NEVES FEITOSA'
  order by f.ativo desc, f.criado_em desc nulls last
  limit 1;

  -- Plano alternativo: matrícula equivalente a 1, aceitando 1, 01, 001 etc.
  if v_funcionario is null then
    select
      f.id,
      f.empresa_id,
      f.nome,
      f.matricula
    into
      v_funcionario,
      v_empresa,
      v_nome,
      v_matricula
    from public.funcionarios f
    where regexp_replace(coalesce(f.matricula,''),'^0+','')='1'
    order by f.ativo desc, f.criado_em desc nulls last
    limit 1;
  end if;

  if v_funcionario is null then
    raise notice
      'Roseli não foi localizada automaticamente. A função de cálculo será atualizada, mas a escala deverá ser salva novamente pelo menu Funcionário.';
  else
    insert into public.jornadas(
      empresa_id,
      funcionario_id,
      dia_semana,
      entrada,
      inicio_intervalo,
      fim_intervalo,
      saida,
      ativo
    )
    values
      (v_empresa,v_funcionario,1,'09:00','13:00','13:30','19:00',true),
      (v_empresa,v_funcionario,2,'09:00','13:00','13:30','19:00',true),
      (v_empresa,v_funcionario,3,'09:00','13:00','13:30','18:00',true),
      (v_empresa,v_funcionario,4,'09:00','13:00','13:30','18:30',true),
      (v_empresa,v_funcionario,5,'09:00','13:00','13:30','17:00',true)
    on conflict (funcionario_id,dia_semana)
    do update set
      empresa_id=excluded.empresa_id,
      entrada=excluded.entrada,
      inicio_intervalo=excluded.inicio_intervalo,
      fim_intervalo=excluded.fim_intervalo,
      saida=excluded.saida,
      ativo=true;

    raise notice
      'Jornada atualizada para % (matrícula %).',
      v_nome,
      coalesce(v_matricula,'sem matrícula');
  end if;
end;
$$;

-- 2) Cálculo mensal corrigido e com diagnóstico de jornada.
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
  v_empresa public.empresas%rowtype;
  v_jornada public.jornadas%rowtype;
  v_feriado public.feriados_empresa%rowtype;
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
  v_total_previsto integer := 0;
  v_total_trabalhado integer := 0;
  v_total_saldo integer := 0;
  v_total_positivo integer := 0;
  v_total_negativo integer := 0;
  v_dias_trabalhados integer := 0;
  v_faltas integer := 0;
  v_pendencias integer := 0;
  v_dias_com_jornada integer := 0;
  v_timezone text := 'America/Sao_Paulo';
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Período inválido.';
  end if;

  select *
    into v_funcionario
  from public.funcionarios f
  where f.id=p_funcionario_id;

  if v_funcionario.id is null then
    raise exception 'Funcionário não encontrado.';
  end if;

  select *
    into v_empresa
  from public.empresas e
  where e.id=v_funcionario.empresa_id;

  v_timezone:=coalesce(v_empresa.timezone,'America/Sao_Paulo');

  for v_dia in
    select gs::date as data
    from generate_series(
      p_inicio::timestamp,
      p_fim::timestamp,
      interval '1 day'
    ) gs
    order by gs
  loop
    v_jornada:=null;

    -- O cadastro da aplicação usa ISO: segunda=1 ... domingo=7.
    select j.*
      into v_jornada
    from public.jornadas j
    where j.funcionario_id=p_funcionario_id
      and j.dia_semana=extract(isodow from v_dia.data)::smallint
      and j.ativo=true
    limit 1;

    if v_jornada.id is null or v_jornada.entrada is null then
      v_previsto:=0;
    else
      v_previsto:=round(
        extract(epoch from (
          (v_jornada.inicio_intervalo-v_jornada.entrada)+
          (v_jornada.saida-v_jornada.fim_intervalo)
        ))/60
      )::integer;
      v_dias_com_jornada:=v_dias_com_jornada+1;
    end if;

    v_feriado:=null;
    if to_regclass('public.feriados_empresa') is not null then
      select fe.*
        into v_feriado
      from public.feriados_empresa fe
      where fe.empresa_id=v_funcionario.empresa_id
        and fe.data=v_dia.data
        and fe.ativo=true
      limit 1;
    end if;

    v_ocorrencia:=null;
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

    if v_ocorrencia in ('folga','ferias','feriado','atestado') then
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
        greatest(
          0,
          round(extract(epoch from (v_horarios[2]-v_horarios[1]))/60)::integer
        );
    end if;

    if v_count>=4 then
      v_trabalhado:=v_trabalhado+
        greatest(
          0,
          round(extract(epoch from (v_horarios[4]-v_horarios[3]))/60)::integer
        );
    end if;

    -- Quatro marcações representam um dia efetivamente trabalhado,
    -- mesmo em feriado ou dia extraordinário.
    if v_count>=4 then
      v_dias_trabalhados:=v_dias_trabalhados+1;
    end if;

    if v_feriado.id is not null then
      if v_count>=4 then
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
      elsif v_count between 1 and 3 then
        v_status:='pendente';
        v_pendencias:=v_pendencias+1;
      else
        v_saldo:=0;
        v_status:='feriado';
      end if;

    elsif v_ocorrencia in ('folga','ferias','atestado') then
      v_status:=v_ocorrencia;
      v_saldo:=case when v_count>=4 then v_trabalhado else 0 end;

    elsif v_previsto=0 then
      if v_count>=4 then
        v_status:='extra';
        v_saldo:=v_trabalhado;
      elsif v_count between 1 and 3 then
        v_status:='pendente';
        v_pendencias:=v_pendencias+1;
      else
        v_status:='sem_jornada';
        v_saldo:=0;
      end if;

    elsif v_count>=4 then
      v_status:='completo';
      v_saldo:=v_trabalhado-v_previsto;

    elsif v_dia.data<(clock_timestamp() at time zone v_timezone)::date
      and v_count=0 then
      v_status:='falta';
      v_saldo:=-v_previsto;
      v_faltas:=v_faltas+1;

    elsif v_dia.data<=(clock_timestamp() at time zone v_timezone)::date
      and v_count between 1 and 3 then
      v_status:='pendente';
      v_pendencias:=v_pendencias+1;

    elsif v_dia.data=(clock_timestamp() at time zone v_timezone)::date then
      v_status:='aguardando';
    else
      v_status:='futuro';
    end if;

    if v_dia.data<=(clock_timestamp() at time zone v_timezone)::date then
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
      'jornada_encontrada',v_jornada.id is not null,
      'previsto_minutos',v_previsto,
      'trabalhado_minutos',v_trabalhado,
      'saldo_minutos',v_saldo,
      'quantidade_marcacoes',v_count,
      'status',v_status,
      'ocorrencia',v_ocorrencia,
      'feriado',case
        when v_feriado.id is null then null
        else jsonb_build_object(
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
    'pendencias',v_pendencias,
    'dias_com_jornada',v_dias_com_jornada,
    'jornada_cadastrada',v_dias_com_jornada>0
  );

  return jsonb_build_object(
    'resumo',v_resumo,
    'dias',v_dias
  );
end;
$$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date)
  from public,anon,authenticated;

-- As funções públicas banco_horas_admin e banco_horas_funcionario_token
-- continuam chamando esta função interna.

commit;

notify pgrst,'reload schema';
