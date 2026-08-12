-- Plenitude Ponto RC5.61
-- Gerenciamento administrativo de marcações com dois níveis de exclusão.
--
-- Nível 1: arquiva a marcação, remove da jornada oficial e preserva cópia completa.
-- Nível 2: remove definitivamente a marcação ativa ou arquivada, preservando apenas
--          o evento de auditoria e exigindo PIN Mestre.

begin;

create table if not exists public.marcacoes_arquivadas (
  id uuid primary key default gen_random_uuid(),
  marcacao_id_original bigint not null,
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  tipo public.tipo_marcacao not null,
  registrado_em timestamptz not null,
  data_local date not null,
  origem text,
  ajustada boolean,
  criado_por uuid,
  snapshot jsonb not null,
  motivo text not null,
  arquivada_por uuid not null references auth.users(id),
  arquivada_em timestamptz not null default clock_timestamp()
);

create unique index if not exists uq_marcacoes_arquivadas_original
  on public.marcacoes_arquivadas(marcacao_id_original);

create index if not exists idx_marcacoes_arquivadas_empresa_data
  on public.marcacoes_arquivadas(empresa_id,data_local desc);

alter table public.marcacoes_arquivadas enable row level security;

drop policy if exists marcacoes_arquivadas_select on public.marcacoes_arquivadas;
drop policy if exists marcacoes_arquivadas_insert on public.marcacoes_arquivadas;
drop policy if exists marcacoes_arquivadas_update on public.marcacoes_arquivadas;
drop policy if exists marcacoes_arquivadas_delete on public.marcacoes_arquivadas;


create or replace function public.competencia_marcacao_aberta_admin(
  p_empresa_id uuid,
  p_data date
)
returns boolean
language sql
security definer
set search_path=public
as $$
  select not exists(
    select 1
    from public.fechamentos_mensais f
    where f.empresa_id=p_empresa_id
      and f.ano=extract(year from p_data)::integer
      and f.mes=extract(month from p_data)::integer
      and f.status='fechado'
  );
$$;


create or replace function public.listar_marcacoes_gerenciamento_admin(
  p_funcionario_id uuid default null,
  p_inicio date default null,
  p_fim date default null,
  p_incluir_arquivadas boolean default true
)
returns table(
  chave text,
  id_original bigint,
  arquivo_id uuid,
  funcionario_id uuid,
  funcionario_nome text,
  matricula text,
  data_local date,
  tipo text,
  registrado_em timestamptz,
  origem text,
  estado text,
  motivo text,
  alterado_em timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_inicio date:=coalesce(p_inicio,current_date-interval '31 days');
  v_fim date:=coalesce(p_fim,current_date);
begin
  if not public.usuario_e_admin() then
    raise exception 'Apenas administradores podem gerenciar marcações.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  return query
  select
    'ativa:'||m.id::text,
    m.id,
    null::uuid,
    m.funcionario_id,
    f.nome,
    f.matricula,
    m.data_local,
    m.tipo::text,
    m.registrado_em,
    m.origem,
    'ativa'::text,
    null::text,
    null::timestamptz
  from public.marcacoes m
  join public.funcionarios f on f.id=m.funcionario_id
  where m.empresa_id=v_empresa
    and m.data_local between v_inicio and v_fim
    and (p_funcionario_id is null or m.funcionario_id=p_funcionario_id)

  union all

  select
    'arquivada:'||a.id::text,
    a.marcacao_id_original,
    a.id,
    a.funcionario_id,
    f.nome,
    f.matricula,
    a.data_local,
    a.tipo::text,
    a.registrado_em,
    a.origem,
    'arquivada'::text,
    a.motivo,
    a.arquivada_em
  from public.marcacoes_arquivadas a
  join public.funcionarios f on f.id=a.funcionario_id
  where p_incluir_arquivadas=true
    and a.empresa_id=v_empresa
    and a.data_local between v_inicio and v_fim
    and (p_funcionario_id is null or a.funcionario_id=p_funcionario_id)

  order by data_local desc,registrado_em desc;
end;
$$;


create or replace function public.excluir_marcacao_logica_admin(
  p_marcacao_id bigint,
  p_motivo text
)
returns table(
  arquivo_id uuid,
  marcacao_id_original bigint,
  status text
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_marcacao public.marcacoes%rowtype;
  v_arquivo uuid;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if length(trim(coalesce(p_motivo,'')))<8 then
    raise exception 'Informe um motivo com pelo menos 8 caracteres.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  select *
    into v_marcacao
  from public.marcacoes m
  where m.id=p_marcacao_id
    and m.empresa_id=v_empresa
  for update;

  if v_marcacao.id is null then
    raise exception 'Marcação ativa não encontrada.';
  end if;

  if not public.competencia_marcacao_aberta_admin(v_empresa,v_marcacao.data_local) then
    raise exception 'A competência está fechada. Reabra o mês antes de excluir a marcação.';
  end if;

  insert into public.marcacoes_arquivadas(
    marcacao_id_original,
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem,
    ajustada,
    criado_por,
    snapshot,
    motivo,
    arquivada_por
  )
  values(
    v_marcacao.id,
    v_marcacao.empresa_id,
    v_marcacao.funcionario_id,
    v_marcacao.tipo,
    v_marcacao.registrado_em,
    v_marcacao.data_local,
    v_marcacao.origem,
    v_marcacao.ajustada,
    v_marcacao.criado_por,
    to_jsonb(v_marcacao),
    trim(p_motivo),
    auth.uid()
  )
  returning id into v_arquivo;

  delete from public.marcacoes
  where id=v_marcacao.id;

  perform public.registrar_evento_auditoria(
    'ARQUIVAR_MARCACAO',
    'marcacoes',
    v_marcacao.id::text,
    'Marcação removida da jornada oficial com cópia preservada para auditoria',
    jsonb_build_object(
      'nivel',1,
      'arquivo_id',v_arquivo,
      'funcionario_id',v_marcacao.funcionario_id,
      'data_local',v_marcacao.data_local,
      'tipo',v_marcacao.tipo,
      'registrado_em',v_marcacao.registrado_em,
      'motivo',trim(p_motivo)
    ),
    'web'
  );

  return query
  select v_arquivo,v_marcacao.id,'arquivada'::text;
end;
$$;


create or replace function public.excluir_marcacao_definitiva_admin(
  p_marcacao_id bigint default null,
  p_arquivo_id uuid default null,
  p_motivo text default null,
  p_confirmacao text default null,
  p_master_pin text default null
)
returns table(
  id_original bigint,
  status text
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_marcacao public.marcacoes%rowtype;
  v_arquivo public.marcacoes_arquivadas%rowtype;
  v_id bigint;
  v_resumo jsonb;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if upper(trim(coalesce(p_confirmacao,'')))<>'EXCLUIR' then
    raise exception 'Digite EXCLUIR para confirmar a remoção definitiva.';
  end if;

  if length(trim(coalesce(p_motivo,'')))<12 then
    raise exception 'Informe um motivo detalhado com pelo menos 12 caracteres.';
  end if;

  v_empresa:=public.empresa_do_usuario();
  perform public.validar_pin_mestre_interno(v_empresa,p_master_pin);

  if p_arquivo_id is not null then
    select *
      into v_arquivo
    from public.marcacoes_arquivadas a
    where a.id=p_arquivo_id
      and a.empresa_id=v_empresa
    for update;

    if v_arquivo.id is null then
      raise exception 'Marcação arquivada não encontrada.';
    end if;

    if not public.competencia_marcacao_aberta_admin(v_empresa,v_arquivo.data_local) then
      raise exception 'A competência está fechada. Reabra o mês antes da exclusão definitiva.';
    end if;

    v_id:=v_arquivo.marcacao_id_original;
    v_resumo:=jsonb_build_object(
      'origem','arquivo',
      'funcionario_id',v_arquivo.funcionario_id,
      'data_local',v_arquivo.data_local,
      'tipo',v_arquivo.tipo,
      'registrado_em',v_arquivo.registrado_em
    );

    delete from public.marcacoes_arquivadas
    where id=v_arquivo.id;

  elsif p_marcacao_id is not null then
    select *
      into v_marcacao
    from public.marcacoes m
    where m.id=p_marcacao_id
      and m.empresa_id=v_empresa
    for update;

    if v_marcacao.id is null then
      raise exception 'Marcação ativa não encontrada.';
    end if;

    if not public.competencia_marcacao_aberta_admin(v_empresa,v_marcacao.data_local) then
      raise exception 'A competência está fechada. Reabra o mês antes da exclusão definitiva.';
    end if;

    v_id:=v_marcacao.id;
    v_resumo:=jsonb_build_object(
      'origem','ativa',
      'funcionario_id',v_marcacao.funcionario_id,
      'data_local',v_marcacao.data_local,
      'tipo',v_marcacao.tipo,
      'registrado_em',v_marcacao.registrado_em
    );

    delete from public.marcacoes
    where id=v_marcacao.id;
  else
    raise exception 'Informe a marcação que será excluída.';
  end if;

  -- A marcação e sua cópia completa deixam de existir. Permanece apenas
  -- o registro mínimo da ação administrativa na auditoria.
  perform public.registrar_evento_auditoria(
    'EXCLUIR_MARCACAO_DEFINITIVA',
    'marcacoes',
    v_id::text,
    'Marcação excluída definitivamente com confirmação e PIN Mestre',
    v_resumo||jsonb_build_object(
      'nivel',2,
      'motivo',trim(p_motivo),
      'confirmacao','EXCLUIR'
    ),
    'web'
  );

  return query select v_id,'excluida_definitivamente'::text;
end;
$$;


revoke all on function public.competencia_marcacao_aberta_admin(uuid,date)
  from public,anon,authenticated;

revoke all on function public.listar_marcacoes_gerenciamento_admin(uuid,date,date,boolean)
  from public,anon;

grant execute on function public.listar_marcacoes_gerenciamento_admin(uuid,date,date,boolean)
  to authenticated;

revoke all on function public.excluir_marcacao_logica_admin(bigint,text)
  from public,anon;

grant execute on function public.excluir_marcacao_logica_admin(bigint,text)
  to authenticated;

revoke all on function public.excluir_marcacao_definitiva_admin(bigint,uuid,text,text,text)
  from public,anon;

grant execute on function public.excluir_marcacao_definitiva_admin(bigint,uuid,text,text,text)
  to authenticated;

commit;

notify pgrst,'reload schema';
