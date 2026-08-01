-- Plenitude Ponto RC5.39
-- Controle dos espelhos mensais impressos e assinados em papel.

begin;

create table if not exists public.espelhos_mensais (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  ano integer not null check (ano between 2020 and 2100),
  mes integer not null check (mes between 1 and 12),
  status text not null default 'pendente'
    check (status in ('pendente','assinado')),
  assinado_em date,
  registrado_por uuid references auth.users(id) on delete set null,
  observacao text,
  criado_em timestamptz not null default clock_timestamp(),
  atualizado_em timestamptz not null default clock_timestamp(),
  unique (empresa_id,funcionario_id,ano,mes)
);

create index if not exists idx_espelhos_mensais_competencia
  on public.espelhos_mensais(empresa_id,ano desc,mes desc,status);

alter table public.espelhos_mensais enable row level security;

drop policy if exists espelhos_mensais_select_admin
  on public.espelhos_mensais;

create policy espelhos_mensais_select_admin
on public.espelhos_mensais
for select
to authenticated
using (
  empresa_id=public.empresa_do_usuario()
  and public.usuario_e_admin()
);

create or replace function public.listar_espelhos_competencia_admin(
  p_ano integer,
  p_mes integer
)
returns table(
  id uuid,
  funcionario_id uuid,
  funcionario_nome text,
  matricula text,
  cargo text,
  status text,
  assinado_em date,
  observacao text,
  registrado_por_nome text,
  atualizado_em timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if p_ano not between 2020 and 2100 or p_mes not between 1 and 12 then
    raise exception 'Competência inválida.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  if not exists(
    select 1
    from public.fechamentos_mensais fm
    where fm.empresa_id=v_empresa
      and fm.ano=p_ano
      and fm.mes=p_mes
      and fm.status='fechado'
  ) then
    raise exception 'A competência precisa estar fechada para controlar os espelhos.';
  end if;

  insert into public.espelhos_mensais(
    empresa_id,
    funcionario_id,
    ano,
    mes,
    status
  )
  select
    v_empresa,
    f.id,
    p_ano,
    p_mes,
    'pendente'
  from public.funcionarios f
  where f.empresa_id=v_empresa
    and f.ativo=true
  on conflict (empresa_id,funcionario_id,ano,mes)
  do nothing;

  return query
  select
    em.id,
    em.funcionario_id,
    f.nome,
    f.matricula,
    f.cargo,
    em.status,
    em.assinado_em,
    em.observacao,
    p.nome,
    em.atualizado_em
  from public.espelhos_mensais em
  join public.funcionarios f
    on f.id=em.funcionario_id
  left join public.perfis p
    on p.id=em.registrado_por
  where em.empresa_id=v_empresa
    and em.ano=p_ano
    and em.mes=p_mes
  order by
    case when em.status='pendente' then 0 else 1 end,
    f.nome;
end;
$$;

create or replace function public.atualizar_status_espelho_admin(
  p_funcionario_id uuid,
  p_ano integer,
  p_mes integer,
  p_status text,
  p_assinado_em date default null,
  p_observacao text default null
)
returns public.espelhos_mensais
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_result public.espelhos_mensais%rowtype;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if p_status not in ('pendente','assinado') then
    raise exception 'Status inválido.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  if not exists(
    select 1
    from public.funcionarios f
    where f.id=p_funcionario_id
      and f.empresa_id=v_empresa
  ) then
    raise exception 'Funcionário não encontrado.';
  end if;

  if not exists(
    select 1
    from public.fechamentos_mensais fm
    where fm.empresa_id=v_empresa
      and fm.ano=p_ano
      and fm.mes=p_mes
      and fm.status='fechado'
  ) then
    raise exception 'A competência precisa estar fechada.';
  end if;

  if p_status='assinado' and p_assinado_em is null then
    raise exception 'Informe a data da assinatura.';
  end if;

  insert into public.espelhos_mensais(
    empresa_id,
    funcionario_id,
    ano,
    mes,
    status,
    assinado_em,
    registrado_por,
    observacao,
    atualizado_em
  )
  values(
    v_empresa,
    p_funcionario_id,
    p_ano,
    p_mes,
    p_status,
    case when p_status='assinado' then p_assinado_em else null end,
    auth.uid(),
    nullif(trim(coalesce(p_observacao,'')),''),
    clock_timestamp()
  )
  on conflict (empresa_id,funcionario_id,ano,mes)
  do update set
    status=excluded.status,
    assinado_em=excluded.assinado_em,
    registrado_por=excluded.registrado_por,
    observacao=excluded.observacao,
    atualizado_em=clock_timestamp()
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.listar_espelhos_competencia_admin(integer,integer)
  from public,anon;

grant execute on function public.listar_espelhos_competencia_admin(integer,integer)
  to authenticated;

revoke all on function public.atualizar_status_espelho_admin(
  uuid,integer,integer,text,date,text
) from public,anon;

grant execute on function public.atualizar_status_espelho_admin(
  uuid,integer,integer,text,date,text
) to authenticated;

commit;

notify pgrst,'reload schema';
