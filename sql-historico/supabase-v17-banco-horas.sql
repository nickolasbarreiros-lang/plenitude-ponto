-- PLENITUDE PONTO V17 — BANCO DE HORAS AUTOMÁTICO
-- Execute integralmente no SQL Editor do Supabase.

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

  if p_fim - p_inicio > 370 then
    raise exception 'O período máximo permitido é de 370 dias.';
  end if;

  select * into v_funcionario
  from public.funcionarios
  where id = p_funcionario_id;

  if v_funcionario.id is null then
    raise exception 'Funcionário não encontrado.';
  end if;

  for v_dia in
    select gs::date as data
    from generate_series(p_inicio::timestamp, p_fim::timestamp, interval '1 day') gs
    order by gs
  loop
    select
      case
        when j.id is null or j.ativo is false or j.entrada is null then 0
        else round(extract(epoch from (
          (j.inicio_intervalo - j.entrada) +
          (j.saida - j.fim_intervalo)
        )) / 60)::integer
      end
    into v_previsto
    from (select 1) x
    left join public.jornadas j
      on j.funcionario_id = p_funcionario_id
     and j.dia_semana = extract(isodow from v_dia.data)::smallint
    limit 1;

    select o.tipo::text
    into v_ocorrencia
    from public.ocorrencias o
    where o.funcionario_id = p_funcionario_id
      and o.aprovado = true
      and v_dia.data between o.data_inicio and o.data_fim
    order by o.criado_em desc
    limit 1;

    if v_ocorrencia in ('folga','ferias','feriado','atestado') then
      v_previsto := 0;
    end if;

    select
      count(*)::integer,
      array_agg(m.tipo order by m.registrado_em),
      array_agg(m.registrado_em order by m.registrado_em)
    into v_count, v_tipos, v_horarios
    from public.marcacoes m
    where m.funcionario_id = p_funcionario_id
      and m.data_local = v_dia.data;

    v_trabalhado := 0;
    v_saldo := null;

    if v_count >= 2 then
      v_trabalhado := v_trabalhado + greatest(0, round(extract(epoch from (v_horarios[2] - v_horarios[1])) / 60)::integer);
    end if;
    if v_count >= 4 then
      v_trabalhado := v_trabalhado + greatest(0, round(extract(epoch from (v_horarios[4] - v_horarios[3])) / 60)::integer);
    end if;

    if v_ocorrencia in ('folga','ferias','feriado','atestado') then
      v_status := v_ocorrencia;
      v_saldo := case when v_count = 4 then v_trabalhado else 0 end;
    elsif v_previsto = 0 then
      v_status := case when v_count > 0 then 'extra' else 'sem_jornada' end;
      v_saldo := case when v_count = 4 then v_trabalhado else 0 end;
    elsif v_count = 4 then
      v_status := 'completo';
      v_saldo := v_trabalhado - v_previsto;
      v_dias_trabalhados := v_dias_trabalhados + 1;
    elsif v_dia.data < (clock_timestamp() at time zone 'America/Sao_Paulo')::date and v_count = 0 then
      v_status := 'falta';
      v_saldo := -v_previsto;
      v_faltas := v_faltas + 1;
    elsif v_dia.data <= (clock_timestamp() at time zone 'America/Sao_Paulo')::date and v_count between 1 and 3 then
      v_status := 'pendente';
      v_pendencias := v_pendencias + 1;
    elsif v_dia.data = (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      v_status := 'aguardando';
    else
      v_status := 'futuro';
    end if;

    if v_dia.data <= (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      v_total_previsto := v_total_previsto + v_previsto;
      v_total_trabalhado := v_total_trabalhado + v_trabalhado;
      if v_saldo is not null then
        v_total_saldo := v_total_saldo + v_saldo;
        if v_saldo > 0 then
          v_total_positivo := v_total_positivo + v_saldo;
        elsif v_saldo < 0 then
          v_total_negativo := v_total_negativo + abs(v_saldo);
        end if;
      end if;
    end if;

    v_dias := v_dias || jsonb_build_array(jsonb_build_object(
      'data', v_dia.data,
      'dia_semana', extract(isodow from v_dia.data)::integer,
      'previsto_minutos', v_previsto,
      'trabalhado_minutos', v_trabalhado,
      'saldo_minutos', v_saldo,
      'quantidade_marcacoes', v_count,
      'status', v_status,
      'ocorrencia', v_ocorrencia,
      'marcacoes', coalesce(to_jsonb(v_horarios), '[]'::jsonb),
      'tipos', coalesce(to_jsonb(v_tipos), '[]'::jsonb)
    ));
  end loop;

  v_resumo := jsonb_build_object(
    'funcionario_id', v_funcionario.id,
    'funcionario_nome', v_funcionario.nome,
    'matricula', v_funcionario.matricula,
    'inicio', p_inicio,
    'fim', p_fim,
    'previsto_minutos', v_total_previsto,
    'trabalhado_minutos', v_total_trabalhado,
    'saldo_minutos', v_total_saldo,
    'credito_minutos', v_total_positivo,
    'debito_minutos', v_total_negativo,
    'dias_trabalhados', v_dias_trabalhados,
    'faltas', v_faltas,
    'pendencias', v_pendencias
  );

  return jsonb_build_object('resumo', v_resumo, 'dias', v_dias);
end;
$$;

create or replace function public.banco_horas_admin(
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
  v_empresa uuid;
  v_empresa_funcionario uuid;
begin
  select empresa_id into v_empresa
  from public.perfis
  where id = auth.uid()
    and papel = 'administrador'
    and ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  select empresa_id into v_empresa_funcionario
  from public.funcionarios
  where id = p_funcionario_id;

  if v_empresa_funcionario is distinct from v_empresa then
    raise exception 'Funcionário não pertence à sua empresa.';
  end if;

  return public._calcular_banco_horas_json(p_funcionario_id, p_inicio, p_fim);
end;
$$;

create or replace function public.banco_horas_funcionario_token(
  p_token text,
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
begin
  select * into v_funcionario
  from public.funcionario_por_token(p_token);

  return public._calcular_banco_horas_json(v_funcionario.id, p_inicio, p_fim);
end;
$$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date) from public, anon, authenticated;
revoke all on function public.banco_horas_admin(uuid,date,date) from public, anon;
revoke all on function public.banco_horas_funcionario_token(text,date,date) from public;

grant execute on function public.banco_horas_admin(uuid,date,date) to authenticated;
grant execute on function public.banco_horas_funcionario_token(text,date,date) to anon, authenticated;
