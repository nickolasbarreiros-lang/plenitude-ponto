begin;

-- RC4.16 — múltiplos computadores autorizados
--
-- Permite manter simultaneamente, por exemplo:
-- • computador da loja;
-- • computador de homologação;
-- • equipamento de contingência.
--
-- Cada navegador continua possuindo um token próprio e pode ser revogado
-- individualmente, sem bloquear os demais.

alter table public.dispositivos_ponto
  add column if not exists tipo text not null default 'terminal';

alter table public.dispositivos_ponto
  drop constraint if exists dispositivos_ponto_tipo_check;

alter table public.dispositivos_ponto
  add constraint dispositivos_ponto_tipo_check
  check (tipo in ('terminal','homologacao','contingencia'));

create index if not exists idx_dispositivos_ponto_empresa_tipo_ativo
  on public.dispositivos_ponto(empresa_id,tipo,ativo);

create or replace function public.autorizar_dispositivo_ponto_multi_master_admin(
  p_token text,
  p_nome text,
  p_tipo text default 'terminal',
  p_user_agent text default null,
  p_master_pin text default null
)
returns table(
  id uuid,
  nome text,
  tipo text,
  ativo boolean,
  autorizado_em timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_id uuid;
  v_tipo text;
  v_ativos integer;
begin
  if not public.usuario_e_admin() then
    raise exception 'Apenas administradores podem autorizar dispositivos.';
  end if;

  v_empresa := public.empresa_do_usuario();

  if v_empresa is null then
    raise exception 'Empresa não identificada.';
  end if;

  perform public.validar_pin_mestre_interno(v_empresa,p_master_pin);

  if length(coalesce(p_token,'')) < 32 then
    raise exception 'Token de dispositivo inválido.';
  end if;

  v_tipo := lower(coalesce(nullif(trim(p_tipo),''),'terminal'));

  if v_tipo not in ('terminal','homologacao','contingencia') then
    raise exception 'Tipo de dispositivo inválido.';
  end if;

  select count(*)::integer
    into v_ativos
  from public.dispositivos_ponto d
  where d.empresa_id = v_empresa
    and d.ativo = true;

  if v_ativos >= 10 then
    raise exception 'Limite de 10 dispositivos ativos atingido.';
  end if;

  if exists(
    select 1
    from public.dispositivos_ponto d
    where d.token_hash = encode(digest(p_token,'sha256'),'hex')
      and d.ativo = true
  ) then
    raise exception 'Este navegador já está autorizado.';
  end if;

  insert into public.dispositivos_ponto(
    empresa_id,
    nome,
    tipo,
    token_hash,
    ativo,
    autorizado_por,
    user_agent_autorizacao
  )
  values(
    v_empresa,
    coalesce(nullif(trim(p_nome),''),'Computador autorizado'),
    v_tipo,
    encode(digest(p_token,'sha256'),'hex'),
    true,
    auth.uid(),
    left(p_user_agent,1000)
  )
  returning dispositivos_ponto.id into v_id;

  perform public.registrar_evento_auditoria(
    'AUTORIZAR',
    'dispositivos_ponto',
    v_id::text,
    'Novo computador autorizado sem revogar os demais',
    jsonb_build_object(
      'nome',coalesce(nullif(trim(p_nome),''),'Computador autorizado'),
      'tipo',v_tipo,
      'dispositivos_ativos_apos_autorizacao',v_ativos + 1
    ),
    'web'
  );

  return query
  select d.id,d.nome,d.tipo,d.ativo,d.autorizado_em
  from public.dispositivos_ponto d
  where d.id = v_id;
end;
$$;

create or replace function public.listar_dispositivos_ponto_multi_admin()
returns table(
  id uuid,
  nome text,
  tipo text,
  ativo boolean,
  autorizado_em timestamptz,
  ultimo_uso_em timestamptz,
  revogado_em timestamptz,
  observacao text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso negado.';
  end if;

  return query
  select
    d.id,
    d.nome,
    d.tipo,
    d.ativo,
    d.autorizado_em,
    d.ultimo_uso_em,
    d.revogado_em,
    d.observacao
  from public.dispositivos_ponto d
  where d.empresa_id = public.empresa_do_usuario()
  order by d.ativo desc,d.autorizado_em desc;
end;
$$;

create or replace function public.validar_dispositivo_ponto_detalhado(p_token text)
returns table(
  id uuid,
  autorizado boolean,
  nome text,
  tipo text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return query
  select d.id,true,d.nome,d.tipo
  from public.dispositivos_ponto d
  where d.token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex')
    and d.ativo = true
  limit 1;

  if not found then
    return query select null::uuid,false,null::text,null::text;
  end if;
end;
$$;

revoke all on function public.autorizar_dispositivo_ponto_multi_master_admin(
  text,text,text,text,text
) from public,anon;

grant execute on function public.autorizar_dispositivo_ponto_multi_master_admin(
  text,text,text,text,text
) to authenticated;

revoke all on function public.listar_dispositivos_ponto_multi_admin()
from public,anon;

grant execute on function public.listar_dispositivos_ponto_multi_admin()
to authenticated;

grant execute on function public.validar_dispositivo_ponto_detalhado(text)
to anon,authenticated;

commit;

notify pgrst,'reload schema';
