-- Plenitude Ponto RC5.60
-- Proteção transacional contra múltiplos cliques e intervalo mínimo do almoço.

begin;

create or replace function public.registrar_ponto_com_pin(p_token text)
returns public.marcacoes
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_empresa public.empresas%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_agora timestamptz:=clock_timestamp();
  v_data date;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_ultima_marcacao timestamptz;
  v_inicio_intervalo timestamptz;
  v_intervalo_minimo integer:=30;
  v_restante_segundos integer;
  v_restante_minutos integer;
begin
  v_funcionario:=public.funcionario_por_token(p_token);

  select *
    into v_empresa
  from public.empresas e
  where e.id=v_funcionario.empresa_id
    and e.ativa=true;

  if v_empresa.id is null then
    raise exception 'Empresa inativa ou não encontrada.';
  end if;

  v_data:=(v_agora at time zone coalesce(v_empresa.timezone,'America/Sao_Paulo'))::date;

  -- Uma única transação por funcionário, inclusive entre abas e computadores.
  perform pg_advisory_xact_lock(
    hashtextextended(v_funcionario.id::text,20260803)
  );

  select
    count(*)::integer,
    max(m.registrado_em)
  into
    v_quantidade,
    v_ultima_marcacao
  from public.marcacoes m
  where m.funcionario_id=v_funcionario.id
    and m.data_local=v_data;

  if v_quantidade>=4 then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  -- Bloqueia requisições repetidas e cliques múltiplos.
  if v_ultima_marcacao is not null
     and v_agora-v_ultima_marcacao<interval '5 seconds' then
    raise exception 'Marcação já recebida. Aguarde alguns segundos antes de tentar novamente.';
  end if;

  v_tipo:=case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  -- Validação estrutural: a sequência já gravada precisa estar íntegra.
  if exists(
    select 1
    from (
      select m.tipo,
             row_number() over(order by m.registrado_em,m.id) as posicao
      from public.marcacoes m
      where m.funcionario_id=v_funcionario.id
        and m.data_local=v_data
    ) sequencia
    where sequencia.tipo<>(
      array[
        'entrada'::public.tipo_marcacao,
        'inicio_intervalo'::public.tipo_marcacao,
        'fim_intervalo'::public.tipo_marcacao,
        'saida'::public.tipo_marcacao
      ]
    )[sequencia.posicao]
  ) then
    raise exception 'A sequência de marcações de hoje está inconsistente. Procure o administrador.';
  end if;

  if v_tipo='fim_intervalo'::public.tipo_marcacao then
    select m.registrado_em
      into v_inicio_intervalo
    from public.marcacoes m
    where m.funcionario_id=v_funcionario.id
      and m.data_local=v_data
      and m.tipo='inicio_intervalo'::public.tipo_marcacao
    order by m.registrado_em desc,m.id desc
    limit 1;

    if v_inicio_intervalo is null then
      raise exception 'Não foi encontrado o início do almoço.';
    end if;

    v_intervalo_minimo:=greatest(
      30,
      coalesce(v_empresa.intervalo_minimo_minutos,30)
    );

    v_restante_segundos:=ceil(
      extract(epoch from(
        v_inicio_intervalo+
        make_interval(mins=>v_intervalo_minimo)-
        v_agora
      ))
    )::integer;

    if v_restante_segundos>0 then
      v_restante_minutos:=ceil(v_restante_segundos/60.0)::integer;
      raise exception
        'Retorno do almoço bloqueado. O intervalo mínimo é de % minutos. Aguarde mais % minuto(s).',
        v_intervalo_minimo,
        v_restante_minutos;
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
set search_path=public,extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash=encode(
      extensions.digest(coalesce(p_dispositivo_token,''),'sha256'),
      'hex'
    )
    and d.ativo=true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Registro bloqueado: computador não autorizado.';
  end if;

  v_funcionario:=public.funcionario_por_token(p_token);

  if v_funcionario.empresa_id<>v_dispositivo.empresa_id then
    raise exception 'Dispositivo não autorizado para esta empresa.';
  end if;

  -- Toda regra crítica fica concentrada na função protegida.
  v_marcacao:=public.registrar_ponto_com_pin(p_token);

  update public.marcacoes
     set origem='dispositivo'
   where id=v_marcacao.id
   returning * into v_marcacao;

  update public.dispositivos_ponto
     set ultimo_uso_em=clock_timestamp()
   where id=v_dispositivo.id;

  return v_marcacao;
end;
$$;


create or replace function public.registrar_ponto_funcionario(
  p_funcionario_id uuid
)
returns public.marcacoes
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_perfil public.perfis%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_empresa public.empresas%rowtype;
  v_resultado public.marcacoes%rowtype;
  v_agora timestamptz:=clock_timestamp();
  v_data date;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_ultima_marcacao timestamptz;
  v_inicio_intervalo timestamptz;
  v_intervalo_minimo integer:=30;
  v_restante_segundos integer;
begin
  select *
    into v_perfil
  from public.perfis p
  where p.id=auth.uid()
    and p.ativo=true;

  if v_perfil.id is null
     or v_perfil.papel<>'administrador'::public.perfil_papel then
    raise exception 'Apenas administradores podem registrar ponto para outro funcionário.';
  end if;

  select *
    into v_funcionario
  from public.funcionarios f
  where f.id=p_funcionario_id
    and f.empresa_id=v_perfil.empresa_id
    and f.ativo=true;

  if v_funcionario.id is null then
    raise exception 'Funcionário ativo não encontrado nesta empresa.';
  end if;

  select *
    into v_empresa
  from public.empresas e
  where e.id=v_funcionario.empresa_id
    and e.ativa=true;

  v_data:=(v_agora at time zone coalesce(v_empresa.timezone,'America/Sao_Paulo'))::date;

  perform pg_advisory_xact_lock(
    hashtextextended(v_funcionario.id::text,20260803)
  );

  select count(*)::integer,max(m.registrado_em)
    into v_quantidade,v_ultima_marcacao
  from public.marcacoes m
  where m.funcionario_id=v_funcionario.id
    and m.data_local=v_data;

  if v_quantidade>=4 then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  if v_ultima_marcacao is not null
     and v_agora-v_ultima_marcacao<interval '5 seconds' then
    raise exception 'Marcação já recebida. Aguarde alguns segundos antes de tentar novamente.';
  end if;

  v_tipo:=case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo='fim_intervalo'::public.tipo_marcacao then
    select m.registrado_em
      into v_inicio_intervalo
    from public.marcacoes m
    where m.funcionario_id=v_funcionario.id
      and m.data_local=v_data
      and m.tipo='inicio_intervalo'::public.tipo_marcacao
    order by m.registrado_em desc,m.id desc
    limit 1;

    v_intervalo_minimo:=greatest(
      30,
      coalesce(v_empresa.intervalo_minimo_minutos,30)
    );

    v_restante_segundos:=ceil(
      extract(epoch from(
        v_inicio_intervalo+
        make_interval(mins=>v_intervalo_minimo)-
        v_agora
      ))
    )::integer;

    if v_inicio_intervalo is null then
      raise exception 'Não foi encontrado o início do almoço.';
    elsif v_restante_segundos>0 then
      raise exception
        'Retorno do almoço bloqueado. Aguarde o intervalo mínimo de % minutos.',
        v_intervalo_minimo;
    end if;
  end if;

  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem,
    criado_por
  )
  values(
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'painel_admin',
    auth.uid()
  )
  returning * into v_resultado;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    tabela,
    registro_id,
    acao,
    dados
  )
  values(
    v_funcionario.empresa_id,
    auth.uid(),
    'marcacoes',
    v_resultado.id::text,
    'INSERT_ADMIN',
    jsonb_build_object(
      'funcionario_id',v_funcionario.id,
      'tipo',v_resultado.tipo,
      'registrado_em',v_resultado.registrado_em
    )
  );

  return v_resultado;
end;
$$;


revoke all on function public.registrar_ponto_com_pin(text)
  from public,anon,authenticated;

revoke all on function public.registrar_ponto_dispositivo(text,text,text)
  from public;

grant execute on function public.registrar_ponto_dispositivo(text,text,text)
  to anon,authenticated;

revoke all on function public.registrar_ponto_funcionario(uuid)
  from public,anon;

grant execute on function public.registrar_ponto_funcionario(uuid)
  to authenticated;

commit;

notify pgrst,'reload schema';
