begin;

-- RC5.0 — Modo de contingência offline
-- Registros offline são enviados para uma fila separada e exigem análise administrativa.

create table if not exists public.marcacoes_contingencia (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  dispositivo_id uuid not null references public.dispositivos_ponto(id),
  evento_offline_id uuid not null,
  tipo public.tipo_marcacao not null,
  ocorrido_em_dispositivo timestamptz not null,
  data_local date not null,
  fuso_horario text,
  offset_minutos integer,
  criado_local_em timestamptz,
  sincronizado_em timestamptz not null default clock_timestamp(),
  status text not null default 'pendente',
  conflito text,
  hash_evento text,
  hash_anterior text,
  user_agent text,
  aprovado_por uuid references auth.users(id),
  aprovado_em timestamptz,
  observacao_admin text,
  marcacao_oficial_id uuid references public.marcacoes(id),
  criado_em timestamptz not null default clock_timestamp(),
  atualizado_em timestamptz not null default clock_timestamp(),
  unique(dispositivo_id, evento_offline_id),
  constraint marcacoes_contingencia_status_check
    check(status in ('pendente','aprovado','rejeitado','duplicado','conflitante'))
);

create index if not exists idx_contingencia_empresa_status_data
  on public.marcacoes_contingencia(empresa_id,status,data_local desc);

alter table public.marcacoes_contingencia enable row level security;

drop policy if exists contingencia_admin_select on public.marcacoes_contingencia;
create policy contingencia_admin_select
on public.marcacoes_contingencia
for select to authenticated
using (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

create or replace function public.sincronizar_marcacao_contingencia(
  p_dispositivo_token text,
  p_evento_offline_id uuid,
  p_funcionario_id uuid,
  p_tipo text,
  p_ocorrido_em_dispositivo timestamptz,
  p_data_local date,
  p_fuso_horario text default null,
  p_offset_minutos integer default null,
  p_criado_local_em timestamptz default null,
  p_hash_evento text default null,
  p_hash_anterior text default null,
  p_user_agent text default null
)
returns public.marcacoes_contingencia
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_result public.marcacoes_contingencia%rowtype;
  v_tipo public.tipo_marcacao;
  v_conflito text;
begin
  select d.* into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash=encode(digest(coalesce(p_dispositivo_token,''),'sha256'),'hex')
    and d.ativo=true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Dispositivo não autorizado para sincronizar contingência.';
  end if;

  select f.* into v_funcionario
  from public.funcionarios f
  where f.id=p_funcionario_id
    and f.empresa_id=v_dispositivo.empresa_id
    and f.ativo=true;

  if v_funcionario.id is null then
    raise exception 'Funcionário inválido para este dispositivo.';
  end if;

  begin
    v_tipo:=p_tipo::public.tipo_marcacao;
  exception when others then
    raise exception 'Tipo de marcação offline inválido.';
  end;

  if p_ocorrido_em_dispositivo > clock_timestamp()+interval '10 minutes' then
    v_conflito:='Horário do dispositivo está no futuro.';
  elsif abs(extract(epoch from(clock_timestamp()-p_ocorrido_em_dispositivo))) > 86400*7 then
    v_conflito:='Horário do dispositivo difere mais de 7 dias do servidor.';
  elsif exists(
    select 1 from public.marcacoes m
    where m.funcionario_id=p_funcionario_id
      and m.data_local=p_data_local
      and m.tipo=v_tipo
  ) then
    v_conflito:='Já existe marcação oficial do mesmo tipo nesta data.';
  end if;

  insert into public.marcacoes_contingencia(
    empresa_id,funcionario_id,dispositivo_id,evento_offline_id,tipo,
    ocorrido_em_dispositivo,data_local,fuso_horario,offset_minutos,
    criado_local_em,status,conflito,hash_evento,hash_anterior,user_agent
  )
  values(
    v_dispositivo.empresa_id,p_funcionario_id,v_dispositivo.id,p_evento_offline_id,v_tipo,
    p_ocorrido_em_dispositivo,p_data_local,left(p_fuso_horario,80),p_offset_minutos,
    p_criado_local_em,case when v_conflito is null then 'pendente' else 'conflitante' end,
    v_conflito,p_hash_evento,p_hash_anterior,left(p_user_agent,1000)
  )
  on conflict(dispositivo_id,evento_offline_id)
  do update set sincronizado_em=clock_timestamp()
  returning * into v_result;

  update public.dispositivos_ponto
  set ultimo_uso_em=clock_timestamp()
  where id=v_dispositivo.id;

  return v_result;
end;
$$;

create or replace function public.listar_contingencias_admin(
  p_status text default null,
  p_inicio date default null,
  p_fim date default null
)
returns table(
  id uuid,
  funcionario_nome text,
  matricula text,
  dispositivo_nome text,
  tipo text,
  ocorrido_em_dispositivo timestamptz,
  data_local date,
  sincronizado_em timestamptz,
  status text,
  conflito text,
  observacao_admin text
)
language plpgsql
security definer
set search_path=public
as $$
declare v_empresa uuid;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  v_empresa:=public.empresa_do_usuario();

  return query
  select c.id,f.nome::text,f.matricula::text,d.nome::text,c.tipo::text,
         c.ocorrido_em_dispositivo,c.data_local,c.sincronizado_em,c.status,
         c.conflito,c.observacao_admin
  from public.marcacoes_contingencia c
  join public.funcionarios f on f.id=c.funcionario_id
  join public.dispositivos_ponto d on d.id=c.dispositivo_id
  where c.empresa_id=v_empresa
    and (p_status is null or p_status='' or c.status=p_status)
    and (p_inicio is null or c.data_local>=p_inicio)
    and (p_fim is null or c.data_local<=p_fim)
  order by c.data_local desc,c.ocorrido_em_dispositivo desc;
end;
$$;

create or replace function public.analisar_contingencia_admin(
  p_id uuid,
  p_acao text,
  p_observacao text default null,
  p_horario_corrigido timestamptz default null
)
returns public.marcacoes_contingencia
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_c public.marcacoes_contingencia%rowtype;
  v_mark public.marcacoes%rowtype;
  v_horario timestamptz;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  v_empresa:=public.empresa_do_usuario();

  select * into v_c
  from public.marcacoes_contingencia
  where id=p_id and empresa_id=v_empresa
  for update;

  if v_c.id is null then raise exception 'Registro não encontrado.'; end if;
  if v_c.status not in ('pendente','conflitante') then
    raise exception 'Registro já analisado.';
  end if;

  if p_acao='aprovar' then
    v_horario:=coalesce(p_horario_corrigido,v_c.ocorrido_em_dispositivo);

    if exists(
      select 1 from public.marcacoes m
      where m.funcionario_id=v_c.funcionario_id
        and m.data_local=v_c.data_local
        and m.tipo=v_c.tipo
    ) then
      update public.marcacoes_contingencia
      set status='duplicado',observacao_admin=coalesce(nullif(trim(p_observacao),''),'Duplicidade detectada na aprovação'),
          aprovado_por=auth.uid(),aprovado_em=clock_timestamp(),atualizado_em=clock_timestamp()
      where id=p_id returning * into v_c;
      return v_c;
    end if;

    insert into public.marcacoes(
      empresa_id,funcionario_id,tipo,registrado_em,data_local,origem
    ) values(
      v_c.empresa_id,v_c.funcionario_id,v_c.tipo,v_horario,
      (v_horario at time zone 'America/Sao_Paulo')::date,'contingencia'
    )
    returning * into v_mark;

    update public.marcacoes_contingencia
    set status='aprovado',marcacao_oficial_id=v_mark.id,
        observacao_admin=nullif(trim(p_observacao),''),
        aprovado_por=auth.uid(),aprovado_em=clock_timestamp(),atualizado_em=clock_timestamp()
    where id=p_id returning * into v_c;

  elsif p_acao='rejeitar' then
    if length(trim(coalesce(p_observacao,'')))<5 then
      raise exception 'Informe o motivo da rejeição.';
    end if;

    update public.marcacoes_contingencia
    set status='rejeitado',observacao_admin=trim(p_observacao),
        aprovado_por=auth.uid(),aprovado_em=clock_timestamp(),atualizado_em=clock_timestamp()
    where id=p_id returning * into v_c;
  else
    raise exception 'Ação inválida.';
  end if;

  insert into public.logs_auditoria(
    empresa_id,usuario_id,tabela,registro_id,acao,dados_novos,origem,descricao
  ) values(
    v_empresa,auth.uid(),'marcacoes_contingencia',v_c.id::text,
    case when p_acao='aprovar' then 'CONTINGENCIA_APROVADA' else 'CONTINGENCIA_REJEITADA' end,
    to_jsonb(v_c),'web','Registro offline analisado pelo administrador.'
  );

  return v_c;
end;
$$;

revoke all on function public.sincronizar_marcacao_contingencia(
  text,uuid,uuid,text,timestamptz,date,text,integer,timestamptz,text,text,text
) from public;
grant execute on function public.sincronizar_marcacao_contingencia(
  text,uuid,uuid,text,timestamptz,date,text,integer,timestamptz,text,text,text
) to anon,authenticated;

revoke all on function public.listar_contingencias_admin(text,date,date) from public,anon;
grant execute on function public.listar_contingencias_admin(text,date,date) to authenticated;

revoke all on function public.analisar_contingencia_admin(uuid,text,text,timestamptz) from public,anon;
grant execute on function public.analisar_contingencia_admin(uuid,text,text,timestamptz) to authenticated;

commit;
notify pgrst,'reload schema';
