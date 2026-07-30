-- Plenitude Ponto V26 — Dispositivo autorizado para registro de ponto
-- Execute após as migrações anteriores.

begin;

create table if not exists public.dispositivos_ponto (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  token_hash text not null unique,
  ativo boolean not null default true,
  autorizado_por uuid references auth.users(id),
  autorizado_em timestamptz not null default clock_timestamp(),
  ultimo_uso_em timestamptz,
  revogado_em timestamptz,
  user_agent_autorizacao text,
  observacao text,
  criado_em timestamptz not null default clock_timestamp()
);

create index if not exists idx_dispositivos_ponto_empresa_ativo
  on public.dispositivos_ponto(empresa_id,ativo);

alter table public.dispositivos_ponto enable row level security;
drop policy if exists dispositivos_select_admin on public.dispositivos_ponto;
create policy dispositivos_select_admin on public.dispositivos_ponto
for select to authenticated
using (empresa_id=public.empresa_do_usuario() and public.usuario_e_admin());

create or replace function public.autorizar_dispositivo_ponto_admin(
  p_token text,
  p_nome text,
  p_user_agent text default null
)
returns table(id uuid,nome text,ativo boolean,autorizado_em timestamptz)
language plpgsql security definer
set search_path=public,extensions
as $$
declare v_empresa uuid; v_id uuid;
begin
  if not public.usuario_e_admin() then raise exception 'Apenas administradores podem autorizar dispositivos.'; end if;
  if length(coalesce(p_token,'')) < 32 then raise exception 'Token de dispositivo inválido.'; end if;
  v_empresa:=public.empresa_do_usuario();
  if v_empresa is null then raise exception 'Empresa não identificada.'; end if;

  -- Regra da V26: somente uma máquina ativa por empresa.
  update public.dispositivos_ponto
     set ativo=false,revogado_em=clock_timestamp()
   where empresa_id=v_empresa and ativo=true;

  insert into public.dispositivos_ponto(
    empresa_id,nome,token_hash,ativo,autorizado_por,user_agent_autorizacao
  ) values (
    v_empresa,coalesce(nullif(trim(p_nome),''),'Computador da loja'),
    encode(digest(p_token,'sha256'),'hex'),true,auth.uid(),left(p_user_agent,1000)
  ) returning dispositivos_ponto.id into v_id;

  perform public.registrar_evento_auditoria(
    'AUTORIZAR','dispositivos_ponto',v_id::text,
    'Computador autorizado para registrar ponto',
    jsonb_build_object('nome',coalesce(nullif(trim(p_nome),''),'Computador da loja')),'web'
  );

  return query select d.id,d.nome,d.ativo,d.autorizado_em from public.dispositivos_ponto d where d.id=v_id;
end $$;

create or replace function public.revogar_dispositivo_ponto_admin(p_id uuid,p_motivo text default null)
returns void language plpgsql security definer
set search_path=public
as $$
declare v_empresa uuid; v_nome text;
begin
  if not public.usuario_e_admin() then raise exception 'Apenas administradores podem revogar dispositivos.'; end if;
  v_empresa:=public.empresa_do_usuario();
  update public.dispositivos_ponto set ativo=false,revogado_em=clock_timestamp(),observacao=coalesce(nullif(trim(p_motivo),''),observacao)
   where id=p_id and empresa_id=v_empresa returning nome into v_nome;
  if v_nome is null then raise exception 'Dispositivo não encontrado.'; end if;
  perform public.registrar_evento_auditoria('REVOGAR','dispositivos_ponto',p_id::text,'Autorização de computador revogada',jsonb_build_object('nome',v_nome,'motivo',p_motivo),'web');
end $$;

create or replace function public.listar_dispositivos_ponto_admin()
returns table(id uuid,nome text,ativo boolean,autorizado_em timestamptz,ultimo_uso_em timestamptz,revogado_em timestamptz,observacao text)
language plpgsql security definer set search_path=public as $$
begin
 if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
 return query select d.id,d.nome,d.ativo,d.autorizado_em,d.ultimo_uso_em,d.revogado_em,d.observacao
 from public.dispositivos_ponto d where d.empresa_id=public.empresa_do_usuario() order by d.autorizado_em desc;
end $$;

create or replace function public.validar_dispositivo_ponto(p_token text)
returns table(autorizado boolean,nome text)
language plpgsql security definer set search_path=public,extensions as $$
begin
 return query
 select true,d.nome from public.dispositivos_ponto d
 where d.token_hash=encode(digest(coalesce(p_token,''),'sha256'),'hex') and d.ativo=true
 limit 1;
 if not found then return query select false,null::text; end if;
end $$;

create or replace function public.login_funcionario_pin_dispositivo(
  p_matricula text,p_pin text,p_dispositivo_token text,p_user_agent text default null
)
returns table(token text,funcionario_id uuid,nome text,cargo text,matricula text,foto_url text,exigir_troca_pin boolean,expira_em timestamptz)
language plpgsql security definer set search_path=public,extensions as $$
declare d public.dispositivos_ponto%rowtype; r record;
begin
 select * into d from public.dispositivos_ponto
 where token_hash=encode(digest(coalesce(p_dispositivo_token,''),'sha256'),'hex') and ativo=true;
 if d.id is null then
   raise exception 'Este computador não está autorizado para registrar ponto.';
 end if;

 select * into r from public.login_funcionario_pin(p_matricula,p_pin);
 if r.funcionario_id is null then raise exception 'Não foi possível iniciar a sessão.'; end if;
 if not exists(select 1 from public.funcionarios f where f.id=r.funcionario_id and f.empresa_id=d.empresa_id) then
   perform public.encerrar_sessao_funcionario(r.token);
   raise exception 'Este dispositivo não pertence à empresa do funcionário.';
 end if;
 update public.dispositivos_ponto set ultimo_uso_em=clock_timestamp() where id=d.id;
 return query select r.token,r.funcionario_id,r.nome,r.cargo,r.matricula,r.foto_url,r.exigir_troca_pin,r.expira_em;
end $$;

create or replace function public.registrar_ponto_dispositivo(p_token text,p_dispositivo_token text,p_user_agent text default null)
returns public.marcacoes language plpgsql security definer set search_path=public,extensions as $$
declare d public.dispositivos_ponto%rowtype; f public.funcionarios%rowtype; m public.marcacoes%rowtype;
begin
 select * into d from public.dispositivos_ponto
 where token_hash=encode(digest(coalesce(p_dispositivo_token,''),'sha256'),'hex') and ativo=true;
 if d.id is null then raise exception 'Registro bloqueado: computador não autorizado.'; end if;
 f:=public.funcionario_por_token(p_token);
 if f.empresa_id<>d.empresa_id then raise exception 'Dispositivo não autorizado para esta empresa.'; end if;
 m:=public.registrar_ponto_com_pin(p_token);
 update public.dispositivos_ponto set ultimo_uso_em=clock_timestamp() where id=d.id;
 return m;
exception when others then
  begin
    if f.id is not null then
      insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados,dados_novos,origem,descricao)
      values(f.empresa_id,null,'dispositivos_ponto',coalesce(d.id::text,'desconhecido'),'PONTO_BLOQUEADO',
      jsonb_build_object('funcionario_id',f.id,'user_agent',left(p_user_agent,500)),
      jsonb_build_object('motivo',sqlerrm),'web','Tentativa de ponto bloqueada por dispositivo');
    end if;
  exception when others then null; end;
  raise;
end $$;

revoke all on function public.autorizar_dispositivo_ponto_admin(text,text,text) from public,anon;
revoke all on function public.revogar_dispositivo_ponto_admin(uuid,text) from public,anon;
revoke all on function public.listar_dispositivos_ponto_admin() from public,anon;
grant execute on function public.autorizar_dispositivo_ponto_admin(text,text,text) to authenticated;
grant execute on function public.revogar_dispositivo_ponto_admin(uuid,text) to authenticated;
grant execute on function public.listar_dispositivos_ponto_admin() to authenticated;

grant execute on function public.validar_dispositivo_ponto(text) to anon,authenticated;
grant execute on function public.login_funcionario_pin_dispositivo(text,text,text,text) to anon,authenticated;
grant execute on function public.registrar_ponto_dispositivo(text,text,text) to anon,authenticated;

-- Impede que o navegador contorne a verificação chamando as funções antigas diretamente.
revoke execute on function public.login_funcionario_pin(text,text) from anon,authenticated;
revoke execute on function public.registrar_ponto_com_pin(text) from anon,authenticated;

commit;
