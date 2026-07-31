begin;

-- RC4.18 — intervalo mínimo obrigatório de 30 minutos
--
-- Regra:
-- depois de registrar "Início do almoço", o "Retorno do almoço"
-- só pode ser registrado após pelo menos 30 minutos.
--
-- A validação é feita no servidor e vale para todos os computadores.

update public.empresas
set intervalo_minimo_minutos = 30
where intervalo_minimo_minutos is distinct from 30;

alter table public.empresas
  alter column intervalo_minimo_minutos set default 30;

alter table public.empresas
  drop constraint if exists empresas_intervalo_check;

alter table public.empresas
  add constraint empresas_intervalo_check
  check (
    intervalo_minimo_minutos between 30 and intervalo_maximo_minutos
    and intervalo_maximo_minutos <= 360
  );

create or replace function public.salvar_politicas_ponto(
  p_tolerancia_entrada integer,
  p_tolerancia_saida integer,
  p_intervalo_minimo integer,
  p_intervalo_maximo integer,
  p_horas_extras_automaticas boolean,
  p_limite_banco_horas integer
)
returns public.empresas
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_result public.empresas%rowtype;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if p_tolerancia_entrada not between 0 and 120
     or p_tolerancia_saida not between 0 and 120 then
    raise exception 'As tolerâncias devem ficar entre 0 e 120 minutos.';
  end if;

  if p_intervalo_minimo < 30 then
    raise exception 'O intervalo mínimo de almoço não pode ser inferior a 30 minutos.';
  end if;

  if p_intervalo_maximo < p_intervalo_minimo
     or p_intervalo_maximo > 360 then
    raise exception 'Configuração de intervalo inválida.';
  end if;

  update public.empresas
     set tolerancia_entrada_minutos = p_tolerancia_entrada,
         tolerancia_saida_minutos = p_tolerancia_saida,
         intervalo_minimo_minutos = p_intervalo_minimo,
         intervalo_maximo_minutos = p_intervalo_maximo,
         horas_extras_automaticas = p_horas_extras_automaticas,
         limite_banco_horas_minutos = p_limite_banco_horas,
         atualizada_em = clock_timestamp()
   where id = v_empresa
  returning * into v_result;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    acao,
    tabela,
    registro_id,
    dados_novos
  )
  values(
    v_empresa,
    auth.uid(),
    'POLITICAS_PONTO_ATUALIZADAS',
    'empresas',
    v_empresa,
    jsonb_build_object(
      'tolerancia_entrada', p_tolerancia_entrada,
      'tolerancia_saida', p_tolerancia_saida,
      'intervalo_minimo', p_intervalo_minimo,
      'intervalo_maximo', p_intervalo_maximo,
      'horas_extras_automaticas', p_horas_extras_automaticas,
      'limite_banco_horas', p_limite_banco_horas
    )
  );

  return v_result;
end;
$$;

create or replace function public.registrar_ponto_com_pin(p_token text)
returns public.marcacoes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_agora timestamptz := clock_timestamp();
  v_data date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_ultima_marcacao timestamptz;
  v_inicio_intervalo timestamptz;
  v_intervalo_minimo integer := 30;
  v_restante integer;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  perform pg_advisory_xact_lock(
    hashtextextended(v_funcionario.id::text, 20260730)
  );

  select max(m.registrado_em)
    into v_ultima_marcacao
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  if v_ultima_marcacao is not null
     and v_agora - v_ultima_marcacao < interval '5 seconds' then
    raise exception 'Aguarde alguns segundos antes de registrar novamente.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  if v_tipo = 'fim_intervalo'::public.tipo_marcacao then
    select m.registrado_em
      into v_inicio_intervalo
    from public.marcacoes m
    where m.funcionario_id = v_funcionario.id
      and m.data_local = v_data
      and m.tipo = 'inicio_intervalo'::public.tipo_marcacao
    order by m.registrado_em desc
    limit 1;

    select greatest(30, coalesce(e.intervalo_minimo_minutos, 30))
      into v_intervalo_minimo
    from public.empresas e
    where e.id = v_funcionario.empresa_id;

    v_restante := ceil(
      extract(epoch from (
        v_inicio_intervalo
        + make_interval(mins => v_intervalo_minimo)
        - v_agora
      )) / 60.0
    )::integer;

    if v_inicio_intervalo is not null and v_restante > 0 then
      raise exception
        'O retorno do almoço só pode ser registrado após % minutos. Aguarde mais % minuto(s).',
        v_intervalo_minimo,
        v_restante;
    end if;
  end if;

  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values(
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'pin'
  )
  returning * into v_marcacao;

  return v_marcacao;
end;
$$;

create or replace function public.registrar_ponto_dispositivo(
  p_token text,
  p_dispositivo_token text,
  p_user_agent text default null
)
returns public.marcacoes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_agora timestamptz := clock_timestamp();
  v_data date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_ultima_marcacao timestamptz;
  v_inicio_intervalo timestamptz;
  v_intervalo_minimo integer := 30;
  v_restante integer;
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash =
        encode(extensions.digest(coalesce(p_dispositivo_token, ''), 'sha256'), 'hex')
    and d.ativo = true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Registro bloqueado: computador não autorizado.';
  end if;

  v_funcionario := public.funcionario_por_token(p_token);

  if v_funcionario.empresa_id <> v_dispositivo.empresa_id then
    raise exception 'Dispositivo não autorizado para esta empresa.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_funcionario.id::text, 20260730)
  );

  select max(m.registrado_em)
    into v_ultima_marcacao
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  if v_ultima_marcacao is not null
     and v_agora - v_ultima_marcacao < interval '5 seconds' then
    raise exception 'Aguarde alguns segundos antes de registrar novamente.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  if v_tipo = 'fim_intervalo'::public.tipo_marcacao then
    select m.registrado_em
      into v_inicio_intervalo
    from public.marcacoes m
    where m.funcionario_id = v_funcionario.id
      and m.data_local = v_data
      and m.tipo = 'inicio_intervalo'::public.tipo_marcacao
    order by m.registrado_em desc
    limit 1;

    select greatest(30, coalesce(e.intervalo_minimo_minutos, 30))
      into v_intervalo_minimo
    from public.empresas e
    where e.id = v_funcionario.empresa_id;

    v_restante := ceil(
      extract(epoch from (
        v_inicio_intervalo
        + make_interval(mins => v_intervalo_minimo)
        - v_agora
      )) / 60.0
    )::integer;

    if v_inicio_intervalo is not null and v_restante > 0 then
      raise exception
        'O retorno do almoço só pode ser registrado após % minutos. Aguarde mais % minuto(s).',
        v_intervalo_minimo,
        v_restante;
    end if;
  end if;

  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values(
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'dispositivo'
  )
  returning * into v_marcacao;

  update public.dispositivos_ponto
     set ultimo_uso_em = v_agora
   where id = v_dispositivo.id;

  return v_marcacao;
end;
$$;

revoke all on function public.registrar_ponto_com_pin(text)
from public, anon, authenticated;

revoke all on function public.registrar_ponto_dispositivo(text,text,text)
from public;

grant execute on function public.registrar_ponto_dispositivo(text,text,text)
to anon, authenticated;

grant execute on function public.salvar_politicas_ponto(
  integer,integer,integer,integer,boolean,integer
) to authenticated;

commit;

notify pgrst, 'reload schema';
