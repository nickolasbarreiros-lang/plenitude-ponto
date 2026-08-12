-- Plenitude Ponto V22 — Auditoria e reforço de segurança
-- Execute após as migrações anteriores.

begin;

alter table public.logs_auditoria
  add column if not exists dados_anteriores jsonb,
  add column if not exists dados_novos jsonb,
  add column if not exists origem text not null default 'sistema',
  add column if not exists descricao text;

create index if not exists idx_logs_auditoria_empresa_criado
  on public.logs_auditoria (empresa_id, criado_em desc);
create index if not exists idx_logs_auditoria_acao
  on public.logs_auditoria (acao);
create index if not exists idx_logs_auditoria_tabela
  on public.logs_auditoria (tabela);

-- Centraliza a gravação de eventos administrativos.
create or replace function public.registrar_evento_auditoria(
  p_acao text,
  p_tabela text default 'sistema',
  p_registro_id text default null,
  p_descricao text default null,
  p_dados_novos jsonb default null,
  p_origem text default 'web'
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_perfil public.perfis%rowtype;
  v_id bigint;
begin
  select * into v_perfil
  from public.perfis
  where id = auth.uid() and ativo = true;

  if v_perfil.id is null then
    raise exception 'Sessão inválida ou perfil inativo.';
  end if;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, tabela, registro_id, acao,
    dados, dados_novos, origem, descricao
  ) values (
    v_perfil.empresa_id, auth.uid(), coalesce(nullif(trim(p_tabela),''),'sistema'),
    p_registro_id, upper(coalesce(nullif(trim(p_acao),''),'EVENTO')),
    p_dados_novos, p_dados_novos, coalesce(nullif(trim(p_origem),''),'web'), p_descricao
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.registrar_evento_auditoria(text,text,text,text,jsonb,text) from public, anon;
grant execute on function public.registrar_evento_auditoria(text,text,text,text,jsonb,text) to authenticated;

-- Trigger reutilizável para alterações diretas nas tabelas críticas.
create or replace function public.auditar_alteracao_tabela()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_registro text;
  v_old jsonb;
  v_new jsonb;
begin
  v_old := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  v_new := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  v_empresa := coalesce((v_new->>'empresa_id')::uuid, (v_old->>'empresa_id')::uuid, public.empresa_do_usuario());
  v_registro := coalesce(v_new->>'id', v_old->>'id');

  insert into public.logs_auditoria(
    empresa_id, usuario_id, tabela, registro_id, acao,
    dados, dados_anteriores, dados_novos, origem, descricao
  ) values (
    v_empresa, auth.uid(), tg_table_name, v_registro, tg_op,
    coalesce(v_new,v_old), v_old, v_new, 'trigger',
    case tg_op when 'INSERT' then 'Registro criado' when 'UPDATE' then 'Registro alterado' else 'Registro excluído' end
  );

  return coalesce(new,old);
end;
$$;

-- Evita duplicar INSERT de marcação, que já é auditado pelas RPCs.
drop trigger if exists trg_auditar_funcionarios on public.funcionarios;
create trigger trg_auditar_funcionarios after insert or update or delete on public.funcionarios
for each row execute function public.auditar_alteracao_tabela();

drop trigger if exists trg_auditar_jornadas on public.jornadas;
create trigger trg_auditar_jornadas after insert or update or delete on public.jornadas
for each row execute function public.auditar_alteracao_tabela();

drop trigger if exists trg_auditar_ocorrencias on public.ocorrencias;
create trigger trg_auditar_ocorrencias after insert or update or delete on public.ocorrencias
for each row execute function public.auditar_alteracao_tabela();

drop trigger if exists trg_auditar_empresas on public.empresas;
create trigger trg_auditar_empresas after update on public.empresas
for each row execute function public.auditar_alteracao_tabela();

drop trigger if exists trg_auditar_marcacoes_ud on public.marcacoes;
create trigger trg_auditar_marcacoes_ud after update or delete on public.marcacoes
for each row execute function public.auditar_alteracao_tabela();

-- Consulta segura e paginada: somente administradores da própria empresa.
create or replace function public.listar_auditoria_admin(
  p_inicio timestamptz default null,
  p_fim timestamptz default null,
  p_acao text default null,
  p_tabela text default null,
  p_busca text default null,
  p_limite integer default 200,
  p_offset integer default 0
)
returns table(
  id bigint,
  criado_em timestamptz,
  usuario_id uuid,
  usuario_nome text,
  usuario_email text,
  acao text,
  tabela text,
  registro_id text,
  descricao text,
  origem text,
  dados_anteriores jsonb,
  dados_novos jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso permitido somente ao administrador.';
  end if;
  v_empresa := public.empresa_do_usuario();

  return query
  select l.id, l.criado_em, l.usuario_id,
         coalesce(p.nome,'Sistema') as usuario_nome,
         coalesce(u.email,'—')::text as usuario_email,
         l.acao, l.tabela, l.registro_id,
         coalesce(l.descricao,'') as descricao,
         coalesce(l.origem,'sistema') as origem,
         coalesce(l.dados_anteriores, case when l.acao='UPDATE' then null else null end),
         coalesce(l.dados_novos,l.dados)
  from public.logs_auditoria l
  left join public.perfis p on p.id=l.usuario_id
  left join auth.users u on u.id=l.usuario_id
  where l.empresa_id=v_empresa
    and (p_inicio is null or l.criado_em >= p_inicio)
    and (p_fim is null or l.criado_em <= p_fim)
    and (p_acao is null or p_acao='' or upper(l.acao)=upper(p_acao))
    and (p_tabela is null or p_tabela='' or l.tabela=p_tabela)
    and (p_busca is null or p_busca='' or
      concat_ws(' ',l.acao,l.tabela,l.registro_id,l.descricao,p.nome,u.email,l.dados::text,l.dados_novos::text) ilike '%'||p_busca||'%')
  order by l.criado_em desc
  limit greatest(1,least(coalesce(p_limite,200),500))
  offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on function public.listar_auditoria_admin(timestamptz,timestamptz,text,text,text,integer,integer) from public, anon;
grant execute on function public.listar_auditoria_admin(timestamptz,timestamptz,text,text,text,integer,integer) to authenticated;

-- Resumo de segurança para a tela de auditoria.
create or replace function public.resumo_seguranca_admin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_empresa uuid;
begin
  if not public.usuario_e_admin() then raise exception 'Acesso negado.'; end if;
  v_empresa:=public.empresa_do_usuario();
  return jsonb_build_object(
    'eventos_24h',(select count(*) from public.logs_auditoria where empresa_id=v_empresa and criado_em>=now()-interval '24 hours'),
    'logins_30d',(select count(*) from public.logs_auditoria where empresa_id=v_empresa and acao='LOGIN' and criado_em>=now()-interval '30 days'),
    'alteracoes_30d',(select count(*) from public.logs_auditoria where empresa_id=v_empresa and acao in ('UPDATE','DELETE','APROVAR','REJEITAR') and criado_em>=now()-interval '30 days'),
    'ultimo_evento',(select max(criado_em) from public.logs_auditoria where empresa_id=v_empresa),
    'rls_ativo',true,
    'horario_servidor',clock_timestamp()
  );
end;
$$;

revoke all on function public.resumo_seguranca_admin() from public, anon;
grant execute on function public.resumo_seguranca_admin() to authenticated;

-- RLS explícita: leitura direta somente por administradores da própria empresa.
alter table public.logs_auditoria enable row level security;
drop policy if exists logs_select_admin_mesma_empresa on public.logs_auditoria;
create policy logs_select_admin_mesma_empresa on public.logs_auditoria
for select to authenticated
using (empresa_id=public.empresa_do_usuario() and public.usuario_e_admin());

-- Sem INSERT/UPDATE/DELETE direto pelo navegador: somente funções e triggers.
drop policy if exists logs_insert_mesma_empresa on public.logs_auditoria;
drop policy if exists logs_update_admin on public.logs_auditoria;
drop policy if exists logs_delete_admin on public.logs_auditoria;

commit;
