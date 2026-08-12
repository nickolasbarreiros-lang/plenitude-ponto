begin;

-- Plenitude Ponto 1.0.0 RC2.3
-- Proteção contra duplo clique, múltiplas abas e chamadas concorrentes.
--
-- Camadas:
-- 1) pg_advisory_xact_lock serializa marcações do mesmo funcionário;
-- 2) janela mínima de 5 segundos recusa marcações consecutivas;
-- 3) o frontend mantém o botão bloqueado e mostra contagem regressiva.

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
begin
  v_funcionario := public.funcionario_por_token(p_token);

  -- Uma única transação por funcionário pode calcular/inserir a próxima etapa.
  perform pg_advisory_xact_lock(hashtextextended(v_funcionario.id::text, 20260730));

  select max(m.registrado_em)
    into v_ultima_marcacao
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  if v_ultima_marcacao is not null
     and v_agora - v_ultima_marcacao < interval '5 seconds' then
    raise exception 'Aguarde alguns segundos antes de registrar novamente.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes as m
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

  insert into public.marcacoes as m (
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'pin'
  )
  returning m.* into v_marcacao;

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
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto as d
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

  -- Protege também chamadas simultâneas vindas de duas abas/navegadores.
  perform pg_advisory_xact_lock(hashtextextended(v_funcionario.id::text, 20260730));

  select max(m.registrado_em)
    into v_ultima_marcacao
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  if v_ultima_marcacao is not null
     and v_agora - v_ultima_marcacao < interval '5 seconds' then
    raise exception 'Aguarde alguns segundos antes de registrar novamente.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes as m
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

  insert into public.marcacoes as m (
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'dispositivo'
  )
  returning m.* into v_marcacao;

  update public.dispositivos_ponto as d
     set ultimo_uso_em = v_agora
   where d.id = v_dispositivo.id;

  return v_marcacao;
end;
$$;

revoke all on function public.registrar_ponto_com_pin(text)
from public, anon, authenticated;

revoke all on function public.registrar_ponto_dispositivo(text,text,text)
from public;

grant execute on function public.registrar_ponto_dispositivo(text,text,text)
to anon, authenticated;

commit;

notify pgrst, 'reload schema';
