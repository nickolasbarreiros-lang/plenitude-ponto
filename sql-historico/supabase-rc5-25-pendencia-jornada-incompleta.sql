-- Plenitude Ponto RC5.25
-- Geração automática de pendências para jornadas incompletas de dias anteriores.

begin;

create table if not exists public.pendencias_jornada (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  data_local date not null,
  quantidade_marcacoes integer not null check (quantidade_marcacoes between 1 and 3),
  marcacao_faltante text not null,
  status text not null default 'pendente'
    check (status in ('pendente','resolvida','arquivada')),
  detectada_em timestamptz not null default clock_timestamp(),
  resolvida_em timestamptz,
  observacao text,
  atualizado_em timestamptz not null default clock_timestamp(),
  unique (funcionario_id,data_local)
);

create index if not exists idx_pendencias_jornada_empresa_status
  on public.pendencias_jornada(empresa_id,status,data_local);

alter table public.pendencias_jornada enable row level security;

-- Converte a quantidade já registrada na próxima marcação que ficou faltando.
create or replace function public.tipo_marcacao_faltante_jornada(
  p_quantidade integer
)
returns text
language sql
immutable
as $$
  select case p_quantidade
    when 1 then 'inicio_intervalo'
    when 2 then 'fim_intervalo'
    when 3 then 'saida'
    else 'entrada'
  end;
$$;

create or replace function public.rotulo_marcacao_jornada(
  p_tipo text
)
returns text
language sql
immutable
as $$
  select case p_tipo
    when 'entrada' then 'Entrada'
    when 'inicio_intervalo' then 'Início do almoço'
    when 'fim_intervalo' then 'Retorno do almoço'
    when 'saida' then 'Saída'
    else 'Marcação'
  end;
$$;

-- Núcleo idempotente. Pode ser executado diversas vezes.
create or replace function public.atualizar_pendencias_jornada_empresa(
  p_empresa_id uuid,
  p_funcionario_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer:=0;
begin
  -- Resolve automaticamente quando o dia passa a possuir quatro marcações.
  update public.pendencias_jornada p
     set status='resolvida',
         resolvida_em=coalesce(p.resolvida_em,clock_timestamp()),
         atualizado_em=clock_timestamp(),
         observacao=coalesce(p.observacao,'Regularizada por marcação ou ajuste posterior.')
   where p.empresa_id=p_empresa_id
     and p.status='pendente'
     and (p_funcionario_id is null or p.funcionario_id=p_funcionario_id)
     and (
       select count(*)
       from public.marcacoes m
       where m.funcionario_id=p.funcionario_id
         and m.data_local=p.data_local
     )>=4;

  -- Gera pendência para qualquer dia anterior com 1, 2 ou 3 marcações.
  insert into public.pendencias_jornada(
    empresa_id,
    funcionario_id,
    data_local,
    quantidade_marcacoes,
    marcacao_faltante,
    status,
    detectada_em,
    atualizado_em
  )
  select
    f.empresa_id,
    f.id,
    m.data_local,
    count(*)::integer,
    public.tipo_marcacao_faltante_jornada(count(*)::integer),
    'pendente',
    clock_timestamp(),
    clock_timestamp()
  from public.marcacoes m
  join public.funcionarios f on f.id=m.funcionario_id
  where f.empresa_id=p_empresa_id
    and f.ativo=true
    and m.data_local<current_date
    and (p_funcionario_id is null or f.id=p_funcionario_id)
  group by f.empresa_id,f.id,m.data_local
  having count(*) between 1 and 3
  on conflict (funcionario_id,data_local)
  do update set
    quantidade_marcacoes=excluded.quantidade_marcacoes,
    marcacao_faltante=excluded.marcacao_faltante,
    status='pendente',
    resolvida_em=null,
    atualizado_em=clock_timestamp();

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function public.atualizar_pendencias_jornada_admin()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user uuid:=auth.uid();
  v_empresa uuid;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id=v_user
    and p.papel='administrador';

  if v_empresa is null then
    raise exception 'Acesso administrativo necessário.';
  end if;

  return public.atualizar_pendencias_jornada_empresa(v_empresa,null);
end;
$$;

create or replace function public.listar_pendencias_jornada_admin()
returns table(
  id uuid,
  funcionario_id uuid,
  funcionario_nome text,
  matricula text,
  data_local date,
  quantidade_marcacoes integer,
  marcacao_faltante text,
  marcacao_faltante_label text,
  status text,
  detectada_em timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user uuid:=auth.uid();
  v_empresa uuid;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id=v_user
    and p.papel='administrador';

  if v_empresa is null then
    raise exception 'Acesso administrativo necessário.';
  end if;

  perform public.atualizar_pendencias_jornada_empresa(v_empresa,null);

  return query
  select
    pj.id,
    pj.funcionario_id,
    f.nome,
    f.matricula,
    pj.data_local,
    pj.quantidade_marcacoes,
    pj.marcacao_faltante,
    public.rotulo_marcacao_jornada(pj.marcacao_faltante),
    pj.status,
    pj.detectada_em
  from public.pendencias_jornada pj
  join public.funcionarios f on f.id=pj.funcionario_id
  where pj.empresa_id=v_empresa
    and pj.status='pendente'
  order by pj.data_local,pj.detectada_em;
end;
$$;

create or replace function public.listar_minhas_pendencias_jornada(
  p_token text
)
returns table(
  id uuid,
  data_local date,
  quantidade_marcacoes integer,
  marcacao_faltante text,
  marcacao_faltante_label text,
  status text,
  detectada_em timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_funcionario_id uuid;
  v_empresa_id uuid;
begin
  -- Usa a mesma tabela de sessões já validada pelas demais funções do ponto.
  select sf.funcionario_id, f.empresa_id
    into v_funcionario_id,v_empresa_id
  from public.sessoes_funcionario sf
  join public.funcionarios f on f.id=sf.funcionario_id
  where sf.token=p_token
    and sf.ativo=true
    and sf.expira_em>clock_timestamp()
  limit 1;

  if v_funcionario_id is null then
    raise exception 'Sessão expirada. Entre novamente.';
  end if;

  perform public.atualizar_pendencias_jornada_empresa(
    v_empresa_id,
    v_funcionario_id
  );

  return query
  select
    pj.id,
    pj.data_local,
    pj.quantidade_marcacoes,
    pj.marcacao_faltante,
    public.rotulo_marcacao_jornada(pj.marcacao_faltante),
    pj.status,
    pj.detectada_em
  from public.pendencias_jornada pj
  where pj.funcionario_id=v_funcionario_id
    and pj.status='pendente'
  order by pj.data_local;
end;
$$;

revoke all on function public.atualizar_pendencias_jornada_admin() from public,anon;
grant execute on function public.atualizar_pendencias_jornada_admin()
  to authenticated;

revoke all on function public.listar_pendencias_jornada_admin() from public,anon;
grant execute on function public.listar_pendencias_jornada_admin()
  to authenticated;

revoke all on function public.listar_minhas_pendencias_jornada(text) from public;
grant execute on function public.listar_minhas_pendencias_jornada(text)
  to anon,authenticated;

commit;

notify pgrst,'reload schema';
