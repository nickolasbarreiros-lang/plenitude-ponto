-- Plenitude Ponto V27 — PIN Mestre para operações críticas
-- Execute após a V26.

begin;

create table if not exists public.seguranca_master (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  pin_hash text not null,
  tentativas_falhas integer not null default 0,
  bloqueado_ate timestamptz,
  atualizado_por uuid references auth.users(id),
  atualizado_em timestamptz not null default clock_timestamp(),
  criado_em timestamptz not null default clock_timestamp()
);

alter table public.seguranca_master enable row level security;
-- Nenhuma leitura ou escrita direta pelo navegador. Acesso somente pelas funções abaixo.
drop policy if exists seguranca_master_select on public.seguranca_master;
drop policy if exists seguranca_master_insert on public.seguranca_master;
drop policy if exists seguranca_master_update on public.seguranca_master;
drop policy if exists seguranca_master_delete on public.seguranca_master;

create or replace function public.validar_pin_mestre_interno(p_empresa uuid,p_pin text)
returns boolean
language plpgsql security definer
set search_path=public,extensions
as $$
declare s public.seguranca_master%rowtype;
begin
  select * into s from public.seguranca_master where empresa_id=p_empresa for update;
  if s.empresa_id is null then raise exception 'PIN Mestre ainda não foi configurado.'; end if;
  if s.bloqueado_ate is not null and s.bloqueado_ate>clock_timestamp() then
    raise exception 'PIN Mestre temporariamente bloqueado. Tente novamente mais tarde.';
  end if;
  if coalesce(p_pin,'') !~ '^\d{6}$' or crypt(p_pin,s.pin_hash)<>s.pin_hash then
    update public.seguranca_master
       set tentativas_falhas=tentativas_falhas+1,
           bloqueado_ate=case when tentativas_falhas+1>=5 then clock_timestamp()+interval '15 minutes' else null end
     where empresa_id=p_empresa;
    raise exception 'PIN Mestre incorreto.';
  end if;
  update public.seguranca_master set tentativas_falhas=0,bloqueado_ate=null where empresa_id=p_empresa;
  return true;
end $$;

create or replace function public.status_pin_mestre_admin()
returns table(configurado boolean,bloqueado_ate timestamptz,atualizado_em timestamptz)
language plpgsql security definer
set search_path=public
as $$
declare v_empresa uuid;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  v_empresa:=public.empresa_do_usuario();
  return query
  select exists(select 1 from public.seguranca_master s where s.empresa_id=v_empresa),
         (select s.bloqueado_ate from public.seguranca_master s where s.empresa_id=v_empresa),
         (select s.atualizado_em from public.seguranca_master s where s.empresa_id=v_empresa);
end $$;

create or replace function public.definir_pin_mestre_admin(p_novo_pin text,p_pin_atual text default null)
returns void
language plpgsql security definer
set search_path=public,extensions
as $$
declare v_empresa uuid; v_existe boolean;
begin
  if not public.usuario_e_admin() then raise exception 'Apenas administradores podem definir o PIN Mestre.'; end if;
  if coalesce(p_novo_pin,'') !~ '^\d{6}$' then raise exception 'O PIN Mestre deve ter exatamente 6 números.'; end if;
  v_empresa:=public.empresa_do_usuario();
  select exists(select 1 from public.seguranca_master where empresa_id=v_empresa) into v_existe;
  if v_existe then perform public.validar_pin_mestre_interno(v_empresa,p_pin_atual); end if;

  insert into public.seguranca_master(empresa_id,pin_hash,atualizado_por)
  values(v_empresa,crypt(p_novo_pin,gen_salt('bf',10)),auth.uid())
  on conflict(empresa_id) do update set
    pin_hash=excluded.pin_hash,tentativas_falhas=0,bloqueado_ate=null,
    atualizado_por=auth.uid(),atualizado_em=clock_timestamp();

  perform public.registrar_evento_auditoria(
    case when v_existe then 'ALTERAR_PIN_MESTRE' else 'CRIAR_PIN_MESTRE' end,
    'seguranca_master',v_empresa::text,
    case when v_existe then 'PIN Mestre alterado' else 'PIN Mestre configurado' end,
    jsonb_build_object('configurado',true),'web'
  );
end $$;

-- Wrappers protegidos: dispositivo.
create or replace function public.autorizar_dispositivo_ponto_master_admin(
  p_token text,p_nome text,p_user_agent text default null,p_master_pin text default null
)
returns table(id uuid,nome text,ativo boolean,autorizado_em timestamptz)
language plpgsql security definer set search_path=public
as $$
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  perform public.validar_pin_mestre_interno(public.empresa_do_usuario(),p_master_pin);
  return query select * from public.autorizar_dispositivo_ponto_admin(p_token,p_nome,p_user_agent);
end $$;

create or replace function public.revogar_dispositivo_ponto_master_admin(p_id uuid,p_motivo text default null,p_master_pin text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  perform public.validar_pin_mestre_interno(public.empresa_do_usuario(),p_master_pin);
  perform public.revogar_dispositivo_ponto_admin(p_id,p_motivo);
end $$;

-- Wrappers protegidos: fechamento mensal.
create or replace function public.fechar_competencia_master_admin(p_ano integer,p_mes integer,p_observacao text default null,p_master_pin text default null)
returns public.fechamentos_mensais
language plpgsql security definer set search_path=public as $$
declare v_result public.fechamentos_mensais%rowtype;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  perform public.validar_pin_mestre_interno(public.empresa_do_usuario(),p_master_pin);
  v_result:=public.fechar_competencia_admin(p_ano,p_mes,p_observacao);
  return v_result;
end $$;

create or replace function public.reabrir_competencia_master_admin(p_ano integer,p_mes integer,p_motivo text,p_master_pin text default null)
returns public.fechamentos_mensais
language plpgsql security definer set search_path=public as $$
declare v_result public.fechamentos_mensais%rowtype;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  perform public.validar_pin_mestre_interno(public.empresa_do_usuario(),p_master_pin);
  v_result:=public.reabrir_competencia_admin(p_ano,p_mes,p_motivo);
  return v_result;
end $$;

-- Remove acesso direto às operações críticas antigas.
revoke execute on function public.autorizar_dispositivo_ponto_admin(text,text,text) from authenticated,anon,public;
revoke execute on function public.revogar_dispositivo_ponto_admin(uuid,text) from authenticated,anon,public;
revoke execute on function public.fechar_competencia_admin(integer,integer,text) from authenticated,anon,public;
revoke execute on function public.reabrir_competencia_admin(integer,integer,text) from authenticated,anon,public;

revoke all on function public.validar_pin_mestre_interno(uuid,text) from public,anon,authenticated;
revoke all on function public.status_pin_mestre_admin() from public,anon;
revoke all on function public.definir_pin_mestre_admin(text,text) from public,anon;
revoke all on function public.autorizar_dispositivo_ponto_master_admin(text,text,text,text) from public,anon;
revoke all on function public.revogar_dispositivo_ponto_master_admin(uuid,text,text) from public,anon;
revoke all on function public.fechar_competencia_master_admin(integer,integer,text,text) from public,anon;
revoke all on function public.reabrir_competencia_master_admin(integer,integer,text,text) from public,anon;

grant execute on function public.status_pin_mestre_admin() to authenticated;
grant execute on function public.definir_pin_mestre_admin(text,text) to authenticated;
grant execute on function public.autorizar_dispositivo_ponto_master_admin(text,text,text,text) to authenticated;
grant execute on function public.revogar_dispositivo_ponto_master_admin(uuid,text,text) to authenticated;
grant execute on function public.fechar_competencia_master_admin(integer,integer,text,text) to authenticated;
grant execute on function public.reabrir_competencia_master_admin(integer,integer,text,text) to authenticated;

commit;
