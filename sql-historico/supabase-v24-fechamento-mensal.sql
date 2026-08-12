-- Plenitude Ponto V24 — Fechamento e reabertura mensal
-- Execute após a V22. Esta migração protege competências já conferidas.

begin;

create table if not exists public.fechamentos_mensais (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ano integer not null check (ano between 2020 and 2100),
  mes integer not null check (mes between 1 and 12),
  status text not null default 'fechado' check (status in ('fechado','reaberto')),
  observacao text,
  fechado_por uuid references auth.users(id) on delete set null,
  fechado_em timestamptz,
  reaberto_por uuid references auth.users(id) on delete set null,
  reaberto_em timestamptz,
  atualizado_em timestamptz not null default now(),
  unique (empresa_id, ano, mes)
);

create index if not exists idx_fechamentos_empresa_competencia
  on public.fechamentos_mensais (empresa_id, ano desc, mes desc);

alter table public.fechamentos_mensais enable row level security;
drop policy if exists fechamentos_select_admin on public.fechamentos_mensais;
create policy fechamentos_select_admin on public.fechamentos_mensais
for select to authenticated
using (empresa_id=public.empresa_do_usuario() and public.usuario_e_admin());

-- Não há escrita direta pelo navegador. Fechamento e reabertura passam pelas RPCs.
drop policy if exists fechamentos_insert_admin on public.fechamentos_mensais;
drop policy if exists fechamentos_update_admin on public.fechamentos_mensais;
drop policy if exists fechamentos_delete_admin on public.fechamentos_mensais;

create or replace function public.competencia_fechada(
  p_empresa_id uuid,
  p_data date
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.fechamentos_mensais f
    where f.empresa_id=p_empresa_id
      and f.ano=extract(year from p_data)::integer
      and f.mes=extract(month from p_data)::integer
      and f.status='fechado'
  );
$$;

create or replace function public.listar_fechamentos_admin(
  p_ano_inicio integer default null,
  p_ano_fim integer default null
)
returns table(
  id uuid,
  ano integer,
  mes integer,
  status text,
  observacao text,
  fechado_em timestamptz,
  fechado_por_nome text,
  reaberto_em timestamptz,
  reaberto_por_nome text,
  atualizado_em timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_empresa uuid;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  v_empresa:=public.empresa_do_usuario();
  return query
  select f.id,f.ano,f.mes,f.status,f.observacao,f.fechado_em,
         pf.nome as fechado_por_nome,f.reaberto_em,pr.nome as reaberto_por_nome,f.atualizado_em
  from public.fechamentos_mensais f
  left join public.perfis pf on pf.id=f.fechado_por
  left join public.perfis pr on pr.id=f.reaberto_por
  where f.empresa_id=v_empresa
    and (p_ano_inicio is null or f.ano>=p_ano_inicio)
    and (p_ano_fim is null or f.ano<=p_ano_fim)
  order by f.ano desc,f.mes desc;
end;
$$;

create or replace function public.fechar_competencia_admin(
  p_ano integer,
  p_mes integer,
  p_observacao text default null
)
returns public.fechamentos_mensais
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_result public.fechamentos_mensais%rowtype;
  v_inicio date;
  v_fim date;
  v_pendencias integer;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  if p_ano not between 2020 and 2100 or p_mes not between 1 and 12 then raise exception 'Competência inválida.'; end if;
  v_empresa:=public.empresa_do_usuario();
  v_inicio:=make_date(p_ano,p_mes,1);
  v_fim:=(v_inicio+interval '1 month - 1 day')::date;
  if v_inicio>current_date then raise exception 'Não é permitido fechar uma competência futura.'; end if;

  -- Bloqueia fechamento quando existem solicitações pendentes no período, se a tabela V18 existir.
  if to_regclass('public.solicitacoes_ajuste') is not null then
    execute 'select count(*) from public.solicitacoes_ajuste where empresa_id=$1 and data_marcacao between $2 and $3 and status=''pendente'''
      into v_pendencias using v_empresa,v_inicio,v_fim;
    if coalesce(v_pendencias,0)>0 then
      raise exception 'Existem % solicitações de ajuste pendentes nesta competência.',v_pendencias;
    end if;
  end if;

  insert into public.fechamentos_mensais(
    empresa_id,ano,mes,status,observacao,fechado_por,fechado_em,reaberto_por,reaberto_em,atualizado_em
  ) values (
    v_empresa,p_ano,p_mes,'fechado',nullif(trim(p_observacao),''),auth.uid(),clock_timestamp(),null,null,clock_timestamp()
  )
  on conflict (empresa_id,ano,mes) do update set
    status='fechado',observacao=excluded.observacao,fechado_por=auth.uid(),fechado_em=clock_timestamp(),
    reaberto_por=null,reaberto_em=null,atualizado_em=clock_timestamp()
  returning * into v_result;

  perform public.registrar_evento_auditoria(
    'FECHAMENTO_MENSAL','fechamentos_mensais',v_result.id::text,
    format('Competência %s/%s fechada',lpad(p_mes::text,2,'0'),p_ano),
    jsonb_build_object('ano',p_ano,'mes',p_mes,'status','fechado','observacao',p_observacao),'web'
  );
  return v_result;
end;
$$;

create or replace function public.reabrir_competencia_admin(
  p_ano integer,
  p_mes integer,
  p_motivo text
)
returns public.fechamentos_mensais
language plpgsql
security definer
set search_path = public
as $$
declare v_empresa uuid; v_result public.fechamentos_mensais%rowtype;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  if length(trim(coalesce(p_motivo,'')))<5 then raise exception 'Informe um motivo para a reabertura.'; end if;
  v_empresa:=public.empresa_do_usuario();
  update public.fechamentos_mensais set
    status='reaberto',observacao=trim(p_motivo),reaberto_por=auth.uid(),reaberto_em=clock_timestamp(),atualizado_em=clock_timestamp()
  where empresa_id=v_empresa and ano=p_ano and mes=p_mes and status='fechado'
  returning * into v_result;
  if v_result.id is null then raise exception 'A competência não está fechada.'; end if;
  perform public.registrar_evento_auditoria(
    'REABERTURA_MENSAL','fechamentos_mensais',v_result.id::text,
    format('Competência %s/%s reaberta',lpad(p_mes::text,2,'0'),p_ano),
    jsonb_build_object('ano',p_ano,'mes',p_mes,'status','reaberto','motivo',p_motivo),'web'
  );
  return v_result;
end;
$$;

-- Protege marcações de competências fechadas, inclusive chamadas RPC e ajustes aprovados.
create or replace function public.bloquear_alteracao_competencia_fechada_marcacao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_empresa uuid; v_data date;
begin
  v_empresa:=coalesce(new.empresa_id,old.empresa_id);
  v_data:=coalesce(new.data_local,old.data_local);
  if public.competencia_fechada(v_empresa,v_data) then
    raise exception 'Competência %/% fechada. Reabra o mês antes de alterar marcações.',
      lpad(extract(month from v_data)::integer::text,2,'0'),extract(year from v_data)::integer;
  end if;
  if tg_op='UPDATE' and public.competencia_fechada(old.empresa_id,old.data_local) then
    raise exception 'A marcação original pertence a uma competência fechada.';
  end if;
  return coalesce(new,old);
end;
$$;

drop trigger if exists trg_bloquear_marcacao_competencia_fechada on public.marcacoes;
create trigger trg_bloquear_marcacao_competencia_fechada
before insert or update or delete on public.marcacoes
for each row execute function public.bloquear_alteracao_competencia_fechada_marcacao();

-- Protege ocorrências que atinjam qualquer dia de uma competência fechada.
create or replace function public.bloquear_alteracao_competencia_fechada_ocorrencia()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare r record; v_empresa uuid; v_inicio date; v_fim date;
begin
  v_empresa:=coalesce(new.empresa_id,old.empresa_id);
  v_inicio:=coalesce(new.data_inicio,old.data_inicio);
  v_fim:=coalesce(new.data_fim,old.data_fim);
  for r in select generate_series(date_trunc('month',v_inicio::timestamp),date_trunc('month',v_fim::timestamp),interval '1 month')::date d loop
    if public.competencia_fechada(v_empresa,r.d) then
      raise exception 'Existe competência fechada no período desta ocorrência. Reabra o mês antes de alterar.';
    end if;
  end loop;
  if tg_op='UPDATE' then
    for r in select generate_series(date_trunc('month',old.data_inicio::timestamp),date_trunc('month',old.data_fim::timestamp),interval '1 month')::date d loop
      if public.competencia_fechada(old.empresa_id,r.d) then raise exception 'A ocorrência original pertence a uma competência fechada.'; end if;
    end loop;
  end if;
  return coalesce(new,old);
end;
$$;

drop trigger if exists trg_bloquear_ocorrencia_competencia_fechada on public.ocorrencias;
create trigger trg_bloquear_ocorrencia_competencia_fechada
before insert or update or delete on public.ocorrencias
for each row execute function public.bloquear_alteracao_competencia_fechada_ocorrencia();

revoke all on function public.listar_fechamentos_admin(integer,integer) from public,anon;
revoke all on function public.fechar_competencia_admin(integer,integer,text) from public,anon;
revoke all on function public.reabrir_competencia_admin(integer,integer,text) from public,anon;
grant execute on function public.listar_fechamentos_admin(integer,integer) to authenticated;
grant execute on function public.fechar_competencia_admin(integer,integer,text) to authenticated;
grant execute on function public.reabrir_competencia_admin(integer,integer,text) to authenticated;

commit;
