-- Plenitude Ponto RC5.22
-- Importação automática das marcações de contingência para a jornada oficial.
--
-- Execute este arquivo inteiro no SQL Editor do Supabase.

begin;

-- Garante que o vínculo com public.marcacoes usa o mesmo tipo do ID oficial.
do $$
declare
  v_type text;
begin
  select data_type
    into v_type
  from information_schema.columns
  where table_schema='public'
    and table_name='marcacoes_contingencia'
    and column_name='marcacao_oficial_id';

  if v_type='uuid' then
    alter table public.marcacoes_contingencia
      drop constraint if exists marcacoes_contingencia_marcacao_oficial_id_fkey;

    update public.marcacoes_contingencia
       set marcacao_oficial_id=null;

    alter table public.marcacoes_contingencia
      alter column marcacao_oficial_id type bigint
      using null::bigint;

    alter table public.marcacoes_contingencia
      add constraint marcacoes_contingencia_marcacao_oficial_id_fkey
      foreign key (marcacao_oficial_id)
      references public.marcacoes(id);
  end if;
end;
$$;

create or replace function public.sincronizar_marcacao_contingencia(
  p_dispositivo_token text,
  p_evento_offline_id uuid,
  p_funcionario_id uuid,
  p_tipo text,
  p_ocorrido_em_dispositivo timestamptz,
  p_data_local date,
  p_fuso_horario text default null,
  p_offset_minutos integer default null,
  p_criado_local_em timestamptz default null,
  p_hash_evento text default null,
  p_hash_anterior text default null,
  p_user_agent text default null
)
returns public.marcacoes_contingencia
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_result public.marcacoes_contingencia%rowtype;
  v_mark public.marcacoes%rowtype;
  v_existing_mark public.marcacoes%rowtype;
  v_tipo public.tipo_marcacao;
  v_conflito text;
  v_data_oficial date;
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash=encode(
          digest(coalesce(p_dispositivo_token,''),'sha256'),
          'hex'
        )
    and d.ativo=true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Dispositivo não autorizado para sincronizar contingência.';
  end if;

  select f.*
    into v_funcionario
  from public.funcionarios f
  where f.id=p_funcionario_id
    and f.empresa_id=v_dispositivo.empresa_id
    and f.ativo=true;

  if v_funcionario.id is null then
    raise exception 'Funcionário inválido para este dispositivo.';
  end if;

  begin
    v_tipo:=p_tipo::public.tipo_marcacao;
  exception when others then
    raise exception 'Tipo de marcação offline inválido.';
  end;

  v_data_oficial :=
    (p_ocorrido_em_dispositivo at time zone 'America/Sao_Paulo')::date;

  if p_ocorrido_em_dispositivo > clock_timestamp()+interval '10 minutes' then
    v_conflito:='Horário do dispositivo está no futuro.';
  elsif abs(
    extract(
      epoch from (clock_timestamp()-p_ocorrido_em_dispositivo)
    )
  ) > 86400*7 then
    v_conflito:='Horário do dispositivo difere mais de 7 dias do servidor.';
  end if;

  -- Idempotência: o mesmo evento offline nunca é importado duas vezes.
  select c.*
    into v_result
  from public.marcacoes_contingencia c
  where c.dispositivo_id=v_dispositivo.id
    and c.evento_offline_id=p_evento_offline_id
  limit 1;

  if v_result.id is not null then
    update public.marcacoes_contingencia
       set sincronizado_em=clock_timestamp(),
           atualizado_em=clock_timestamp()
     where id=v_result.id
     returning * into v_result;

    return v_result;
  end if;

  -- Detecta marcação oficial equivalente já existente.
  select m.*
    into v_existing_mark
  from public.marcacoes m
  where m.funcionario_id=p_funcionario_id
    and m.data_local=v_data_oficial
    and m.tipo=v_tipo
  order by m.registrado_em
  limit 1;

  if v_existing_mark.id is not null then
    insert into public.marcacoes_contingencia(
      empresa_id,
      funcionario_id,
      dispositivo_id,
      evento_offline_id,
      tipo,
      ocorrido_em_dispositivo,
      data_local,
      fuso_horario,
      offset_minutos,
      criado_local_em,
      sincronizado_em,
      status,
      conflito,
      hash_evento,
      hash_anterior,
      user_agent,
      marcacao_oficial_id,
      observacao_admin,
      aprovado_em
    )
    values(
      v_dispositivo.empresa_id,
      p_funcionario_id,
      v_dispositivo.id,
      p_evento_offline_id,
      v_tipo,
      p_ocorrido_em_dispositivo,
      v_data_oficial,
      left(p_fuso_horario,80),
      p_offset_minutos,
      p_criado_local_em,
      clock_timestamp(),
      'duplicado',
      'Já existe marcação oficial do mesmo tipo nesta data.',
      p_hash_evento,
      p_hash_anterior,
      left(p_user_agent,1000),
      v_existing_mark.id,
      'Duplicidade detectada automaticamente na sincronização.',
      clock_timestamp()
    )
    returning * into v_result;

    return v_result;
  end if;

  -- Horários suspeitos continuam pendentes para análise administrativa.
  if v_conflito is not null then
    insert into public.marcacoes_contingencia(
      empresa_id,
      funcionario_id,
      dispositivo_id,
      evento_offline_id,
      tipo,
      ocorrido_em_dispositivo,
      data_local,
      fuso_horario,
      offset_minutos,
      criado_local_em,
      sincronizado_em,
      status,
      conflito,
      hash_evento,
      hash_anterior,
      user_agent
    )
    values(
      v_dispositivo.empresa_id,
      p_funcionario_id,
      v_dispositivo.id,
      p_evento_offline_id,
      v_tipo,
      p_ocorrido_em_dispositivo,
      v_data_oficial,
      left(p_fuso_horario,80),
      p_offset_minutos,
      p_criado_local_em,
      clock_timestamp(),
      'conflitante',
      v_conflito,
      p_hash_evento,
      p_hash_anterior,
      left(p_user_agent,1000)
    )
    returning * into v_result;

    return v_result;
  end if;

  -- Importa imediatamente para a jornada oficial.
  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values(
    v_dispositivo.empresa_id,
    p_funcionario_id,
    v_tipo,
    p_ocorrido_em_dispositivo,
    v_data_oficial,
    'contingencia'
  )
  returning * into v_mark;

  insert into public.marcacoes_contingencia(
    empresa_id,
    funcionario_id,
    dispositivo_id,
    evento_offline_id,
    tipo,
    ocorrido_em_dispositivo,
    data_local,
    fuso_horario,
    offset_minutos,
    criado_local_em,
    sincronizado_em,
    status,
    hash_evento,
    hash_anterior,
    user_agent,
    marcacao_oficial_id,
    observacao_admin,
    aprovado_em
  )
  values(
    v_dispositivo.empresa_id,
    p_funcionario_id,
    v_dispositivo.id,
    p_evento_offline_id,
    v_tipo,
    p_ocorrido_em_dispositivo,
    v_data_oficial,
    left(p_fuso_horario,80),
    p_offset_minutos,
    p_criado_local_em,
    clock_timestamp(),
    'aprovado',
    p_hash_evento,
    p_hash_anterior,
    left(p_user_agent,1000),
    v_mark.id,
    'Importação automática da contingência.',
    clock_timestamp()
  )
  returning * into v_result;

  update public.dispositivos_ponto
     set ultimo_uso_em=clock_timestamp()
   where id=v_dispositivo.id;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    tabela,
    registro_id,
    acao,
    dados_novos,
    origem,
    descricao
  )
  values(
    v_dispositivo.empresa_id,
    null,
    'marcacoes_contingencia',
    v_result.id::text,
    'CONTINGENCIA_IMPORTADA_AUTOMATICAMENTE',
    to_jsonb(v_result),
    'contingencia',
    'Marcação offline importada automaticamente para a jornada oficial.'
  );

  return v_result;
end;
$$;

revoke all on function public.sincronizar_marcacao_contingencia(
  text,uuid,uuid,text,timestamptz,date,text,integer,timestamptz,text,text,text
) from public,anon;

grant execute on function public.sincronizar_marcacao_contingencia(
  text,uuid,uuid,text,timestamptz,date,text,integer,timestamptz,text,text,text
) to authenticated;

commit;

notify pgrst,'reload schema';
