-- PLENITUDE PONTO V15 — ACESSO POR MATRÍCULA + PIN
-- Execute integralmente no SQL Editor do Supabase.

create extension if not exists pgcrypto;

alter table public.funcionarios
  add column if not exists pin_hash text,
  add column if not exists acesso_ponto_ativo boolean not null default true,
  add column if not exists tentativas_pin integer not null default 0,
  add column if not exists bloqueado_ate timestamptz,
  add column if not exists exigir_troca_pin boolean not null default false,
  add column if not exists ultimo_acesso_em timestamptz;

create unique index if not exists funcionarios_empresa_matricula_uidx
  on public.funcionarios (empresa_id, matricula)
  where matricula is not null;

create table if not exists public.sessoes_funcionario (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  token_hash text not null unique,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null default (now() + interval '12 hours'),
  encerrado_em timestamptz,
  ultimo_uso_em timestamptz not null default now()
);

alter table public.sessoes_funcionario enable row level security;
revoke all on public.sessoes_funcionario from anon, authenticated;

create or replace function public.proxima_matricula(p_empresa_id uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare v_num integer;
begin
  select coalesce(max(case when matricula ~ '^\\d+$' then matricula::integer end),0)+1
    into v_num from public.funcionarios where empresa_id=p_empresa_id;
  return lpad(v_num::text,4,'0');
end $$;

create or replace function public.gerar_matricula_funcionario()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.matricula is null or btrim(new.matricula)='' then
    new.matricula := public.proxima_matricula(new.empresa_id);
  else
    new.matricula := btrim(new.matricula);
  end if;
  return new;
end $$;

drop trigger if exists trg_gerar_matricula_funcionario on public.funcionarios;
create trigger trg_gerar_matricula_funcionario before insert on public.funcionarios
for each row execute function public.gerar_matricula_funcionario();

-- Gera matrícula para cadastros antigos que ainda não possuem uma.
do $$
declare r record; begin
  for r in select id,empresa_id from public.funcionarios where matricula is null or btrim(matricula)='' order by criado_em nulls last, id loop
    update public.funcionarios set matricula=public.proxima_matricula(r.empresa_id) where id=r.id;
  end loop;
end $$;

create or replace function public.admin_definir_pin(
  p_funcionario_id uuid,
  p_pin text,
  p_exigir_troca boolean default false,
  p_acesso_ativo boolean default true
)
returns table(id uuid, matricula text, acesso_ponto_ativo boolean, exigir_troca_pin boolean)
language plpgsql security definer set search_path=public
as $$
declare v_empresa uuid;
begin
  if auth.uid() is null then raise exception 'Sessão administrativa obrigatória.'; end if;
  select empresa_id into v_empresa from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  if p_pin !~ '^\\d{4}$' then raise exception 'O PIN deve conter exatamente 4 números.'; end if;

  update public.funcionarios f set
    pin_hash=crypt(p_pin,gen_salt('bf',10)),
    acesso_ponto_ativo=p_acesso_ativo,
    exigir_troca_pin=p_exigir_troca,
    tentativas_pin=0,
    bloqueado_ate=null
  where f.id=p_funcionario_id and f.empresa_id=v_empresa;
  if not found then raise exception 'Funcionário não encontrado.'; end if;

  insert into public.logs_auditoria(empresa_id,usuario_id,acao,tabela,registro_id,dados_novos)
  values(v_empresa,auth.uid(),'PIN_REDEFINIDO','funcionarios',p_funcionario_id,
    jsonb_build_object('exigir_troca',p_exigir_troca,'acesso_ativo',p_acesso_ativo));

  return query select f.id,f.matricula,f.acesso_ponto_ativo,f.exigir_troca_pin
    from public.funcionarios f where f.id=p_funcionario_id;
end $$;

create or replace function public.admin_alterar_acesso_pin(p_funcionario_id uuid,p_ativo boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_empresa uuid;
begin
  select empresa_id into v_empresa from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  update public.funcionarios set acesso_ponto_ativo=p_ativo,tentativas_pin=0,bloqueado_ate=null
   where id=p_funcionario_id and empresa_id=v_empresa;
  if not found then raise exception 'Funcionário não encontrado.'; end if;
end $$;

create or replace function public.login_funcionario_pin(p_matricula text,p_pin text)
returns table(token text,funcionario_id uuid,nome text,cargo text,matricula text,foto_url text,exigir_troca_pin boolean,expira_em timestamptz)
language plpgsql security definer set search_path=public
as $$
declare f public.funcionarios%rowtype; v_token text; v_now timestamptz:=clock_timestamp();
begin
  if p_pin !~ '^\\d{4}$' then raise exception 'Matrícula ou PIN incorretos.'; end if;
  select * into f from public.funcionarios where funcionarios.matricula=btrim(p_matricula) and ativo=true limit 1;
  if f.id is null or f.pin_hash is null then raise exception 'Matrícula ou PIN incorretos.'; end if;
  if not f.acesso_ponto_ativo then raise exception 'Acesso ao ponto bloqueado. Procure o administrador.'; end if;
  if f.bloqueado_ate is not null and f.bloqueado_ate>v_now then
    raise exception 'Acesso temporariamente bloqueado. Tente novamente mais tarde.';
  end if;
  if crypt(p_pin,f.pin_hash)<>f.pin_hash then
    update public.funcionarios set
      tentativas_pin=tentativas_pin+1,
      bloqueado_ate=case when tentativas_pin+1>=5 then v_now+interval '15 minutes' else null end
    where id=f.id;
    raise exception 'Matrícula ou PIN incorretos.';
  end if;
  update public.funcionarios set tentativas_pin=0,bloqueado_ate=null,ultimo_acesso_em=v_now where id=f.id;
  v_token:=encode(gen_random_bytes(32),'hex');
  insert into public.sessoes_funcionario(funcionario_id,token_hash,expira_em)
    values(f.id,encode(digest(v_token,'sha256'),'hex'),v_now+interval '12 hours');
  return query select v_token,f.id,f.nome,f.cargo,f.matricula,f.foto_url,f.exigir_troca_pin,v_now+interval '12 hours';
end $$;

create or replace function public.funcionario_por_token(p_token text)
returns public.funcionarios
language plpgsql security definer set search_path=public as $$
declare f public.funcionarios%rowtype;
begin
  select fun.* into f from public.sessoes_funcionario s join public.funcionarios fun on fun.id=s.funcionario_id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.encerrado_em is null and s.expira_em>clock_timestamp()
    and fun.ativo=true and fun.acesso_ponto_ativo=true;
  if f.id is null then raise exception 'Sessão expirada. Entre novamente.'; end if;
  update public.sessoes_funcionario set ultimo_uso_em=clock_timestamp() where token_hash=encode(digest(p_token,'sha256'),'hex');
  return f;
end $$;

create or replace function public.dados_funcionario_token(p_token text)
returns table(id uuid,nome text,cargo text,matricula text,status text,foto_url text,codigo_qr text,exigir_troca_pin boolean)
language plpgsql security definer set search_path=public as $$
declare f public.funcionarios%rowtype;
begin
  f:=public.funcionario_por_token(p_token);
  return query select f.id,f.nome,f.cargo,f.matricula,f.status,f.foto_url,f.codigo_qr,f.exigir_troca_pin;
end $$;

create or replace function public.marcacoes_funcionario_token(p_token text,p_inicio date,p_fim date)
returns setof public.marcacoes language plpgsql security definer set search_path=public as $$
declare f public.funcionarios%rowtype;
begin f:=public.funcionario_por_token(p_token);
 return query select m.* from public.marcacoes m where m.funcionario_id=f.id and m.data_local between p_inicio and p_fim order by m.registrado_em;
end $$;

create or replace function public.jornada_funcionario_token(p_token text)
returns setof public.jornadas language plpgsql security definer set search_path=public as $$
declare f public.funcionarios%rowtype;
begin f:=public.funcionario_por_token(p_token);
 return query select j.* from public.jornadas j where j.funcionario_id=f.id order by j.dia_semana;
end $$;

create or replace function public.registrar_ponto_com_pin(p_token text)
returns public.marcacoes language plpgsql security definer set search_path=public as $$
declare f public.funcionarios%rowtype; m public.marcacoes%rowtype; v_count int; v_tipo text; v_now timestamptz:=clock_timestamp();
begin
  f:=public.funcionario_por_token(p_token);
  select count(*) into v_count from public.marcacoes where funcionario_id=f.id and data_local=(v_now at time zone 'America/Sao_Paulo')::date;
  if v_count>=4 then raise exception 'As quatro marcações do dia já foram realizadas.'; end if;
  v_tipo:=(array['entrada','inicio_intervalo','fim_intervalo','saida'])[v_count+1];
  insert into public.marcacoes(empresa_id,funcionario_id,tipo,registrado_em,data_local,origem)
  values(f.empresa_id,f.id,v_tipo,v_now,(v_now at time zone 'America/Sao_Paulo')::date,'pin') returning * into m;
  return m;
end $$;

create or replace function public.alterar_proprio_pin(p_token text,p_pin_atual text,p_novo_pin text)
returns void language plpgsql security definer set search_path=public as $$
declare f public.funcionarios%rowtype;
begin
  f:=public.funcionario_por_token(p_token);
  if p_novo_pin !~ '^\\d{4}$' then raise exception 'O novo PIN deve conter exatamente 4 números.'; end if;
  if crypt(p_pin_atual,f.pin_hash)<>f.pin_hash then raise exception 'PIN atual incorreto.'; end if;
  update public.funcionarios set pin_hash=crypt(p_novo_pin,gen_salt('bf',10)),exigir_troca_pin=false where id=f.id;
end $$;

create or replace function public.encerrar_sessao_funcionario(p_token text)
returns void language sql security definer set search_path=public as $$
 update public.sessoes_funcionario set encerrado_em=clock_timestamp()
 where token_hash=encode(digest(p_token,'sha256'),'hex') and encerrado_em is null;
$$;

grant execute on function public.login_funcionario_pin(text,text) to anon,authenticated;
grant execute on function public.dados_funcionario_token(text) to anon,authenticated;
grant execute on function public.marcacoes_funcionario_token(text,date,date) to anon,authenticated;
grant execute on function public.jornada_funcionario_token(text) to anon,authenticated;
grant execute on function public.registrar_ponto_com_pin(text) to anon,authenticated;
grant execute on function public.alterar_proprio_pin(text,text,text) to anon,authenticated;
grant execute on function public.encerrar_sessao_funcionario(text) to anon,authenticated;
grant execute on function public.admin_definir_pin(uuid,text,boolean,boolean) to authenticated;
grant execute on function public.admin_alterar_acesso_pin(uuid,boolean) to authenticated;
