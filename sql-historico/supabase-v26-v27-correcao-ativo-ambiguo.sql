-- Correção V26/V27 — referência ambígua à coluna "ativo"
-- Execute após as versões V26 e V27.

begin;

create or replace function public.autorizar_dispositivo_ponto_admin(
  p_token text,
  p_nome text,
  p_user_agent text default null
)
returns table(id uuid,nome text,ativo boolean,autorizado_em timestamptz)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa uuid;
  v_id uuid;
begin
  if not public.usuario_e_admin() then
    raise exception 'Apenas administradores podem autorizar dispositivos.';
  end if;

  if length(coalesce(p_token,'')) < 32 then
    raise exception 'Token de dispositivo inválido.';
  end if;

  v_empresa := public.empresa_do_usuario();
  if v_empresa is null then
    raise exception 'Empresa não identificada.';
  end if;

  -- Somente uma máquina ativa por empresa.
  update public.dispositivos_ponto as dp
     set ativo = false,
         revogado_em = clock_timestamp()
   where dp.empresa_id = v_empresa
     and dp.ativo = true;

  insert into public.dispositivos_ponto as dp (
    empresa_id,
    nome,
    token_hash,
    ativo,
    autorizado_por,
    user_agent_autorizacao
  ) values (
    v_empresa,
    coalesce(nullif(trim(p_nome),''),'Computador da loja'),
    encode(digest(p_token,'sha256'),'hex'),
    true,
    auth.uid(),
    left(p_user_agent,1000)
  )
  returning dp.id into v_id;

  perform public.registrar_evento_auditoria(
    'AUTORIZAR',
    'dispositivos_ponto',
    v_id::text,
    'Computador autorizado para registrar ponto',
    jsonb_build_object(
      'nome',coalesce(nullif(trim(p_nome),''),'Computador da loja')
    ),
    'web'
  );

  return query
  select dp.id, dp.nome, dp.ativo, dp.autorizado_em
    from public.dispositivos_ponto as dp
   where dp.id = v_id;
end;
$$;

-- Mantém a proteção da V27: a função-base não pode ser chamada diretamente.
revoke execute on function public.autorizar_dispositivo_ponto_admin(text,text,text)
  from authenticated, anon, public;

-- O wrapper com PIN Mestre continua sendo o ponto de entrada autorizado.
grant execute on function public.autorizar_dispositivo_ponto_master_admin(text,text,text,text)
  to authenticated;

commit;
