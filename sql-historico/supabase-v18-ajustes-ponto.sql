-- PLENITUDE PONTO V18 — SOLICITAÇÃO E APROVAÇÃO DE AJUSTES
-- Execute integralmente no SQL Editor do Supabase.

create table if not exists public.solicitacoes_ajuste (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  data_marcacao date not null,
  tipo_marcacao public.tipo_marcacao not null,
  horario_solicitado time not null,
  justificativa text not null,
  status text not null default 'pendente' check (status in ('pendente','aprovada','rejeitada','cancelada')),
  resposta_administrador text,
  marcacao_gerada_id bigint references public.marcacoes(id) on delete set null,
  analisado_por uuid references auth.users(id) on delete set null,
  analisado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (char_length(btrim(justificativa)) between 10 and 1000)
);

create index if not exists idx_solicitacoes_ajuste_empresa_status
  on public.solicitacoes_ajuste(empresa_id,status,criado_em desc);
create index if not exists idx_solicitacoes_ajuste_funcionario
  on public.solicitacoes_ajuste(funcionario_id,data_marcacao desc);

alter table public.solicitacoes_ajuste enable row level security;
revoke all on public.solicitacoes_ajuste from anon, authenticated;

create or replace function public.atualizar_timestamp_ajuste()
returns trigger language plpgsql set search_path = public, extensions as $$
begin new.atualizado_em := clock_timestamp(); return new; end $$;

drop trigger if exists trg_atualizar_solicitacao_ajuste on public.solicitacoes_ajuste;
create trigger trg_atualizar_solicitacao_ajuste
before update on public.solicitacoes_ajuste
for each row execute function public.atualizar_timestamp_ajuste();

create or replace function public.solicitar_ajuste_ponto(
  p_token text,
  p_data date,
  p_tipo public.tipo_marcacao,
  p_horario time,
  p_justificativa text
)
returns public.solicitacoes_ajuste
language plpgsql security definer set search_path = public, extensions as $$
declare
  f public.funcionarios%rowtype;
  s public.solicitacoes_ajuste%rowtype;
begin
  f := public.funcionario_por_token(p_token);
  if p_data > (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Não é possível solicitar ajuste para uma data futura.';
  end if;
  if char_length(btrim(coalesce(p_justificativa,''))) < 10 then
    raise exception 'Informe uma justificativa com pelo menos 10 caracteres.';
  end if;
  if exists(select 1 from public.marcacoes where funcionario_id=f.id and data_local=p_data and tipo=p_tipo) then
    raise exception 'Essa marcação já existe. Para alterar um horário existente, procure o administrador.';
  end if;
  if exists(select 1 from public.solicitacoes_ajuste where funcionario_id=f.id and data_marcacao=p_data and tipo_marcacao=p_tipo and status='pendente') then
    raise exception 'Já existe uma solicitação pendente para essa marcação.';
  end if;
  insert into public.solicitacoes_ajuste(empresa_id,funcionario_id,data_marcacao,tipo_marcacao,horario_solicitado,justificativa)
  values(f.empresa_id,f.id,p_data,p_tipo,p_horario,btrim(p_justificativa)) returning * into s;
  return s;
end $$;

create or replace function public.listar_meus_ajustes(p_token text)
returns setof public.solicitacoes_ajuste
language plpgsql security definer set search_path = public, extensions as $$
declare f public.funcionarios%rowtype;
begin
  f := public.funcionario_por_token(p_token);
  return query select * from public.solicitacoes_ajuste where funcionario_id=f.id order by criado_em desc limit 50;
end $$;

create or replace function public.listar_ajustes_admin(p_status text default null)
returns table(
  id uuid, funcionario_id uuid, funcionario_nome text, matricula text,
  data_marcacao date, tipo_marcacao public.tipo_marcacao, horario_solicitado time,
  justificativa text, status text, resposta_administrador text,
  criado_em timestamptz, analisado_em timestamptz
)
language plpgsql security definer set search_path = public, extensions as $$
declare v_empresa uuid;
begin
  select empresa_id into v_empresa from public.perfis
  where id=auth.uid() and papel='administrador' and ativo=true;
  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  return query
  select s.id,s.funcionario_id,f.nome,f.matricula,s.data_marcacao,s.tipo_marcacao,
         s.horario_solicitado,s.justificativa,s.status,s.resposta_administrador,
         s.criado_em,s.analisado_em
  from public.solicitacoes_ajuste s join public.funcionarios f on f.id=s.funcionario_id
  where s.empresa_id=v_empresa and (p_status is null or p_status='' or s.status=p_status)
  order by case when s.status='pendente' then 0 else 1 end,s.criado_em desc;
end $$;

create or replace function public.analisar_ajuste_ponto(
  p_solicitacao_id uuid,
  p_decisao text,
  p_resposta text default null
)
returns public.solicitacoes_ajuste
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_empresa uuid;
  s public.solicitacoes_ajuste%rowtype;
  v_marcacao_id bigint;
  v_instante timestamptz;
begin
  select empresa_id into v_empresa from public.perfis
  where id=auth.uid() and papel='administrador' and ativo=true;
  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  if p_decisao not in ('aprovada','rejeitada') then raise exception 'Decisão inválida.'; end if;
  select * into s from public.solicitacoes_ajuste where id=p_solicitacao_id and empresa_id=v_empresa for update;
  if s.id is null then raise exception 'Solicitação não encontrada.'; end if;
  if s.status <> 'pendente' then raise exception 'Esta solicitação já foi analisada.'; end if;

  if p_decisao='aprovada' then
    if exists(select 1 from public.marcacoes where funcionario_id=s.funcionario_id and data_local=s.data_marcacao and tipo=s.tipo_marcacao) then
      raise exception 'A marcação solicitada já existe e a aprovação foi interrompida.';
    end if;
    v_instante := (s.data_marcacao + s.horario_solicitado) at time zone 'America/Sao_Paulo';
    insert into public.marcacoes(empresa_id,funcionario_id,tipo,registrado_em,data_local,origem,observacao,criado_por,ajustada)
    values(s.empresa_id,s.funcionario_id,s.tipo_marcacao,v_instante,s.data_marcacao,'ajuste_aprovado',
      'Incluída pela solicitação '||s.id::text||'. Justificativa: '||s.justificativa,auth.uid(),true)
    returning id into v_marcacao_id;
  end if;

  update public.solicitacoes_ajuste set status=p_decisao,resposta_administrador=nullif(btrim(coalesce(p_resposta,'')),''),
    marcacao_gerada_id=v_marcacao_id,analisado_por=auth.uid(),analisado_em=clock_timestamp()
  where id=s.id returning * into s;

  insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados)
  values(v_empresa,auth.uid(),'solicitacoes_ajuste',s.id::text,upper(p_decisao),
    jsonb_build_object('funcionario_id',s.funcionario_id,'data',s.data_marcacao,'tipo',s.tipo_marcacao,'horario',s.horario_solicitado,'marcacao_id',v_marcacao_id));
  return s;
end $$;

grant execute on function public.solicitar_ajuste_ponto(text,date,public.tipo_marcacao,time,text) to anon,authenticated;
grant execute on function public.listar_meus_ajustes(text) to anon,authenticated;
grant execute on function public.listar_ajustes_admin(text) to authenticated;
grant execute on function public.analisar_ajuste_ponto(uuid,text,text) to authenticated;
