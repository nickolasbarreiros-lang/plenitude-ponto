-- =====================================================================
-- PLENITUDE PONTO — SQL BASE CONSOLIDADO
-- Baseline de instalação limpa — RC6.1
-- Gerado em 12/08/2026
-- =====================================================================
--
-- FINALIDADE
--   Este arquivo substitui a execução manual das dezenas de migrações
--   históricas do Plenitude Ponto em UMA INSTALAÇÃO NOVA do Supabase.
--
-- IMPORTANTE
--   • Use este arquivo em PROJETOS SUPABASE NOVOS / banco vazio.
--   • NÃO execute este baseline sobre o banco de produção já existente.
--   • Para o banco atual, continue usando apenas migrações futuras.
--   • Os arquivos SQL históricos foram preservados como documentação.
--
-- FLUXO DE INSTALAÇÃO NOVA
--   1. Crie um projeto novo no Supabase.
--   2. Abra SQL Editor > New query.
--   3. Cole/executa este arquivo inteiro.
--   4. Crie o usuário administrador em Authentication > Users.
--   5. Execute o bloco PÓS-INSTALAÇÃO ao final deste arquivo,
--      substituindo o e-mail do administrador.
--
-- Este baseline preserva o estado funcional final da RC6.1, incluindo:
--   ponto, matrícula/PIN, políticas, banco de horas, ajustes, auditoria,
--   fechamento mensal, dispositivos, PIN Mestre, movimentações,
--   contingência offline, pendências, espelhos, feriados, exclusão de
--   marcações, horário oficial, desativação e banco acumulado.
-- =====================================================================



-- =====================================================================
-- SEÇÃO 01 — CORE-LOTE-1
-- Origem histórica: plenitude-ponto-lote-1.sql
-- =====================================================================

-- ============================================================
-- PLENITUDE PONTO — LOTE 1
-- Banco, autenticação, marcação segura e políticas RLS
-- Execute uma única vez no SQL Editor do Supabase.
-- ============================================================

begin;

-- 1) TIPOS
do $$
begin
  if not exists (select 1 from pg_type where typname = 'perfil_papel') then
    create type public.perfil_papel as enum ('administrador', 'funcionario');
  end if;

  if not exists (select 1 from pg_type where typname = 'tipo_marcacao') then
    create type public.tipo_marcacao as enum ('entrada', 'inicio_intervalo', 'fim_intervalo', 'saida');
  end if;

  if not exists (select 1 from pg_type where typname = 'tipo_ocorrencia') then
    create type public.tipo_ocorrencia as enum ('folga', 'ferias', 'feriado', 'atestado', 'compensacao', 'justificativa');
  end if;
end
$$;

-- 2) TABELAS PRINCIPAIS
create table if not exists public.empresas (
  id uuid primary key default gen_random_uuid(),
  razao_social text not null,
  nome_fantasia text not null,
  cnpj text,
  endereco text,
  cidade text,
  uf char(2),
  timezone text not null default 'America/Sao_Paulo',
  ativa boolean not null default true,
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now()
);

create table if not exists public.perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  empresa_id uuid references public.empresas(id) on delete set null,
  nome text,
  papel public.perfil_papel not null default 'funcionario',
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.funcionarios (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete restrict,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  nome text not null,
  cpf text,
  cargo text,
  matricula text,
  data_admissao date,
  carga_semanal_minutos integer not null default 2640
    check (carga_semanal_minutos between 0 and 10080),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (empresa_id, cpf),
  unique (empresa_id, matricula)
);

create table if not exists public.jornadas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  dia_semana smallint not null check (dia_semana between 1 and 7),
  entrada time,
  inicio_intervalo time,
  fim_intervalo time,
  saida time,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (funcionario_id, dia_semana),
  check (
    (entrada is null and inicio_intervalo is null and fim_intervalo is null and saida is null)
    or
    (
      entrada is not null
      and inicio_intervalo is not null
      and fim_intervalo is not null
      and saida is not null
      and entrada < inicio_intervalo
      and inicio_intervalo < fim_intervalo
      and fim_intervalo < saida
    )
  )
);

create table if not exists public.marcacoes (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references public.empresas(id) on delete restrict,
  funcionario_id uuid not null references public.funcionarios(id) on delete restrict,
  tipo public.tipo_marcacao not null,
  registrado_em timestamptz not null default now(),
  data_local date not null,
  origem text not null default 'web',
  observacao text,
  criado_por uuid references auth.users(id) on delete set null,
  ajustada boolean not null default false,
  registro_original_id bigint references public.marcacoes(id) on delete restrict,
  criado_em timestamptz not null default now(),
  unique (funcionario_id, data_local, tipo)
);

create table if not exists public.ocorrencias (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  tipo public.tipo_ocorrencia not null,
  data_inicio date not null,
  data_fim date not null,
  descricao text,
  aprovado boolean not null default false,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (data_fim >= data_inicio)
);

create table if not exists public.logs_auditoria (
  id bigint generated always as identity primary key,
  empresa_id uuid references public.empresas(id) on delete set null,
  usuario_id uuid references auth.users(id) on delete set null,
  tabela text not null,
  registro_id text,
  acao text not null,
  dados jsonb,
  criado_em timestamptz not null default now()
);

-- 3) ÍNDICES
create index if not exists idx_perfis_empresa on public.perfis(empresa_id);
create index if not exists idx_funcionarios_empresa on public.funcionarios(empresa_id);
create index if not exists idx_funcionarios_auth on public.funcionarios(auth_user_id);
create index if not exists idx_jornadas_funcionario on public.jornadas(funcionario_id);
create index if not exists idx_marcacoes_func_data on public.marcacoes(funcionario_id, data_local);
create index if not exists idx_marcacoes_empresa_data on public.marcacoes(empresa_id, data_local);
create index if not exists idx_ocorrencias_func_datas on public.ocorrencias(funcionario_id, data_inicio, data_fim);

-- 4) FUNÇÃO DE ATUALIZAÇÃO DE TIMESTAMP
create or replace function public.definir_atualizado_em()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.atualizada_em = now();
  return new;
end;
$$;

create or replace function public.definir_atualizado_em_generico()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

drop trigger if exists trg_empresas_atualizada_em on public.empresas;
create trigger trg_empresas_atualizada_em
before update on public.empresas
for each row execute function public.definir_atualizado_em();

drop trigger if exists trg_perfis_atualizado_em on public.perfis;
create trigger trg_perfis_atualizado_em
before update on public.perfis
for each row execute function public.definir_atualizado_em_generico();

drop trigger if exists trg_funcionarios_atualizado_em on public.funcionarios;
create trigger trg_funcionarios_atualizado_em
before update on public.funcionarios
for each row execute function public.definir_atualizado_em_generico();

drop trigger if exists trg_jornadas_atualizado_em on public.jornadas;
create trigger trg_jornadas_atualizado_em
before update on public.jornadas
for each row execute function public.definir_atualizado_em_generico();

drop trigger if exists trg_ocorrencias_atualizado_em on public.ocorrencias;
create trigger trg_ocorrencias_atualizado_em
before update on public.ocorrencias
for each row execute function public.definir_atualizado_em_generico();

-- 5) CRIA PERFIL AUTOMATICAMENTE APÓS NOVO USUÁRIO DO AUTH
create or replace function public.criar_perfil_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfis (id, nome)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'nome', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.criar_perfil_novo_usuario();

-- 6) FUNÇÕES AUXILIARES PARA RLS
create or replace function public.empresa_do_usuario()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.empresa_id
  from public.perfis p
  where p.id = auth.uid()
    and p.ativo = true
  limit 1;
$$;

create or replace function public.usuario_e_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfis p
    where p.id = auth.uid()
      and p.ativo = true
      and p.papel = 'administrador'::public.perfil_papel
  );
$$;

create or replace function public.funcionario_do_usuario()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select f.id
  from public.funcionarios f
  where f.auth_user_id = auth.uid()
    and f.ativo = true
  limit 1;
$$;

-- 7) REGISTRO DE PONTO PELO HORÁRIO DO SERVIDOR
create or replace function public.registrar_ponto()
returns public.marcacoes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_funcionario public.funcionarios;
  v_empresa public.empresas;
  v_agora timestamptz := now();
  v_data date;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_resultado public.marcacoes;
begin
  select f.*
    into v_funcionario
  from public.funcionarios f
  where f.auth_user_id = auth.uid()
    and f.ativo = true
  limit 1;

  if v_funcionario.id is null then
    raise exception 'Usuário não está vinculado a um funcionário ativo.';
  end if;

  select e.*
    into v_empresa
  from public.empresas e
  where e.id = v_funcionario.empresa_id
    and e.ativa = true;

  if v_empresa.id is null then
    raise exception 'Empresa inativa ou não encontrada.';
  end if;

  v_data := (v_agora at time zone v_empresa.timezone)::date;

  select count(*)
    into v_quantidade
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data
    and m.ajustada = false;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram registradas.';
  end if;

  insert into public.marcacoes (
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem,
    criado_por
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'web',
    auth.uid()
  )
  returning * into v_resultado;

  insert into public.logs_auditoria (
    empresa_id, usuario_id, tabela, registro_id, acao, dados
  )
  values (
    v_funcionario.empresa_id,
    auth.uid(),
    'marcacoes',
    v_resultado.id::text,
    'INSERT',
    jsonb_build_object(
      'tipo', v_resultado.tipo,
      'registrado_em', v_resultado.registrado_em,
      'origem', v_resultado.origem
    )
  );

  return v_resultado;
end;
$$;

-- 8) RLS
alter table public.empresas enable row level security;
alter table public.perfis enable row level security;
alter table public.funcionarios enable row level security;
alter table public.jornadas enable row level security;
alter table public.marcacoes enable row level security;
alter table public.ocorrencias enable row level security;
alter table public.logs_auditoria enable row level security;

-- Empresas
drop policy if exists empresas_select_mesma_empresa on public.empresas;
create policy empresas_select_mesma_empresa
on public.empresas for select
to authenticated
using (id = public.empresa_do_usuario());

drop policy if exists empresas_update_admin on public.empresas;
create policy empresas_update_admin
on public.empresas for update
to authenticated
using (id = public.empresa_do_usuario() and public.usuario_e_admin())
with check (id = public.empresa_do_usuario() and public.usuario_e_admin());

-- Perfis
drop policy if exists perfis_select_proprio_ou_admin on public.perfis;
create policy perfis_select_proprio_ou_admin
on public.perfis for select
to authenticated
using (
  id = auth.uid()
  or (
    empresa_id = public.empresa_do_usuario()
    and public.usuario_e_admin()
  )
);

drop policy if exists perfis_update_admin on public.perfis;
create policy perfis_update_admin
on public.perfis for update
to authenticated
using (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
)
with check (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

-- Funcionários
drop policy if exists funcionarios_select_proprio_ou_admin on public.funcionarios;
create policy funcionarios_select_proprio_ou_admin
on public.funcionarios for select
to authenticated
using (
  auth_user_id = auth.uid()
  or (
    empresa_id = public.empresa_do_usuario()
    and public.usuario_e_admin()
  )
);

drop policy if exists funcionarios_admin_insert on public.funcionarios;
create policy funcionarios_admin_insert
on public.funcionarios for insert
to authenticated
with check (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

drop policy if exists funcionarios_admin_update on public.funcionarios;
create policy funcionarios_admin_update
on public.funcionarios for update
to authenticated
using (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
)
with check (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

-- Jornadas
drop policy if exists jornadas_select_proprio_ou_admin on public.jornadas;
create policy jornadas_select_proprio_ou_admin
on public.jornadas for select
to authenticated
using (
  funcionario_id = public.funcionario_do_usuario()
  or (
    empresa_id = public.empresa_do_usuario()
    and public.usuario_e_admin()
  )
);

drop policy if exists jornadas_admin_insert on public.jornadas;
create policy jornadas_admin_insert
on public.jornadas for insert
to authenticated
with check (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

drop policy if exists jornadas_admin_update on public.jornadas;
create policy jornadas_admin_update
on public.jornadas for update
to authenticated
using (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
)
with check (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

-- Marcações: leitura própria ou admin. Inserção somente pela função registrar_ponto().
drop policy if exists marcacoes_select_proprio_ou_admin on public.marcacoes;
create policy marcacoes_select_proprio_ou_admin
on public.marcacoes for select
to authenticated
using (
  funcionario_id = public.funcionario_do_usuario()
  or (
    empresa_id = public.empresa_do_usuario()
    and public.usuario_e_admin()
  )
);

drop policy if exists marcacoes_admin_update on public.marcacoes;
create policy marcacoes_admin_update
on public.marcacoes for update
to authenticated
using (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
)
with check (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

-- Ocorrências
drop policy if exists ocorrencias_select_proprio_ou_admin on public.ocorrencias;
create policy ocorrencias_select_proprio_ou_admin
on public.ocorrencias for select
to authenticated
using (
  funcionario_id = public.funcionario_do_usuario()
  or (
    empresa_id = public.empresa_do_usuario()
    and public.usuario_e_admin()
  )
);

drop policy if exists ocorrencias_admin_all on public.ocorrencias;
create policy ocorrencias_admin_all
on public.ocorrencias for all
to authenticated
using (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
)
with check (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

-- Logs: somente administradores da empresa.
drop policy if exists logs_select_admin on public.logs_auditoria;
create policy logs_select_admin
on public.logs_auditoria for select
to authenticated
using (
  empresa_id = public.empresa_do_usuario()
  and public.usuario_e_admin()
);

-- 9) PRIVILÉGIOS
revoke all on public.empresas from anon;
revoke all on public.perfis from anon;
revoke all on public.funcionarios from anon;
revoke all on public.jornadas from anon;
revoke all on public.marcacoes from anon;
revoke all on public.ocorrencias from anon;
revoke all on public.logs_auditoria from anon;

grant select, update on public.empresas to authenticated;
grant select, update on public.perfis to authenticated;
grant select, insert, update on public.funcionarios to authenticated;
grant select, insert, update on public.jornadas to authenticated;
grant select, update on public.marcacoes to authenticated;
grant select, insert, update, delete on public.ocorrencias to authenticated;
grant select on public.logs_auditoria to authenticated;

grant usage, select on sequence public.marcacoes_id_seq to authenticated;
grant usage, select on sequence public.logs_auditoria_id_seq to authenticated;

grant execute on function public.registrar_ponto() to authenticated;
grant execute on function public.empresa_do_usuario() to authenticated;
grant execute on function public.usuario_e_admin() to authenticated;
grant execute on function public.funcionario_do_usuario() to authenticated;

-- 10) EMPRESA INICIAL
insert into public.empresas (
  razao_social,
  nome_fantasia,
  endereco,
  cidade,
  uf,
  timezone
)
select
  'Livraria Plenitude',
  'Presentes Plenitude e Artigos Religiosos',
  'Av. Primeira Avenida, 231, Shopping Laranjeiras',
  'Serra',
  'ES',
  'America/Sao_Paulo'
where not exists (
  select 1
  from public.empresas
  where nome_fantasia = 'Presentes Plenitude e Artigos Religiosos'
);

commit;



-- =====================================================================
-- SEÇÃO 02 — V10
-- Origem histórica: supabase-v10-registro-ponto.sql
-- =====================================================================

-- PLENITUDE PONTO V10 — registro administrativo seguro
-- Execute no SQL Editor do Supabase uma única vez.

begin;

create or replace function public.registrar_ponto_funcionario(p_funcionario_id uuid)
returns public.marcacoes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfis;
  v_funcionario public.funcionarios;
  v_empresa public.empresas;
  v_agora timestamptz := now();
  v_data date;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_resultado public.marcacoes;
begin
  select * into v_perfil from public.perfis
  where id = auth.uid() and ativo = true;

  if v_perfil.id is null or v_perfil.papel <> 'administrador'::public.perfil_papel then
    raise exception 'Apenas administradores podem registrar ponto para outro funcionário.';
  end if;

  select * into v_funcionario from public.funcionarios
  where id = p_funcionario_id
    and empresa_id = v_perfil.empresa_id
    and ativo = true;

  if v_funcionario.id is null then
    raise exception 'Funcionário ativo não encontrado nesta empresa.';
  end if;

  select * into v_empresa from public.empresas
  where id = v_funcionario.empresa_id and ativa = true;

  v_data := (v_agora at time zone v_empresa.timezone)::date;

  select count(*) into v_quantidade
  from public.marcacoes
  where funcionario_id = v_funcionario.id
    and data_local = v_data
    and ajustada = false;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram registradas.';
  end if;

  insert into public.marcacoes(
    empresa_id,funcionario_id,tipo,registrado_em,data_local,origem,criado_por
  ) values (
    v_funcionario.empresa_id,v_funcionario.id,v_tipo,v_agora,v_data,'painel_admin',auth.uid()
  ) returning * into v_resultado;

  insert into public.logs_auditoria(
    empresa_id,usuario_id,tabela,registro_id,acao,dados
  ) values (
    v_funcionario.empresa_id,auth.uid(),'marcacoes',v_resultado.id::text,'INSERT_ADMIN',
    jsonb_build_object('funcionario_id',v_funcionario.id,'tipo',v_resultado.tipo,'registrado_em',v_resultado.registrado_em)
  );

  return v_resultado;
end;
$$;

grant execute on function public.registrar_ponto_funcionario(uuid) to authenticated;

-- Habilita atualização em tempo real das marcações, sem duplicar a tabela na publicação.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'marcacoes'
  ) then
    alter publication supabase_realtime add table public.marcacoes;
  end if;
end $$;

commit;



-- =====================================================================
-- SEÇÃO 03 — V11
-- Origem histórica: supabase-v11-perfil-funcionario.sql
-- =====================================================================

-- PLENITUDE PONTO V11 — perfil visual e identificação do funcionário
-- Execute uma única vez no SQL Editor do Supabase antes de publicar a V11.

begin;

alter table public.funcionarios
  add column if not exists status text not null default 'ativo',
  add column if not exists foto_url text,
  add column if not exists codigo_qr text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'funcionarios_status_check'
  ) then
    alter table public.funcionarios
      add constraint funcionarios_status_check
      check (status in ('ativo','ferias','afastado','inativo'));
  end if;
end $$;

update public.funcionarios
set codigo_qr = 'PLENITUDE-' || upper(substr(replace(id::text,'-',''),1,12))
where codigo_qr is null;

create unique index if not exists funcionarios_codigo_qr_unique
  on public.funcionarios(codigo_qr)
  where codigo_qr is not null;

create or replace function public.definir_codigo_qr_funcionario()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.codigo_qr is null or btrim(new.codigo_qr) = '' then
    new.codigo_qr := 'PLENITUDE-' || upper(substr(replace(new.id::text,'-',''),1,12));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_funcionarios_codigo_qr on public.funcionarios;
create trigger trg_funcionarios_codigo_qr
before insert or update of codigo_qr on public.funcionarios
for each row execute function public.definir_codigo_qr_funcionario();

commit;

select id,nome,status,codigo_qr from public.funcionarios order by nome;



-- =====================================================================
-- SEÇÃO 04 — V12
-- Origem histórica: supabase-v12-storage-acesso.sql
-- =====================================================================

-- PLENITUDE PONTO V12 — Storage privado, foto e vínculo de acesso
-- Execute uma única vez no SQL Editor do Supabase.

begin;

-- Bucket privado para fotos dos funcionários.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'funcionarios',
  'funcionarios',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Remove versões anteriores das políticas, caso o script seja reexecutado.
drop policy if exists funcionarios_fotos_select on storage.objects;
drop policy if exists funcionarios_fotos_insert_admin on storage.objects;
drop policy if exists funcionarios_fotos_update_admin on storage.objects;
drop policy if exists funcionarios_fotos_delete_admin on storage.objects;

-- Usuários autenticados da empresa podem visualizar as fotos da própria empresa.
create policy funcionarios_fotos_select
on storage.objects for select
to authenticated
using (
  bucket_id = 'funcionarios'
  and (storage.foldername(name))[1] = public.empresa_do_usuario()::text
);

-- Apenas administradores podem enviar, trocar ou remover fotos.
create policy funcionarios_fotos_insert_admin
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'funcionarios'
  and public.usuario_e_admin()
  and (storage.foldername(name))[1] = public.empresa_do_usuario()::text
);

create policy funcionarios_fotos_update_admin
on storage.objects for update
to authenticated
using (
  bucket_id = 'funcionarios'
  and public.usuario_e_admin()
  and (storage.foldername(name))[1] = public.empresa_do_usuario()::text
)
with check (
  bucket_id = 'funcionarios'
  and public.usuario_e_admin()
  and (storage.foldername(name))[1] = public.empresa_do_usuario()::text
);

create policy funcionarios_fotos_delete_admin
on storage.objects for delete
to authenticated
using (
  bucket_id = 'funcionarios'
  and public.usuario_e_admin()
  and (storage.foldername(name))[1] = public.empresa_do_usuario()::text
);

-- Vincula um usuário já criado no Supabase Auth ao funcionário.
create or replace function public.vincular_funcionario_usuario(
  p_funcionario_id uuid,
  p_email text
)
returns public.funcionarios
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfis;
  v_usuario auth.users;
  v_funcionario public.funcionarios;
begin
  select * into v_perfil
  from public.perfis
  where id = auth.uid()
    and ativo = true
    and papel = 'administrador'::public.perfil_papel;

  if v_perfil.id is null then
    raise exception 'Somente administradores podem vincular contas.';
  end if;

  select * into v_funcionario
  from public.funcionarios
  where id = p_funcionario_id
    and empresa_id = v_perfil.empresa_id;

  if v_funcionario.id is null then
    raise exception 'Funcionário não encontrado nesta empresa.';
  end if;

  select * into v_usuario
  from auth.users
  where lower(email) = lower(btrim(p_email))
  limit 1;

  if v_usuario.id is null then
    raise exception 'Usuário não encontrado no Authentication. Crie-o primeiro em Authentication → Users.';
  end if;

  if exists (
    select 1 from public.funcionarios
    where auth_user_id = v_usuario.id
      and id <> p_funcionario_id
  ) then
    raise exception 'Esta conta já está vinculada a outro funcionário.';
  end if;

  update public.perfis
  set empresa_id = v_perfil.empresa_id,
      papel = 'funcionario'::public.perfil_papel,
      nome = v_funcionario.nome,
      ativo = true
  where id = v_usuario.id;

  update public.funcionarios
  set auth_user_id = v_usuario.id
  where id = p_funcionario_id
  returning * into v_funcionario;

  insert into public.logs_auditoria (
    empresa_id, usuario_id, tabela, registro_id, acao, dados
  ) values (
    v_perfil.empresa_id,
    auth.uid(),
    'funcionarios',
    v_funcionario.id::text,
    'VINCULAR_USUARIO',
    jsonb_build_object('auth_user_id', v_usuario.id, 'email', v_usuario.email)
  );

  return v_funcionario;
end;
$$;

grant execute on function public.vincular_funcionario_usuario(uuid,text) to authenticated;

commit;

select id, name, public, file_size_limit
from storage.buckets
where id = 'funcionarios';



-- =====================================================================
-- SEÇÃO 05 — V15
-- Origem histórica: supabase-v15-matricula-pin.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 06 — CORRECAO-LOGIN-MATRICULA
-- Origem histórica: supabase-correcao-login-matricula-pin.sql
-- =====================================================================

begin;

-- Corrige o login do funcionário para:
-- 1) aceitar matrícula com ou sem zeros à esquerda (001 = 0001);
-- 2) validar PIN usando apenas algarismos;
-- 3) acessar corretamente as funções do pgcrypto no schema extensions.
create or replace function public.login_funcionario_pin(p_matricula text,p_pin text)
returns table(
  token text,
  funcionario_id uuid,
  nome text,
  cargo text,
  matricula text,
  foto_url text,
  exigir_troca_pin boolean,
  expira_em timestamptz
)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  f public.funcionarios%rowtype;
  v_token text;
  v_now timestamptz:=clock_timestamp();
  v_matricula_normalizada text;
begin
  if coalesce(p_pin,'') !~ '^[0-9]{4}$' then
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  -- Remove espaços e zeros à esquerda. Mantém "0" quando a matrícula for só zeros.
  v_matricula_normalizada := coalesce(nullif(ltrim(btrim(coalesce(p_matricula,'')),'0'),''),'0');

  select fun.*
    into f
    from public.funcionarios fun
   where fun.ativo=true
     and coalesce(nullif(ltrim(btrim(fun.matricula),'0'),''),'0')=v_matricula_normalizada
   order by fun.criado_em asc nulls last
   limit 1;

  if f.id is null or f.pin_hash is null then
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  if not f.acesso_ponto_ativo then
    raise exception 'Acesso ao ponto bloqueado. Procure o administrador.';
  end if;

  if f.bloqueado_ate is not null and f.bloqueado_ate>v_now then
    raise exception 'Acesso temporariamente bloqueado. Tente novamente mais tarde.';
  end if;

  if extensions.crypt(p_pin,f.pin_hash)<>f.pin_hash then
    update public.funcionarios fun
       set tentativas_pin=coalesce(fun.tentativas_pin,0)+1,
           bloqueado_ate=case
             when coalesce(fun.tentativas_pin,0)+1>=5 then v_now+interval '15 minutes'
             else null
           end
     where fun.id=f.id;
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  update public.funcionarios fun
     set tentativas_pin=0,
         bloqueado_ate=null,
         ultimo_acesso_em=v_now
   where fun.id=f.id;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');

  insert into public.sessoes_funcionario(funcionario_id,token_hash,expira_em)
  values(
    f.id,
    encode(extensions.digest(v_token,'sha256'),'hex'),
    v_now+interval '12 hours'
  );

  return query
  select v_token,f.id,f.nome,f.cargo,f.matricula,f.foto_url,
         f.exigir_troca_pin,v_now+interval '12 hours';
end $$;

revoke all on function public.login_funcionario_pin(text,text) from public,anon,authenticated;
-- A função direta permanece bloqueada para o navegador.
-- login_funcionario_pin_dispositivo() continua chamando-a internamente como SECURITY DEFINER.

commit;



-- =====================================================================
-- SEÇÃO 07 — CORRECAO-LOGIN-STATUS
-- Origem histórica: supabase-correcao-status-ambiguo-login-funcionario.sql
-- =====================================================================

begin;

-- Correção: elimina referências ambíguas a colunas como "status" no fluxo
-- de login do funcionário. Todas as colunas passam a usar alias explícito.

create or replace function public.login_funcionario_pin(
  p_matricula text,
  p_pin text
)
returns table(
  token text,
  funcionario_id uuid,
  nome text,
  cargo text,
  matricula text,
  foto_url text,
  exigir_troca_pin boolean,
  expira_em timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_token text;
  v_agora timestamptz := clock_timestamp();
  v_matricula text;
begin
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  v_matricula :=
    coalesce(nullif(ltrim(btrim(coalesce(p_matricula, '')), '0'), ''), '0');

  select f.*
    into v_funcionario
    from public.funcionarios as f
   where f.ativo = true
     and coalesce(nullif(ltrim(btrim(f.matricula), '0'), ''), '0') = v_matricula
   order by f.criado_em asc nulls last
   limit 1;

  if v_funcionario.id is null or v_funcionario.pin_hash is null then
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  if not coalesce(v_funcionario.acesso_ponto_ativo, false) then
    raise exception 'Acesso ao ponto bloqueado. Procure o administrador.';
  end if;

  if v_funcionario.bloqueado_ate is not null
     and v_funcionario.bloqueado_ate > v_agora then
    raise exception 'Acesso temporariamente bloqueado. Tente novamente mais tarde.';
  end if;

  if extensions.crypt(p_pin, v_funcionario.pin_hash) <> v_funcionario.pin_hash then
    update public.funcionarios as f
       set tentativas_pin = coalesce(f.tentativas_pin, 0) + 1,
           bloqueado_ate = case
             when coalesce(f.tentativas_pin, 0) + 1 >= 5
               then v_agora + interval '15 minutes'
             else null
           end
     where f.id = v_funcionario.id;

    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  update public.funcionarios as f
     set tentativas_pin = 0,
         bloqueado_ate = null,
         ultimo_acesso_em = v_agora
   where f.id = v_funcionario.id;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.sessoes_funcionario(
    funcionario_id,
    token_hash,
    expira_em
  )
  values (
    v_funcionario.id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    v_agora + interval '12 hours'
  );

  return query
  select
    v_token,
    v_funcionario.id,
    v_funcionario.nome,
    v_funcionario.cargo,
    v_funcionario.matricula,
    v_funcionario.foto_url,
    v_funcionario.exigir_troca_pin,
    v_agora + interval '12 hours';
end;
$$;

create or replace function public.login_funcionario_pin_dispositivo(
  p_matricula text,
  p_pin text,
  p_dispositivo_token text,
  p_user_agent text default null
)
returns table(
  token text,
  funcionario_id uuid,
  nome text,
  cargo text,
  matricula text,
  foto_url text,
  exigir_troca_pin boolean,
  expira_em timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_login record;
begin
  select d.*
    into v_dispositivo
    from public.dispositivos_ponto as d
   where d.token_hash =
         encode(extensions.digest(coalesce(p_dispositivo_token, ''), 'sha256'), 'hex')
     and d.ativo = true
   limit 1;

  if v_dispositivo.id is null then
    raise exception 'Este computador não está autorizado para registrar ponto.';
  end if;

  select l.*
    into v_login
    from public.login_funcionario_pin(p_matricula, p_pin) as l;

  if v_login.funcionario_id is null then
    raise exception 'Não foi possível iniciar a sessão.';
  end if;

  if not exists (
    select 1
      from public.funcionarios as f
     where f.id = v_login.funcionario_id
       and f.empresa_id = v_dispositivo.empresa_id
  ) then
    perform public.encerrar_sessao_funcionario(v_login.token);
    raise exception 'Este dispositivo não pertence à empresa do funcionário.';
  end if;

  update public.dispositivos_ponto as d
     set ultimo_uso_em = clock_timestamp()
   where d.id = v_dispositivo.id;

  return query
  select
    v_login.token::text,
    v_login.funcionario_id::uuid,
    v_login.nome::text,
    v_login.cargo::text,
    v_login.matricula::text,
    v_login.foto_url::text,
    v_login.exigir_troca_pin::boolean,
    v_login.expira_em::timestamptz;
end;
$$;

-- O navegador acessa apenas a versão que valida o computador.
revoke all on function public.login_funcionario_pin(text,text)
from public, anon, authenticated;

revoke all on function public.login_funcionario_pin_dispositivo(text,text,text,text)
from public;

grant execute on function public.login_funcionario_pin_dispositivo(text,text,text,text)
to anon, authenticated;

commit;



-- =====================================================================
-- SEÇÃO 08 — V17
-- Origem histórica: supabase-v17-banco-horas.sql
-- =====================================================================

-- PLENITUDE PONTO V17 — BANCO DE HORAS AUTOMÁTICO
-- Execute integralmente no SQL Editor do Supabase.

create or replace function public._calcular_banco_horas_json(
  p_funcionario_id uuid,
  p_inicio date,
  p_fim date
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_dias jsonb := '[]'::jsonb;
  v_resumo jsonb;
  v_dia record;
  v_previsto integer;
  v_trabalhado integer;
  v_saldo integer;
  v_count integer;
  v_tipos public.tipo_marcacao[];
  v_horarios timestamptz[];
  v_ocorrencia text;
  v_status text;
  v_total_previsto integer := 0;
  v_total_trabalhado integer := 0;
  v_total_saldo integer := 0;
  v_total_positivo integer := 0;
  v_total_negativo integer := 0;
  v_dias_trabalhados integer := 0;
  v_faltas integer := 0;
  v_pendencias integer := 0;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Período inválido.';
  end if;

  if p_fim - p_inicio > 370 then
    raise exception 'O período máximo permitido é de 370 dias.';
  end if;

  select * into v_funcionario
  from public.funcionarios
  where id = p_funcionario_id;

  if v_funcionario.id is null then
    raise exception 'Funcionário não encontrado.';
  end if;

  for v_dia in
    select gs::date as data
    from generate_series(p_inicio::timestamp, p_fim::timestamp, interval '1 day') gs
    order by gs
  loop
    select
      case
        when j.id is null or j.ativo is false or j.entrada is null then 0
        else round(extract(epoch from (
          (j.inicio_intervalo - j.entrada) +
          (j.saida - j.fim_intervalo)
        )) / 60)::integer
      end
    into v_previsto
    from (select 1) x
    left join public.jornadas j
      on j.funcionario_id = p_funcionario_id
     and j.dia_semana = extract(isodow from v_dia.data)::smallint
    limit 1;

    select o.tipo::text
    into v_ocorrencia
    from public.ocorrencias o
    where o.funcionario_id = p_funcionario_id
      and o.aprovado = true
      and v_dia.data between o.data_inicio and o.data_fim
    order by o.criado_em desc
    limit 1;

    if v_ocorrencia in ('folga','ferias','feriado','atestado') then
      v_previsto := 0;
    end if;

    select
      count(*)::integer,
      array_agg(m.tipo order by m.registrado_em),
      array_agg(m.registrado_em order by m.registrado_em)
    into v_count, v_tipos, v_horarios
    from public.marcacoes m
    where m.funcionario_id = p_funcionario_id
      and m.data_local = v_dia.data;

    v_trabalhado := 0;
    v_saldo := null;

    if v_count >= 2 then
      v_trabalhado := v_trabalhado + greatest(0, round(extract(epoch from (v_horarios[2] - v_horarios[1])) / 60)::integer);
    end if;
    if v_count >= 4 then
      v_trabalhado := v_trabalhado + greatest(0, round(extract(epoch from (v_horarios[4] - v_horarios[3])) / 60)::integer);
    end if;

    if v_ocorrencia in ('folga','ferias','feriado','atestado') then
      v_status := v_ocorrencia;
      v_saldo := case when v_count = 4 then v_trabalhado else 0 end;
    elsif v_previsto = 0 then
      v_status := case when v_count > 0 then 'extra' else 'sem_jornada' end;
      v_saldo := case when v_count = 4 then v_trabalhado else 0 end;
    elsif v_count = 4 then
      v_status := 'completo';
      v_saldo := v_trabalhado - v_previsto;
      v_dias_trabalhados := v_dias_trabalhados + 1;
    elsif v_dia.data < (clock_timestamp() at time zone 'America/Sao_Paulo')::date and v_count = 0 then
      v_status := 'falta';
      v_saldo := -v_previsto;
      v_faltas := v_faltas + 1;
    elsif v_dia.data <= (clock_timestamp() at time zone 'America/Sao_Paulo')::date and v_count between 1 and 3 then
      v_status := 'pendente';
      v_pendencias := v_pendencias + 1;
    elsif v_dia.data = (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      v_status := 'aguardando';
    else
      v_status := 'futuro';
    end if;

    if v_dia.data <= (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      v_total_previsto := v_total_previsto + v_previsto;
      v_total_trabalhado := v_total_trabalhado + v_trabalhado;
      if v_saldo is not null then
        v_total_saldo := v_total_saldo + v_saldo;
        if v_saldo > 0 then
          v_total_positivo := v_total_positivo + v_saldo;
        elsif v_saldo < 0 then
          v_total_negativo := v_total_negativo + abs(v_saldo);
        end if;
      end if;
    end if;

    v_dias := v_dias || jsonb_build_array(jsonb_build_object(
      'data', v_dia.data,
      'dia_semana', extract(isodow from v_dia.data)::integer,
      'previsto_minutos', v_previsto,
      'trabalhado_minutos', v_trabalhado,
      'saldo_minutos', v_saldo,
      'quantidade_marcacoes', v_count,
      'status', v_status,
      'ocorrencia', v_ocorrencia,
      'marcacoes', coalesce(to_jsonb(v_horarios), '[]'::jsonb),
      'tipos', coalesce(to_jsonb(v_tipos), '[]'::jsonb)
    ));
  end loop;

  v_resumo := jsonb_build_object(
    'funcionario_id', v_funcionario.id,
    'funcionario_nome', v_funcionario.nome,
    'matricula', v_funcionario.matricula,
    'inicio', p_inicio,
    'fim', p_fim,
    'previsto_minutos', v_total_previsto,
    'trabalhado_minutos', v_total_trabalhado,
    'saldo_minutos', v_total_saldo,
    'credito_minutos', v_total_positivo,
    'debito_minutos', v_total_negativo,
    'dias_trabalhados', v_dias_trabalhados,
    'faltas', v_faltas,
    'pendencias', v_pendencias
  );

  return jsonb_build_object('resumo', v_resumo, 'dias', v_dias);
end;
$$;

create or replace function public.banco_horas_admin(
  p_funcionario_id uuid,
  p_inicio date,
  p_fim date
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_empresa_funcionario uuid;
begin
  select empresa_id into v_empresa
  from public.perfis
  where id = auth.uid()
    and papel = 'administrador'
    and ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  select empresa_id into v_empresa_funcionario
  from public.funcionarios
  where id = p_funcionario_id;

  if v_empresa_funcionario is distinct from v_empresa then
    raise exception 'Funcionário não pertence à sua empresa.';
  end if;

  return public._calcular_banco_horas_json(p_funcionario_id, p_inicio, p_fim);
end;
$$;

create or replace function public.banco_horas_funcionario_token(
  p_token text,
  p_inicio date,
  p_fim date
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
begin
  select * into v_funcionario
  from public.funcionario_por_token(p_token);

  return public._calcular_banco_horas_json(v_funcionario.id, p_inicio, p_fim);
end;
$$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date) from public, anon, authenticated;
revoke all on function public.banco_horas_admin(uuid,date,date) from public, anon;
revoke all on function public.banco_horas_funcionario_token(text,date,date) from public;

grant execute on function public.banco_horas_admin(uuid,date,date) to authenticated;
grant execute on function public.banco_horas_funcionario_token(text,date,date) to anon, authenticated;



-- =====================================================================
-- SEÇÃO 09 — V18
-- Origem histórica: supabase-v18-ajustes-ponto.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 10 — V19
-- Origem histórica: supabase-v19-politicas-ponto.sql
-- =====================================================================

-- PLENITUDE PONTO V19 — POLÍTICAS DE PONTO E TOLERÂNCIAS
-- Execute integralmente no SQL Editor do Supabase.

alter table public.empresas
  add column if not exists tolerancia_entrada_minutos integer not null default 15,
  add column if not exists tolerancia_saida_minutos integer not null default 10,
  add column if not exists intervalo_minimo_minutos integer not null default 60,
  add column if not exists intervalo_maximo_minutos integer not null default 120,
  add column if not exists horas_extras_automaticas boolean not null default true,
  add column if not exists limite_banco_horas_minutos integer not null default 2400;

alter table public.empresas drop constraint if exists empresas_tolerancia_entrada_check;
alter table public.empresas add constraint empresas_tolerancia_entrada_check check (tolerancia_entrada_minutos between 0 and 120);
alter table public.empresas drop constraint if exists empresas_tolerancia_saida_check;
alter table public.empresas add constraint empresas_tolerancia_saida_check check (tolerancia_saida_minutos between 0 and 120);
alter table public.empresas drop constraint if exists empresas_intervalo_check;
alter table public.empresas add constraint empresas_intervalo_check check (intervalo_minimo_minutos between 0 and intervalo_maximo_minutos and intervalo_maximo_minutos <= 360);
alter table public.empresas drop constraint if exists empresas_limite_banco_check;
alter table public.empresas add constraint empresas_limite_banco_check check (limite_banco_horas_minutos between 0 and 60000);

create or replace function public.salvar_politicas_ponto(
  p_tolerancia_entrada integer,
  p_tolerancia_saida integer,
  p_intervalo_minimo integer,
  p_intervalo_maximo integer,
  p_horas_extras_automaticas boolean,
  p_limite_banco_horas integer
)
returns public.empresas
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_result public.empresas%rowtype;
begin
  select empresa_id into v_empresa from public.perfis
  where id=auth.uid() and papel='administrador' and ativo=true;
  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  if p_tolerancia_entrada not between 0 and 120 or p_tolerancia_saida not between 0 and 120 then
    raise exception 'As tolerâncias devem ficar entre 0 e 120 minutos.';
  end if;
  if p_intervalo_minimo < 0 or p_intervalo_maximo < p_intervalo_minimo or p_intervalo_maximo > 360 then
    raise exception 'Configuração de intervalo inválida.';
  end if;
  update public.empresas set
    tolerancia_entrada_minutos=p_tolerancia_entrada,
    tolerancia_saida_minutos=p_tolerancia_saida,
    intervalo_minimo_minutos=p_intervalo_minimo,
    intervalo_maximo_minutos=p_intervalo_maximo,
    horas_extras_automaticas=p_horas_extras_automaticas,
    limite_banco_horas_minutos=p_limite_banco_horas,
    atualizada_em=clock_timestamp()
  where id=v_empresa returning * into v_result;
  insert into public.logs_auditoria(empresa_id,usuario_id,acao,tabela,registro_id,dados_novos)
  values(v_empresa,auth.uid(),'POLITICAS_PONTO_ATUALIZADAS','empresas',v_empresa,
    jsonb_build_object('tolerancia_entrada',p_tolerancia_entrada,'tolerancia_saida',p_tolerancia_saida,
    'intervalo_minimo',p_intervalo_minimo,'intervalo_maximo',p_intervalo_maximo,
    'horas_extras_automaticas',p_horas_extras_automaticas,'limite_banco_horas',p_limite_banco_horas));
  return v_result;
end; $$;

grant execute on function public.salvar_politicas_ponto(integer,integer,integer,integer,boolean,integer) to authenticated;

-- Substitui o cálculo da V17, preservando o horário real e usando a tolerância somente no cálculo.
create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    if qtd>=1 then entrada_real:=horarios[1]; entrada_calc:=entrada_real; else entrada_real:=null; entrada_calc:=null; end if;
    if qtd>=2 then inicio_int:=horarios[2]; else inicio_int:=null; end if;
    if qtd>=3 then fim_int:=horarios[3]; else fim_int:=null; end if;
    if qtd>=4 then saida_real:=horarios[4]; saida_calc:=saida_real; else saida_real:=null; saida_calc:=null; end if;
    if j.id is not null and entrada_real is not null then
      if entrada_real > (d.data+j.entrada) at time zone e.timezone and entrada_real <= ((d.data+j.entrada) at time zone e.timezone)+make_interval(mins=>e.tolerancia_entrada_minutos) then
        entrada_calc:=(d.data+j.entrada) at time zone e.timezone; tolerancia_aplicada:=true;
      end if;
    end if;
    if j.id is not null and saida_real is not null then
      if saida_real < (d.data+j.saida) at time zone e.timezone and saida_real >= ((d.data+j.saida) at time zone e.timezone)-make_interval(mins=>e.tolerancia_saida_minutos) then
        saida_calc:=(d.data+j.saida) at time zone e.timezone; tolerancia_aplicada:=true;
      end if;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then
      int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;
    if ocorr in ('folga','ferias','feriado','atestado') then status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then status:='falta'; saldo:=-previsto; faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then status:='aguardando'; else status:='futuro'; end if;
    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0 and not e.horas_extras_automaticas then saldo:=0; end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end; $$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date) from public,anon,authenticated;



-- =====================================================================
-- SEÇÃO 11 — V22
-- Origem histórica: supabase-v22-auditoria-seguranca.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 12 — V24
-- Origem histórica: supabase-v24-fechamento-mensal.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 13 — V26
-- Origem histórica: supabase-v26-dispositivo-autorizado.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 14 — V26-V27-CORRECAO-ATIVO
-- Origem histórica: supabase-v26-v27-correcao-ativo-ambiguo.sql
-- =====================================================================

-- Correção V26/V27 — referência ambígua à coluna "ativo"
-- Execute após as versões V26 e V27.

begin;

create or replace function public.autorizar_dispositivo_ponto_admin(
  p_token text,
  p_nome text,
  p_user_agent text default null
)
returns table(id uuid,nome text,ativo boolean,autorizado_em timestamptz)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa uuid;
  v_id uuid;
begin
  if not public.usuario_e_admin() then
    raise exception 'Apenas administradores podem autorizar dispositivos.';
  end if;

  if length(coalesce(p_token,'')) < 32 then
    raise exception 'Token de dispositivo inválido.';
  end if;

  v_empresa := public.empresa_do_usuario();
  if v_empresa is null then
    raise exception 'Empresa não identificada.';
  end if;

  -- Somente uma máquina ativa por empresa.
  update public.dispositivos_ponto as dp
     set ativo = false,
         revogado_em = clock_timestamp()
   where dp.empresa_id = v_empresa
     and dp.ativo = true;

  insert into public.dispositivos_ponto as dp (
    empresa_id,
    nome,
    token_hash,
    ativo,
    autorizado_por,
    user_agent_autorizacao
  ) values (
    v_empresa,
    coalesce(nullif(trim(p_nome),''),'Computador da loja'),
    encode(digest(p_token,'sha256'),'hex'),
    true,
    auth.uid(),
    left(p_user_agent,1000)
  )
  returning dp.id into v_id;

  perform public.registrar_evento_auditoria(
    'AUTORIZAR',
    'dispositivos_ponto',
    v_id::text,
    'Computador autorizado para registrar ponto',
    jsonb_build_object(
      'nome',coalesce(nullif(trim(p_nome),''),'Computador da loja')
    ),
    'web'
  );

  return query
  select dp.id, dp.nome, dp.ativo, dp.autorizado_em
    from public.dispositivos_ponto as dp
   where dp.id = v_id;
end;
$$;

-- Mantém a proteção da V27: a função-base não pode ser chamada diretamente.
revoke execute on function public.autorizar_dispositivo_ponto_admin(text,text,text)
  from authenticated, anon, public;

-- O wrapper com PIN Mestre continua sendo o ponto de entrada autorizado.
grant execute on function public.autorizar_dispositivo_ponto_master_admin(text,text,text,text)
  to authenticated;

commit;



-- =====================================================================
-- SEÇÃO 15 — V27
-- Origem histórica: supabase-v27-pin-mestre.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 16 — V28
-- Origem histórica: supabase-v28-movimentacoes-jornada.sql
-- =====================================================================

-- PLENITUDE PONTO V28 — MOVIMENTAÇÕES E JUSTIFICATIVAS DE JORNADA
-- Execute integralmente no SQL Editor do Supabase após a V27.

begin;

create table if not exists public.movimentacoes_jornada (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  data_local date not null,
  inicio_em timestamptz not null,
  fim_em timestamptz,
  origem text not null default 'funcionario',
  motivo_informado text,
  classificacao text,
  efeito_calculo text not null default 'pendente',
  status text not null default 'aberta',
  aprovado boolean not null default false,
  observacao_admin text,
  criado_por uuid,
  analisado_por uuid,
  analisado_em timestamptz,
  criado_em timestamptz not null default clock_timestamp(),
  atualizado_em timestamptz not null default clock_timestamp(),
  constraint movimentacoes_status_check check (status in ('aberta','encerrada','cancelada')),
  constraint movimentacoes_efeito_check check (efeito_calculo in ('pendente','descontar','abonar','trabalhado','credito')),
  constraint movimentacoes_classificacao_check check (classificacao is null or classificacao in (
    'consulta_medica','atestado','servico_externo','curso','banco','particular','saida_autorizada',
    'compensacao','hora_extra_autorizada','home_office','outro'
  )),
  constraint movimentacoes_periodo_check check (fim_em is null or fim_em >= inicio_em)
);

create index if not exists movimentacoes_func_data_idx on public.movimentacoes_jornada(funcionario_id,data_local,inicio_em);
create index if not exists movimentacoes_empresa_status_idx on public.movimentacoes_jornada(empresa_id,status,aprovado);

alter table public.movimentacoes_jornada enable row level security;
drop policy if exists movimentacoes_admin_select on public.movimentacoes_jornada;
create policy movimentacoes_admin_select on public.movimentacoes_jornada for select to authenticated
using (empresa_id=public.empresa_do_usuario() and public.usuario_e_admin());

create or replace function public.registrar_movimentacao_dispositivo(
  p_token text,p_dispositivo_token text,p_acao text,p_motivo text default null,p_user_agent text default null
)
returns public.movimentacoes_jornada
language plpgsql security definer set search_path=public,extensions as $$
declare d public.dispositivos_ponto%rowtype; f public.funcionarios%rowtype; v public.movimentacoes_jornada%rowtype;
  agora timestamptz:=clock_timestamp(); hoje date;
begin
  select * into d from public.dispositivos_ponto
  where token_hash=encode(digest(coalesce(p_dispositivo_token,''),'sha256'),'hex') and ativo=true;
  if d.id is null then raise exception 'Registro bloqueado: computador não autorizado.'; end if;
  f:=public.funcionario_por_token(p_token);
  if f.empresa_id<>d.empresa_id then raise exception 'Dispositivo não autorizado para esta empresa.'; end if;
  hoje:=(agora at time zone 'America/Sao_Paulo')::date;

  if p_acao='saida' then
    if exists(select 1 from public.movimentacoes_jornada where funcionario_id=f.id and status='aberta') then
      raise exception 'Já existe uma saída temporária aguardando retorno.';
    end if;
    insert into public.movimentacoes_jornada(empresa_id,funcionario_id,data_local,inicio_em,origem,motivo_informado,status)
    values(f.empresa_id,f.id,hoje,agora,'funcionario',nullif(trim(p_motivo),''),'aberta') returning * into v;
  elsif p_acao='retorno' then
    select * into v from public.movimentacoes_jornada
    where funcionario_id=f.id and status='aberta' order by inicio_em desc limit 1 for update;
    if v.id is null then raise exception 'Não existe saída temporária aberta.'; end if;
    update public.movimentacoes_jornada set fim_em=agora,status='encerrada',atualizado_em=agora where id=v.id returning * into v;
  else
    raise exception 'Ação inválida.';
  end if;

  update public.dispositivos_ponto set ultimo_uso_em=agora where id=d.id;
  insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados_novos,origem,descricao)
  values(f.empresa_id,null,'movimentacoes_jornada',v.id::text,upper('MOVIMENTACAO_'||p_acao),
    jsonb_build_object('funcionario_id',f.id,'inicio_em',v.inicio_em,'fim_em',v.fim_em,'motivo',v.motivo_informado,'user_agent',left(p_user_agent,500)),
    'web','Movimentação de jornada registrada pelo funcionário');
  return v;
end $$;

create or replace function public.listar_minhas_movimentacoes(p_token text,p_inicio date,p_fim date)
returns setof public.movimentacoes_jornada
language plpgsql security definer set search_path=public as $$
declare f public.funcionarios%rowtype;
begin
  f:=public.funcionario_por_token(p_token);
  return query select m.* from public.movimentacoes_jornada m
  where m.funcionario_id=f.id and m.data_local between p_inicio and p_fim order by m.inicio_em desc;
end $$;

create or replace function public.listar_movimentacoes_admin(p_inicio date,p_fim date,p_funcionario_id uuid default null,p_pendentes boolean default false)
returns table(
  id uuid,funcionario_id uuid,funcionario_nome text,matricula text,data_local date,inicio_em timestamptz,fim_em timestamptz,
  origem text,motivo_informado text,classificacao text,efeito_calculo text,status text,aprovado boolean,observacao_admin text
)
language plpgsql security definer set search_path=public as $$
declare emp uuid;
begin
  select empresa_id into emp from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
  if emp is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  return query select m.id,m.funcionario_id,f.nome,f.matricula,m.data_local,m.inicio_em,m.fim_em,m.origem,m.motivo_informado,
    m.classificacao,m.efeito_calculo,m.status,m.aprovado,m.observacao_admin
  from public.movimentacoes_jornada m join public.funcionarios f on f.id=m.funcionario_id
  where m.empresa_id=emp and m.data_local between p_inicio and p_fim
    and (p_funcionario_id is null or m.funcionario_id=p_funcionario_id)
    and (not p_pendentes or m.efeito_calculo='pendente' or m.status='aberta')
  order by m.inicio_em desc;
end $$;

create or replace function public.criar_movimentacao_admin(
  p_funcionario_id uuid,p_inicio timestamptz,p_fim timestamptz,p_classificacao text,p_efeito text,p_observacao text default null
)
returns public.movimentacoes_jornada
language plpgsql security definer set search_path=public as $$
declare emp uuid; v public.movimentacoes_jornada%rowtype;
begin
  select empresa_id into emp from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
  if emp is null or not exists(select 1 from public.funcionarios where id=p_funcionario_id and empresa_id=emp) then raise exception 'Funcionário inválido.'; end if;
  if p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  insert into public.movimentacoes_jornada(empresa_id,funcionario_id,data_local,inicio_em,fim_em,origem,classificacao,efeito_calculo,status,aprovado,observacao_admin,criado_por,analisado_por,analisado_em)
  values(emp,p_funcionario_id,(p_inicio at time zone 'America/Sao_Paulo')::date,p_inicio,p_fim,'administrador',p_classificacao,p_efeito,'encerrada',true,p_observacao,auth.uid(),auth.uid(),clock_timestamp()) returning * into v;
  insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados_novos,origem,descricao)
  values(emp,auth.uid(),'movimentacoes_jornada',v.id::text,'MOVIMENTACAO_CRIADA_ADMIN',to_jsonb(v),'web','Justificativa ou movimentação criada pelo administrador');
  return v;
end $$;

create or replace function public.analisar_movimentacao_admin(
  p_id uuid,p_classificacao text,p_efeito text,p_observacao text default null
)
returns public.movimentacoes_jornada
language plpgsql security definer set search_path=public as $$
declare emp uuid; v public.movimentacoes_jornada%rowtype;
begin
  select empresa_id into emp from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
  if emp is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  update public.movimentacoes_jornada set classificacao=p_classificacao,efeito_calculo=p_efeito,aprovado=true,
    observacao_admin=p_observacao,analisado_por=auth.uid(),analisado_em=clock_timestamp(),atualizado_em=clock_timestamp()
  where id=p_id and empresa_id=emp and status='encerrada' returning * into v;
  if v.id is null then raise exception 'Movimentação não encontrada ou ainda sem retorno.'; end if;
  insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados_novos,origem,descricao)
  values(emp,auth.uid(),'movimentacoes_jornada',v.id::text,'MOVIMENTACAO_ANALISADA',to_jsonb(v),'web','Movimentação classificada pelo administrador');
  return v;
end $$;

-- Atualiza o cálculo: saídas particulares descontam; períodos abonados recompõem a jornada;
-- serviço externo/home office contam como trabalho; hora extra autorizada libera saldo positivo.
create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    if j.id is not null and entrada_real is not null and entrada_real > (d.data+j.entrada) at time zone e.timezone
       and entrada_real <= ((d.data+j.entrada) at time zone e.timezone)+make_interval(mins=>e.tolerancia_entrada_minutos) then
      entrada_calc:=(d.data+j.entrada) at time zone e.timezone; tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null and saida_real < (d.data+j.saida) at time zone e.timezone
       and saida_real >= ((d.data+j.saida) at time zone e.timezone)-make_interval(mins=>e.tolerancia_saida_minutos) then
      saida_calc:=(d.data+j.saida) at time zone e.timezone; tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    select coalesce(sum(case when aprovado and efeito_calculo='descontar' and fim_em is not null then round(extract(epoch from (fim_em-inicio_em))/60)::int else 0 end),0),
           coalesce(sum(case when aprovado and efeito_calculo='abonar' and fim_em is not null then round(extract(epoch from (fim_em-inicio_em))/60)::int else 0 end),0),
           coalesce(bool_or(aprovado and efeito_calculo='credito'),false),
           coalesce(jsonb_agg(jsonb_build_object('id',id,'inicio_em',inicio_em,'fim_em',fim_em,'classificacao',classificacao,'efeito',efeito_calculo,'status',status,'aprovado',aprovado) order by inicio_em),'[]'::jsonb)
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada where funcionario_id=f.id and data_local=d.data and status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then status:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then status:='aguardando'; else status:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0 and not e.horas_extras_automaticas and not extra_autorizada then saldo:=0; end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;

revoke all on table public.movimentacoes_jornada from anon,authenticated;
revoke all on function public.registrar_movimentacao_dispositivo(text,text,text,text,text) from public;
revoke all on function public.listar_minhas_movimentacoes(text,date,date) from public;
revoke all on function public.listar_movimentacoes_admin(date,date,uuid,boolean) from public,anon;
revoke all on function public.criar_movimentacao_admin(uuid,timestamptz,timestamptz,text,text,text) from public,anon;
revoke all on function public.analisar_movimentacao_admin(uuid,text,text,text) from public,anon;
grant execute on function public.registrar_movimentacao_dispositivo(text,text,text,text,text) to anon,authenticated;
grant execute on function public.listar_minhas_movimentacoes(text,date,date) to anon,authenticated;
grant execute on function public.listar_movimentacoes_admin(date,date,uuid,boolean) to authenticated;
grant execute on function public.criar_movimentacao_admin(uuid,timestamptz,timestamptz,text,text,text) to authenticated;
grant execute on function public.analisar_movimentacao_admin(uuid,text,text,text) to authenticated;

commit;



-- =====================================================================
-- SEÇÃO 17 — V29
-- Origem histórica: supabase-v29-correcao-pin-funcionario.sql
-- =====================================================================

begin;

-- V29 — consolidação do PIN de funcionário.
-- Corrige a gravação do hash, mantém a validação pela sessão administrativa
-- e devolve o estado real salvo para o frontend confirmar a operação.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.admin_definir_pin(
  p_funcionario_id uuid,
  p_pin text,
  p_exigir_troca boolean default false,
  p_acesso_ativo boolean default true
)
returns table(
  id uuid,
  matricula text,
  acesso_ponto_ativo boolean,
  exigir_troca_pin boolean,
  pin_configurado boolean
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Sessão administrativa obrigatória.';
  end if;

  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if coalesce(p_pin, '') !~ '^\d{4}$' then
    raise exception 'O PIN deve conter exatamente 4 números.';
  end if;

  update public.funcionarios f
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
         acesso_ponto_ativo = coalesce(p_acesso_ativo, true),
         exigir_troca_pin = coalesce(p_exigir_troca, false),
         tentativas_pin = 0,
         bloqueado_ate = null
   where f.id = p_funcionario_id
     and f.empresa_id = v_empresa;

  if not found then
    raise exception 'Funcionário não encontrado ou não pertence à sua empresa.';
  end if;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, acao, tabela, registro_id, dados_novos
  ) values (
    v_empresa,
    auth.uid(),
    'PIN_REDEFINIDO',
    'funcionarios',
    p_funcionario_id,
    jsonb_build_object(
      'exigir_troca', coalesce(p_exigir_troca, false),
      'acesso_ativo', coalesce(p_acesso_ativo, true),
      'pin_configurado', true
    )
  );

  return query
  select f.id,
         f.matricula,
         f.acesso_ponto_ativo,
         f.exigir_troca_pin,
         (f.pin_hash is not null)
  from public.funcionarios f
  where f.id = p_funcionario_id
    and f.empresa_id = v_empresa;
end;
$$;

create or replace function public.admin_alterar_acesso_pin(
  p_funcionario_id uuid,
  p_ativo boolean
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Sessão administrativa obrigatória.';
  end if;

  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  update public.funcionarios f
     set acesso_ponto_ativo = coalesce(p_ativo, false),
         tentativas_pin = 0,
         bloqueado_ate = null
   where f.id = p_funcionario_id
     and f.empresa_id = v_empresa;

  if not found then
    raise exception 'Funcionário não encontrado ou não pertence à sua empresa.';
  end if;
end;
$$;

revoke all on function public.admin_definir_pin(uuid,text,boolean,boolean) from public, anon;
revoke all on function public.admin_alterar_acesso_pin(uuid,boolean) from public, anon;
grant execute on function public.admin_definir_pin(uuid,text,boolean,boolean) to authenticated;
grant execute on function public.admin_alterar_acesso_pin(uuid,boolean) to authenticated;

commit;



-- =====================================================================
-- SEÇÃO 18 — V29-CORRECAO-RETORNO
-- Origem histórica: supabase-v29-correcao-tipo-retorno-pin.sql
-- =====================================================================

begin;

-- Correção V29: a função já existia com outro tipo de retorno.
-- PostgreSQL exige DROP FUNCTION antes de recriá-la com novo RETURNS TABLE.

drop function if exists public.admin_definir_pin(uuid,text,boolean,boolean);

create or replace function public.admin_definir_pin(
  p_funcionario_id uuid,
  p_pin text,
  p_exigir_troca boolean default false,
  p_acesso_ativo boolean default true
)
returns table(
  id uuid,
  matricula text,
  acesso_ponto_ativo boolean,
  exigir_troca_pin boolean,
  pin_configurado boolean
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Sessão administrativa obrigatória.';
  end if;

  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    raise exception 'O PIN deve conter exatamente 4 números.';
  end if;

  update public.funcionarios f
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
         acesso_ponto_ativo = coalesce(p_acesso_ativo, true),
         exigir_troca_pin = coalesce(p_exigir_troca, false),
         tentativas_pin = 0,
         bloqueado_ate = null
   where f.id = p_funcionario_id
     and f.empresa_id = v_empresa;

  if not found then
    raise exception 'Funcionário não encontrado ou não pertence à sua empresa.';
  end if;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, acao, tabela, registro_id, dados_novos
  ) values (
    v_empresa,
    auth.uid(),
    'PIN_REDEFINIDO',
    'funcionarios',
    p_funcionario_id,
    jsonb_build_object(
      'exigir_troca', coalesce(p_exigir_troca, false),
      'acesso_ativo', coalesce(p_acesso_ativo, true),
      'pin_configurado', true
    )
  );

  return query
  select
    f.id,
    f.matricula,
    f.acesso_ponto_ativo,
    f.exigir_troca_pin,
    (f.pin_hash is not null)
  from public.funcionarios f
  where f.id = p_funcionario_id
    and f.empresa_id = v_empresa;
end;
$$;

revoke all on function public.admin_definir_pin(uuid,text,boolean,boolean)
from public, anon;

grant execute on function public.admin_definir_pin(uuid,text,boolean,boolean)
to authenticated;

commit;



-- =====================================================================
-- SEÇÃO 19 — V30.3
-- Origem histórica: supabase-v30-3-criar-listar-meus-ajustes.sql
-- =====================================================================

begin;

-- Correção V30.3
-- O frontend chama public.listar_meus_ajustes(p_token), mas a função
-- não existe no banco. Este script recria a função usada pela tela
-- da funcionária e força a atualização do cache do PostgREST.

create or replace function public.listar_meus_ajustes(p_token text)
returns setof public.solicitacoes_ajuste
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  return query
  select s.*
  from public.solicitacoes_ajuste as s
  where s.funcionario_id = v_funcionario.id
  order by s.criado_em desc
  limit 50;
end;
$$;

revoke all on function public.listar_meus_ajustes(text)
from public;

grant execute on function public.listar_meus_ajustes(text)
to anon, authenticated;

commit;

-- Solicita ao Supabase/PostgREST que recarregue imediatamente as funções.
notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 20 — V31
-- Origem histórica: supabase-v31-homologacao.sql
-- =====================================================================

begin;

create or replace function public.criar_funcionario_homologacao_admin()
returns table(funcionario_id uuid,nome text,matricula text,pin_configurado boolean)
language plpgsql security definer set search_path=public,extensions as $$
declare v_empresa uuid; v_id uuid;
begin
  select p.empresa_id into v_empresa from public.perfis p
  where p.id=auth.uid() and p.papel='administrador' and p.ativo=true;
  if v_empresa is null then raise exception 'Sessão administrativa obrigatória.'; end if;

  select f.id into v_id from public.funcionarios f
  where f.empresa_id=v_empresa and f.matricula='999' limit 1;

  if v_id is null then
  else
  end if;

  if not exists(select 1 from public.jornadas j where j.funcionario_id=v_id) then
    insert into public.jornadas(empresa_id,funcionario_id,dia_semana,entrada,inicio_intervalo,fim_intervalo,saida,ativo)
    select v_empresa,v_id,d,'09:00'::time,'13:00'::time,'13:30'::time,
      case when d=3 then '18:00'::time when d=4 then '18:30'::time when d=5 then '17:00'::time else '19:00'::time end,true
    from generate_series(1,5) d;
  end if;


  return query select f.id,f.nome,f.matricula,(f.pin_hash is not null) from public.funcionarios f where f.id=v_id;
end $$;

create or replace function public.resetar_funcionario_homologacao_admin()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_empresa uuid; v_id uuid; v_total integer:=0; v_n integer;
begin
  select p.empresa_id into v_empresa from public.perfis p where p.id=auth.uid() and p.papel='administrador' and p.ativo=true;
  if v_empresa is null then raise exception 'Sessão administrativa obrigatória.'; end if;
  select f.id into v_id from public.funcionarios f where f.empresa_id=v_empresa and f.matricula='999' limit 1;
  if v_id is null then raise exception 'Crie primeiro o funcionário de homologação.'; end if;

  delete from public.sessoes_funcionario s where s.funcionario_id=v_id; get diagnostics v_n=row_count; v_total:=v_total+v_n;
  if to_regclass('public.solicitacoes_ajuste') is not null then execute 'delete from public.solicitacoes_ajuste where funcionario_id=$1' using v_id; get diagnostics v_n=row_count; v_total:=v_total+v_n; end if;
  if to_regclass('public.movimentacoes_jornada') is not null then execute 'delete from public.movimentacoes_jornada where funcionario_id=$1' using v_id; get diagnostics v_n=row_count; v_total:=v_total+v_n; end if;
  delete from public.ocorrencias o where o.funcionario_id=v_id; get diagnostics v_n=row_count; v_total:=v_total+v_n;
  delete from public.marcacoes m where m.funcionario_id=v_id; get diagnostics v_n=row_count; v_total:=v_total+v_n;

  insert into public.logs_auditoria(empresa_id,usuario_id,acao,tabela,registro_id,dados_novos)
  values(v_empresa,auth.uid(),'HOMOLOGACAO_RESETADA','funcionarios',v_id::text,jsonb_build_object('registros_removidos',v_total));
  return jsonb_build_object('funcionario_id',v_id,'registros_removidos',v_total,'matricula','999','pin','9999');
end $$;

revoke all on function public.criar_funcionario_homologacao_admin() from public,anon;
revoke all on function public.resetar_funcionario_homologacao_admin() from public,anon;
grant execute on function public.criar_funcionario_homologacao_admin() to authenticated;
grant execute on function public.resetar_funcionario_homologacao_admin() to authenticated;
commit;
notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 21 — RC1.1
-- Origem histórica: supabase-rc1-1-atualizacao.sql
-- =====================================================================

begin;

-- RC1.2 — correção definitiva do registro de ponto por dispositivo
-- Esta versão não depende da implementação antiga de registrar_ponto_com_pin.
-- O tipo da marcação é declarado explicitamente como public.tipo_marcacao.

create or replace function public.registrar_ponto_com_pin(p_token text)
returns public.marcacoes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_agora timestamptz := clock_timestamp();
  v_data date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  select count(*)::integer
    into v_quantidade
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  insert into public.marcacoes as m (
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'pin'
  )
  returning m.* into v_marcacao;

  return v_marcacao;
end;
$$;

create or replace function public.registrar_ponto_dispositivo(
  p_token text,
  p_dispositivo_token text,
  p_user_agent text default null
)
returns public.marcacoes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_agora timestamptz := clock_timestamp();
  v_data date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto as d
  where d.token_hash =
        encode(extensions.digest(coalesce(p_dispositivo_token, ''), 'sha256'), 'hex')
    and d.ativo = true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Registro bloqueado: computador não autorizado.';
  end if;

  v_funcionario := public.funcionario_por_token(p_token);

  if v_funcionario.empresa_id <> v_dispositivo.empresa_id then
    raise exception 'Dispositivo não autorizado para esta empresa.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  insert into public.marcacoes as m (
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'dispositivo'
  )
  returning m.* into v_marcacao;

  update public.dispositivos_ponto as d
     set ultimo_uso_em = v_agora
   where d.id = v_dispositivo.id;

  return v_marcacao;
end;
$$;

revoke all on function public.registrar_ponto_com_pin(text)
from public, anon, authenticated;

revoke all on function public.registrar_ponto_dispositivo(text,text,text)
from public;

grant execute on function public.registrar_ponto_dispositivo(text,text,text)
to anon, authenticated;

commit;

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 22 — RC1-CORRECOES
-- Origem histórica: supabase-rc1-correcoes-consolidadas.sql
-- =====================================================================

-- PLENITUDE PONTO 1.0.0 RC1
-- Correções consolidadas e idempotentes. Execute o arquivo inteiro no SQL Editor.

-- ============================================================
-- Fonte consolidada: supabase-v26-v27-correcao-ativo-ambiguo.sql
-- ============================================================
-- Correção V26/V27 — referência ambígua à coluna "ativo"
-- Execute após as versões V26 e V27.

begin;

create or replace function public.autorizar_dispositivo_ponto_admin(
  p_token text,
  p_nome text,
  p_user_agent text default null
)
returns table(id uuid,nome text,ativo boolean,autorizado_em timestamptz)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa uuid;
  v_id uuid;
begin
  if not public.usuario_e_admin() then
    raise exception 'Apenas administradores podem autorizar dispositivos.';
  end if;

  if length(coalesce(p_token,'')) < 32 then
    raise exception 'Token de dispositivo inválido.';
  end if;

  v_empresa := public.empresa_do_usuario();
  if v_empresa is null then
    raise exception 'Empresa não identificada.';
  end if;

  -- Somente uma máquina ativa por empresa.
  update public.dispositivos_ponto as dp
     set ativo = false,
         revogado_em = clock_timestamp()
   where dp.empresa_id = v_empresa
     and dp.ativo = true;

  insert into public.dispositivos_ponto as dp (
    empresa_id,
    nome,
    token_hash,
    ativo,
    autorizado_por,
    user_agent_autorizacao
  ) values (
    v_empresa,
    coalesce(nullif(trim(p_nome),''),'Computador da loja'),
    encode(digest(p_token,'sha256'),'hex'),
    true,
    auth.uid(),
    left(p_user_agent,1000)
  )
  returning dp.id into v_id;

  perform public.registrar_evento_auditoria(
    'AUTORIZAR',
    'dispositivos_ponto',
    v_id::text,
    'Computador autorizado para registrar ponto',
    jsonb_build_object(
      'nome',coalesce(nullif(trim(p_nome),''),'Computador da loja')
    ),
    'web'
  );

  return query
  select dp.id, dp.nome, dp.ativo, dp.autorizado_em
    from public.dispositivos_ponto as dp
   where dp.id = v_id;
end;
$$;

-- Mantém a proteção da V27: a função-base não pode ser chamada diretamente.
revoke execute on function public.autorizar_dispositivo_ponto_admin(text,text,text)
  from authenticated, anon, public;

-- O wrapper com PIN Mestre continua sendo o ponto de entrada autorizado.
grant execute on function public.autorizar_dispositivo_ponto_master_admin(text,text,text,text)
  to authenticated;

commit;

-- ============================================================
-- Fonte consolidada: supabase-v29-correcao-tipo-retorno-pin.sql
-- ============================================================
begin;

-- Correção V29: a função já existia com outro tipo de retorno.
-- PostgreSQL exige DROP FUNCTION antes de recriá-la com novo RETURNS TABLE.

drop function if exists public.admin_definir_pin(uuid,text,boolean,boolean);

create or replace function public.admin_definir_pin(
  p_funcionario_id uuid,
  p_pin text,
  p_exigir_troca boolean default false,
  p_acesso_ativo boolean default true
)
returns table(
  id uuid,
  matricula text,
  acesso_ponto_ativo boolean,
  exigir_troca_pin boolean,
  pin_configurado boolean
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Sessão administrativa obrigatória.';
  end if;

  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    raise exception 'O PIN deve conter exatamente 4 números.';
  end if;

  update public.funcionarios f
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
         acesso_ponto_ativo = coalesce(p_acesso_ativo, true),
         exigir_troca_pin = coalesce(p_exigir_troca, false),
         tentativas_pin = 0,
         bloqueado_ate = null
   where f.id = p_funcionario_id
     and f.empresa_id = v_empresa;

  if not found then
    raise exception 'Funcionário não encontrado ou não pertence à sua empresa.';
  end if;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, acao, tabela, registro_id, dados_novos
  ) values (
    v_empresa,
    auth.uid(),
    'PIN_REDEFINIDO',
    'funcionarios',
    p_funcionario_id,
    jsonb_build_object(
      'exigir_troca', coalesce(p_exigir_troca, false),
      'acesso_ativo', coalesce(p_acesso_ativo, true),
      'pin_configurado', true
    )
  );

  return query
  select
    f.id,
    f.matricula,
    f.acesso_ponto_ativo,
    f.exigir_troca_pin,
    (f.pin_hash is not null)
  from public.funcionarios f
  where f.id = p_funcionario_id
    and f.empresa_id = v_empresa;
end;
$$;

revoke all on function public.admin_definir_pin(uuid,text,boolean,boolean)
from public, anon;

grant execute on function public.admin_definir_pin(uuid,text,boolean,boolean)
to authenticated;

commit;

-- ============================================================
-- Fonte consolidada: supabase-correcao-login-matricula-pin.sql
-- ============================================================
begin;

-- Corrige o login do funcionário para:
-- 1) aceitar matrícula com ou sem zeros à esquerda (001 = 0001);
-- 2) validar PIN usando apenas algarismos;
-- 3) acessar corretamente as funções do pgcrypto no schema extensions.
create or replace function public.login_funcionario_pin(p_matricula text,p_pin text)
returns table(
  token text,
  funcionario_id uuid,
  nome text,
  cargo text,
  matricula text,
  foto_url text,
  exigir_troca_pin boolean,
  expira_em timestamptz
)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  f public.funcionarios%rowtype;
  v_token text;
  v_now timestamptz:=clock_timestamp();
  v_matricula_normalizada text;
begin
  if coalesce(p_pin,'') !~ '^[0-9]{4}$' then
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  -- Remove espaços e zeros à esquerda. Mantém "0" quando a matrícula for só zeros.
  v_matricula_normalizada := coalesce(nullif(ltrim(btrim(coalesce(p_matricula,'')),'0'),''),'0');

  select fun.*
    into f
    from public.funcionarios fun
   where fun.ativo=true
     and coalesce(nullif(ltrim(btrim(fun.matricula),'0'),''),'0')=v_matricula_normalizada
   order by fun.criado_em asc nulls last
   limit 1;

  if f.id is null or f.pin_hash is null then
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  if not f.acesso_ponto_ativo then
    raise exception 'Acesso ao ponto bloqueado. Procure o administrador.';
  end if;

  if f.bloqueado_ate is not null and f.bloqueado_ate>v_now then
    raise exception 'Acesso temporariamente bloqueado. Tente novamente mais tarde.';
  end if;

  if extensions.crypt(p_pin,f.pin_hash)<>f.pin_hash then
    update public.funcionarios fun
       set tentativas_pin=coalesce(fun.tentativas_pin,0)+1,
           bloqueado_ate=case
             when coalesce(fun.tentativas_pin,0)+1>=5 then v_now+interval '15 minutes'
             else null
           end
     where fun.id=f.id;
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  update public.funcionarios fun
     set tentativas_pin=0,
         bloqueado_ate=null,
         ultimo_acesso_em=v_now
   where fun.id=f.id;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');

  insert into public.sessoes_funcionario(funcionario_id,token_hash,expira_em)
  values(
    f.id,
    encode(extensions.digest(v_token,'sha256'),'hex'),
    v_now+interval '12 hours'
  );

  return query
  select v_token,f.id,f.nome,f.cargo,f.matricula,f.foto_url,
         f.exigir_troca_pin,v_now+interval '12 hours';
end $$;

revoke all on function public.login_funcionario_pin(text,text) from public,anon,authenticated;
-- A função direta permanece bloqueada para o navegador.
-- login_funcionario_pin_dispositivo() continua chamando-a internamente como SECURITY DEFINER.

commit;

-- ============================================================
-- Fonte consolidada: supabase-v30-2-correcao-status-banco-horas.sql
-- ============================================================
begin;

-- Correção V30.2
-- O erro "column reference status is ambiguous" vinha do cálculo do banco de horas.
-- A função possuía uma variável local chamada status e também consultava
-- movimentacoes_jornada.status sem alias. Agora todas as referências são explícitas.

create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; v_status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    if j.id is not null and entrada_real is not null and entrada_real > (d.data+j.entrada) at time zone e.timezone
       and entrada_real <= ((d.data+j.entrada) at time zone e.timezone)+make_interval(mins=>e.tolerancia_entrada_minutos) then
      entrada_calc:=(d.data+j.entrada) at time zone e.timezone; tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null and saida_real < (d.data+j.saida) at time zone e.timezone
       and saida_real >= ((d.data+j.saida) at time zone e.timezone)-make_interval(mins=>e.tolerancia_saida_minutos) then
      saida_calc:=(d.data+j.saida) at time zone e.timezone; tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    select coalesce(sum(case when mj.aprovado and mj.efeito_calculo='descontar' and mj.fim_em is not null then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int else 0 end),0),
           coalesce(sum(case when mj.aprovado and mj.efeito_calculo='abonar' and mj.fim_em is not null then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int else 0 end),0),
           coalesce(bool_or(mj.aprovado and mj.efeito_calculo='credito'),false),
           coalesce(jsonb_agg(jsonb_build_object('id',mj.id,'inicio_em',mj.inicio_em,'fim_em',mj.fim_em,'classificacao',mj.classificacao,'efeito',mj.efeito_calculo,'status',mj.status,'aprovado',mj.aprovado) order by mj.inicio_em),'[]'::jsonb)
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada as mj where mj.funcionario_id=f.id and mj.data_local=d.data and mj.status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then v_status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then v_status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then v_status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then v_status:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then v_status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then v_status:='aguardando'; else v_status:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0 and not e.horas_extras_automaticas and not extra_autorizada then saldo:=0; end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',v_status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;


revoke all on function public._calcular_banco_horas_json(uuid,date,date)
from public, anon, authenticated;

commit;

-- ============================================================
-- Fonte consolidada: supabase-v30-3-instalar-modulo-ajustes-completo.sql
-- ============================================================
begin;

-- V30.3 corrigida
-- Instala o módulo de solicitações de ajuste que está ausente no banco.
-- O erro anterior ocorreu porque a tabela public.solicitacoes_ajuste não existia.

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
  if exists(select 1 from public.marcacoes as m where m.funcionario_id=f.id and m.data_local=p_data and m.tipo=p_tipo) then
    raise exception 'Essa marcação já existe. Para alterar um horário existente, procure o administrador.';
  end if;
  if exists(select 1 from public.solicitacoes_ajuste as s where s.funcionario_id=f.id and s.data_marcacao=p_data and s.tipo_marcacao=p_tipo and s.status='pendente') then
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
  return query select s.* from public.solicitacoes_ajuste as s where s.funcionario_id=f.id order by s.criado_em desc limit 50;
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
    if exists(select 1 from public.marcacoes as m where m.funcionario_id=s.funcionario_id and m.data_local=s.data_marcacao and m.tipo=s.tipo_marcacao) then
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


commit;

notify pgrst, 'reload schema';

-- ============================================================
-- Fonte consolidada: supabase-v31-1-corrigir-ajustes-pendentes-admin.sql
-- ============================================================
begin;

-- Correção V31.1
-- Corrige a função usada no painel administrativo para contar/listar
-- solicitações de ajuste pendentes. Todas as colunas recebem alias e
-- conversões explícitas para evitar erro 400 do PostgREST.

create or replace function public.listar_ajustes_admin(
  p_status text default null
)
returns table(
  id uuid,
  funcionario_id uuid,
  funcionario_nome text,
  matricula text,
  data_marcacao date,
  tipo_marcacao public.tipo_marcacao,
  horario_solicitado time,
  justificativa text,
  status text,
  resposta_administrador text,
  criado_em timestamptz,
  analisado_em timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa_id uuid;
begin
  select p.empresa_id
    into v_empresa_id
  from public.perfis as p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa_id is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  return query
  select
    s.id::uuid,
    s.funcionario_id::uuid,
    f.nome::text,
    f.matricula::text,
    s.data_marcacao::date,
    s.tipo_marcacao::public.tipo_marcacao,
    s.horario_solicitado::time,
    s.justificativa::text,
    s.status::text,
    s.resposta_administrador::text,
    s.criado_em::timestamptz,
    s.analisado_em::timestamptz
  from public.solicitacoes_ajuste as s
  inner join public.funcionarios as f
    on f.id = s.funcionario_id
  where s.empresa_id = v_empresa_id
    and (
      p_status is null
      or btrim(p_status) = ''
      or s.status::text = p_status
    )
  order by
    case when s.status::text = 'pendente' then 0 else 1 end,
    s.criado_em desc;
end;
$$;

revoke all on function public.listar_ajustes_admin(text)
from public, anon;

grant execute on function public.listar_ajustes_admin(text)
to authenticated;

commit;

notify pgrst, 'reload schema';

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 23 — RC2.3
-- Origem histórica: supabase-rc2-3-protecao-multiplos-cliques.sql
-- =====================================================================

begin;

-- Plenitude Ponto 1.0.0 RC2.3
-- Proteção contra duplo clique, múltiplas abas e chamadas concorrentes.
--
-- Camadas:
-- 1) pg_advisory_xact_lock serializa marcações do mesmo funcionário;
-- 2) janela mínima de 5 segundos recusa marcações consecutivas;
-- 3) o frontend mantém o botão bloqueado e mostra contagem regressiva.

create or replace function public.registrar_ponto_com_pin(p_token text)
returns public.marcacoes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_agora timestamptz := clock_timestamp();
  v_data date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_ultima_marcacao timestamptz;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  -- Uma única transação por funcionário pode calcular/inserir a próxima etapa.
  perform pg_advisory_xact_lock(hashtextextended(v_funcionario.id::text, 20260730));

  select max(m.registrado_em)
    into v_ultima_marcacao
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  if v_ultima_marcacao is not null
     and v_agora - v_ultima_marcacao < interval '5 seconds' then
    raise exception 'Aguarde alguns segundos antes de registrar novamente.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  insert into public.marcacoes as m (
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'pin'
  )
  returning m.* into v_marcacao;

  return v_marcacao;
end;
$$;

create or replace function public.registrar_ponto_dispositivo(
  p_token text,
  p_dispositivo_token text,
  p_user_agent text default null
)
returns public.marcacoes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_agora timestamptz := clock_timestamp();
  v_data date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_ultima_marcacao timestamptz;
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto as d
  where d.token_hash =
        encode(extensions.digest(coalesce(p_dispositivo_token, ''), 'sha256'), 'hex')
    and d.ativo = true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Registro bloqueado: computador não autorizado.';
  end if;

  v_funcionario := public.funcionario_por_token(p_token);

  if v_funcionario.empresa_id <> v_dispositivo.empresa_id then
    raise exception 'Dispositivo não autorizado para esta empresa.';
  end if;

  -- Protege também chamadas simultâneas vindas de duas abas/navegadores.
  perform pg_advisory_xact_lock(hashtextextended(v_funcionario.id::text, 20260730));

  select max(m.registrado_em)
    into v_ultima_marcacao
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  if v_ultima_marcacao is not null
     and v_agora - v_ultima_marcacao < interval '5 seconds' then
    raise exception 'Aguarde alguns segundos antes de registrar novamente.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  insert into public.marcacoes as m (
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'dispositivo'
  )
  returning m.* into v_marcacao;

  update public.dispositivos_ponto as d
     set ultimo_uso_em = v_agora
   where d.id = v_dispositivo.id;

  return v_marcacao;
end;
$$;

revoke all on function public.registrar_ponto_com_pin(text)
from public, anon, authenticated;

revoke all on function public.registrar_ponto_dispositivo(text,text,text)
from public;

grant execute on function public.registrar_ponto_dispositivo(text,text,text)
to anon, authenticated;

commit;

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 24 — RC3-VALIDACAO-CORRIGIDA
-- Origem histórica: supabase-rc3-1-correcao-validacao-automatica.sql
-- =====================================================================

begin;

-- Plenitude Ponto 1.0.0 RC3
-- Validação automática dos itens do checklist que podem ser comprovados
-- diretamente pelo banco de dados. Itens visuais ou que dependem de ação
-- humana continuam manuais.

create or replace function public.validar_homologacao_automatica_admin()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_funcionario public.funcionarios%rowtype;
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_checks jsonb := '{}'::jsonb;
  v_tipos public.tipo_marcacao[];
  v_qtd integer;
  v_mov_aberta integer;
  v_mov_encerrada integer;
  v_aj_pendentes integer;
  v_aj_aprovados integer;
  v_aj_rejeitados integer;
  v_auditoria integer;
  v_fechado boolean;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis as p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  select f.*
    into v_funcionario
  from public.funcionarios as f
  where f.empresa_id = v_empresa
    and f.matricula = '999'
  limit 1;

  -- Preparação
  v_checks := v_checks || jsonb_build_object(
    'diagnostico_tecnico',
    jsonb_build_object(
      'ok', public.diagnostico_homologacao_admin()->>'status' = 'aprovado',
      'detalhe', 'Diagnóstico técnico consultado no Supabase.'
    ),
    'funcionario_999',
    jsonb_build_object(
      'ok', v_funcionario.id is not null,
      'detalhe', coalesce(v_funcionario.nome, 'Funcionário 999 não encontrado.')
    ),
    'pin_999',
    jsonb_build_object(
      'ok', v_funcionario.pin_hash is not null,
      'detalhe', case when v_funcionario.pin_hash is not null then 'PIN configurado.' else 'PIN não configurado.' end
    ),
    'acesso_999',
    jsonb_build_object(
      'ok', coalesce(v_funcionario.ativo,false) and coalesce(v_funcionario.acesso_ponto_ativo,false),
      'detalhe', case when coalesce(v_funcionario.acesso_ponto_ativo,false) then 'Acesso ativo.' else 'Acesso bloqueado.' end
    ),
    'dispositivo_autorizado',
    jsonb_build_object(
      'ok', exists(
        select 1 from public.dispositivos_ponto as d
        where d.empresa_id = v_empresa and d.ativo = true
      ),
      'detalhe', 'Verificação de dispositivo ativo da empresa.'
    )
  );

  if v_funcionario.id is null then
    return jsonb_build_object(
      'gerado_em', clock_timestamp(),
      'funcionario_id', null,
      'data', v_hoje,
      'checks', v_checks
    );
  end if;

  select count(*)::integer,
         array_agg(m.tipo order by m.registrado_em, m.id)
    into v_qtd, v_tipos
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_hoje;

  -- Jornada
  v_checks := v_checks || jsonb_build_object(
    'entrada_registrada',
    jsonb_build_object(
      'ok', 'entrada'::public.tipo_marcacao = any(coalesce(v_tipos, array[]::public.tipo_marcacao[])),
      'detalhe', format('%s marcação(ões) hoje.', coalesce(v_qtd,0))
    ),
    'almoco_registrado',
    jsonb_build_object(
      'ok', 'inicio_intervalo'::public.tipo_marcacao = any(coalesce(v_tipos, array[]::public.tipo_marcacao[])),
      'detalhe', 'Início do intervalo consultado.'
    ),
    'retorno_registrado',
    jsonb_build_object(
      'ok', 'fim_intervalo'::public.tipo_marcacao = any(coalesce(v_tipos, array[]::public.tipo_marcacao[])),
      'detalhe', 'Retorno do intervalo consultado.'
    ),
    'saida_registrada',
    jsonb_build_object(
      'ok', 'saida'::public.tipo_marcacao = any(coalesce(v_tipos, array[]::public.tipo_marcacao[])),
      'detalhe', 'Saída final consultada.'
    ),
    'ordem_jornada',
    jsonb_build_object(
      'ok', coalesce(v_tipos, array[]::public.tipo_marcacao[]) <@ array[
        'entrada'::public.tipo_marcacao,
        'inicio_intervalo'::public.tipo_marcacao,
        'fim_intervalo'::public.tipo_marcacao,
        'saida'::public.tipo_marcacao
      ]
      and (
        v_qtd = 0
        or v_tipos = (
          array[
            'entrada'::public.tipo_marcacao,
            'inicio_intervalo'::public.tipo_marcacao,
            'fim_intervalo'::public.tipo_marcacao,
            'saida'::public.tipo_marcacao
          ]
        )[1:v_qtd]
      ),
      'detalhe', 'Sequência esperada: Entrada → Almoço → Retorno → Saída.'
    ),
    'jornada_concluida',
    jsonb_build_object(
      'ok', v_qtd = 4 and v_tipos = array[
        'entrada'::public.tipo_marcacao,
        'inicio_intervalo'::public.tipo_marcacao,
        'fim_intervalo'::public.tipo_marcacao,
        'saida'::public.tipo_marcacao
      ],
      'detalhe', format('%s de 4 marcações válidas.', coalesce(v_qtd,0))
    ),
    'sem_quinta_marcacao',
    jsonb_build_object(
      'ok', coalesce(v_qtd,0) <= 4,
      'detalhe', format('%s marcação(ões) encontradas hoje.', coalesce(v_qtd,0))
    )
  );

  -- Movimentações temporárias
  select count(*) filter (where m.status = 'aberta')::integer,
         count(*) filter (where m.status = 'encerrada')::integer
    into v_mov_aberta, v_mov_encerrada
  from public.movimentacoes_jornada as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_hoje;

  v_checks := v_checks || jsonb_build_object(
    'movimentacao_saida',
    jsonb_build_object(
      'ok', (v_mov_aberta + v_mov_encerrada) > 0,
      'detalhe', format('%s movimentação(ões) hoje.', v_mov_aberta + v_mov_encerrada)
    ),
    'movimentacao_fora',
    jsonb_build_object(
      'ok', v_mov_aberta > 0,
      'detalhe', format('%s saída(s) aguardando retorno.', v_mov_aberta)
    ),
    'movimentacao_retorno',
    jsonb_build_object(
      'ok', v_mov_encerrada > 0,
      'detalhe', format('%s movimentação(ões) encerrada(s).', v_mov_encerrada)
    ),
    'movimentacao_classificada',
    jsonb_build_object(
      'ok', exists(
        select 1
        from public.movimentacoes_jornada as m
        where m.funcionario_id = v_funcionario.id
          and m.classificacao is not null
          and m.efeito_calculo <> 'pendente'
      ),
      'detalhe', 'Classificação e efeito administrativo consultados.'
    )
  );

  -- Ajustes
  select count(*) filter (where s.status = 'pendente')::integer,
         count(*) filter (where s.status = 'aprovada')::integer,
         count(*) filter (where s.status = 'rejeitada')::integer
    into v_aj_pendentes, v_aj_aprovados, v_aj_rejeitados
  from public.solicitacoes_ajuste as s
  where s.funcionario_id = v_funcionario.id;

  v_checks := v_checks || jsonb_build_object(
    'ajuste_solicitado',
    jsonb_build_object(
      'ok', (v_aj_pendentes + v_aj_aprovados + v_aj_rejeitados) > 0,
      'detalhe', format('%s solicitação(ões) encontradas.', v_aj_pendentes + v_aj_aprovados + v_aj_rejeitados)
    ),
    'ajuste_aprovado',
    jsonb_build_object(
      'ok', v_aj_aprovados > 0,
      'detalhe', format('%s solicitação(ões) aprovada(s).', v_aj_aprovados)
    ),
    'ajuste_rejeitado',
    jsonb_build_object(
      'ok', v_aj_rejeitados > 0,
      'detalhe', format('%s solicitação(ões) rejeitada(s).', v_aj_rejeitados)
    ),
    'ajuste_refletido',
    jsonb_build_object(
      'ok', exists(
        select 1
        from public.solicitacoes_ajuste as s
        join public.marcacoes as m on m.id = s.marcacao_gerada_id
        where s.funcionario_id = v_funcionario.id
          and s.status = 'aprovada'
      ),
      'detalhe', 'Marcação gerada por ajuste aprovado.'
    )
  );

  -- Auditoria
  select count(*)::integer
    into v_auditoria
  from public.logs_auditoria as l
  where l.empresa_id = v_empresa
    and (
      l.registro_id = v_funcionario.id::text
      or coalesce(l.dados::text,'') like '%' || v_funcionario.id::text || '%'
      or coalesce(l.dados_novos::text,'') like '%' || v_funcionario.id::text || '%'
    );

  v_checks := v_checks || jsonb_build_object(
    'auditoria_funcionario',
    jsonb_build_object(
      'ok', v_auditoria > 0,
      'detalhe', format('%s evento(s) relacionado(s) ao funcionário teste.', v_auditoria)
    ),
    'banco_horas_disponivel',
    jsonb_build_object(
      'ok', to_regprocedure('public.banco_horas_funcionario_token(text,date,date)') is not null,
      'detalhe', 'RPC do banco de horas instalada.'
    ),
    'backup_disponivel',
    jsonb_build_object(
      'ok', to_regclass('public.funcionarios') is not null
            and to_regclass('public.marcacoes') is not null
            and to_regclass('public.logs_auditoria') is not null,
      'detalhe', 'Estruturas necessárias para exportação disponíveis.'
    )
  );

  -- Fechamento da competência atual
  select exists(
    select 1
    from public.fechamentos_mensais as fm
    where fm.empresa_id = v_empresa
      and fm.ano = extract(year from v_hoje)::integer
      and fm.mes = extract(month from v_hoje)::integer
      and fm.status = 'fechada'
  ) into v_fechado;

  v_checks := v_checks || jsonb_build_object(
    'competencia_fechada',
    jsonb_build_object(
      'ok', v_fechado,
      'detalhe', case when v_fechado then 'Competência atual fechada.' else 'Competência atual está aberta.' end
    ),
    'competencia_reaberta',
    jsonb_build_object(
      'ok', exists(
        select 1
        from public.logs_auditoria as l
        where l.empresa_id = v_empresa
          and upper(coalesce(l.acao,'')) like '%REABR%'
      ),
      'detalhe', 'Evento de reabertura consultado na auditoria.'
    )
  );

  return jsonb_build_object(
    'gerado_em', clock_timestamp(),
    'funcionario_id', v_funcionario.id,
    'data', v_hoje,
    'checks', v_checks
  );
end;
$$;

revoke all on function public.validar_homologacao_automatica_admin()
from public, anon;

grant execute on function public.validar_homologacao_automatica_admin()
to authenticated;

commit;

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 25 — RC3.2-AJUSTE
-- Origem histórica: supabase-rc3-2-correcao-solicitacao-ajuste.sql
-- =====================================================================

begin;

-- RC3.2 — correção da solicitação de ajuste
-- A função possuía uma variável PL/pgSQL chamada "s" e também usava
-- "s" como alias da tabela solicitacoes_ajuste. Isso tornava
-- s.funcionario_id ambíguo no PostgreSQL.

create or replace function public.solicitar_ajuste_ponto(
  p_token text,
  p_data date,
  p_tipo public.tipo_marcacao,
  p_horario time,
  p_justificativa text
)
returns public.solicitacoes_ajuste
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_solicitacao public.solicitacoes_ajuste%rowtype;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  if p_data > (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Não é possível solicitar ajuste para uma data futura.';
  end if;

  if char_length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'Informe uma justificativa com pelo menos 10 caracteres.';
  end if;

  if exists (
    select 1
    from public.marcacoes as m
    where m.funcionario_id = v_funcionario.id
      and m.data_local = p_data
      and m.tipo = p_tipo
  ) then
    raise exception 'Essa marcação já existe. Para alterar um horário existente, procure o administrador.';
  end if;

  if exists (
    select 1
    from public.solicitacoes_ajuste as sa
    where sa.funcionario_id = v_funcionario.id
      and sa.data_marcacao = p_data
      and sa.tipo_marcacao = p_tipo
      and sa.status = 'pendente'
  ) then
    raise exception 'Já existe uma solicitação pendente para essa marcação.';
  end if;

  insert into public.solicitacoes_ajuste (
    empresa_id,
    funcionario_id,
    data_marcacao,
    tipo_marcacao,
    horario_solicitado,
    justificativa
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    p_data,
    p_tipo,
    p_horario,
    btrim(p_justificativa)
  )
  returning * into v_solicitacao;

  return v_solicitacao;
end;
$$;

revoke all on function public.solicitar_ajuste_ponto(
  text,
  date,
  public.tipo_marcacao,
  time,
  text
) from public;

grant execute on function public.solicitar_ajuste_ponto(
  text,
  date,
  public.tipo_marcacao,
  time,
  text
) to anon, authenticated;

commit;

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 26 — RC4.4
-- Origem histórica: supabase-rc4-4-pendencias-retorno.sql
-- =====================================================================

begin;

create or replace function public.registrar_movimentacao_dispositivo(
  p_token text,
  p_dispositivo_token text,
  p_acao text,
  p_motivo text default null,
  p_user_agent text default null
)
returns public.movimentacoes_jornada
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_movimentacao public.movimentacoes_jornada%rowtype;
  v_agora timestamptz := clock_timestamp();
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  select d.* into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash=encode(extensions.digest(coalesce(p_dispositivo_token,''),'sha256'),'hex')
    and d.ativo=true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Registro bloqueado: computador não autorizado.';
  end if;

  v_funcionario:=public.funcionario_por_token(p_token);

  if v_funcionario.empresa_id<>v_dispositivo.empresa_id then
    raise exception 'Dispositivo não autorizado para esta empresa.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_funcionario.id::text||':movimentacao',20260731));

  if p_acao='saida' then
    if exists(
      select 1 from public.movimentacoes_jornada mj
      where mj.funcionario_id=v_funcionario.id
        and mj.data_local=v_hoje
        and mj.status='aberta'
    ) then
      raise exception 'Já existe uma saída temporária de hoje aguardando retorno.';
    end if;

    insert into public.movimentacoes_jornada(
      empresa_id,funcionario_id,data_local,inicio_em,origem,motivo_informado,status
    ) values(
      v_funcionario.empresa_id,v_funcionario.id,v_hoje,v_agora,
      'funcionario',nullif(btrim(p_motivo),''),'aberta'
    )
    returning * into v_movimentacao;

  elsif p_acao='retorno' then
    select mj.* into v_movimentacao
    from public.movimentacoes_jornada mj
    where mj.funcionario_id=v_funcionario.id
      and mj.data_local=v_hoje
      and mj.status='aberta'
    order by mj.inicio_em desc
    limit 1
    for update;

    if v_movimentacao.id is null then
      raise exception 'Não existe saída temporária aberta hoje.';
    end if;

    update public.movimentacoes_jornada mj
       set fim_em=v_agora,status='encerrada',atualizado_em=v_agora
     where mj.id=v_movimentacao.id
    returning mj.* into v_movimentacao;
  else
    raise exception 'Ação inválida.';
  end if;

  update public.dispositivos_ponto
     set ultimo_uso_em=v_agora
   where id=v_dispositivo.id;

  return v_movimentacao;
end;
$$;

create or replace function public.listar_pendencias_retorno_funcionario(p_token text)
returns table(
  id uuid,data_local date,inicio_em timestamptz,motivo_informado text,dias_em_aberto integer
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  v_funcionario:=public.funcionario_por_token(p_token);
  return query
  select mj.id,mj.data_local,mj.inicio_em,mj.motivo_informado,(v_hoje-mj.data_local)::integer
  from public.movimentacoes_jornada mj
  where mj.funcionario_id=v_funcionario.id
    and mj.status='aberta'
    and mj.data_local<v_hoje
  order by mj.data_local desc,mj.inicio_em desc;
end;
$$;

create or replace function public.listar_pendencias_retorno_admin()
returns table(
  id uuid,funcionario_id uuid,funcionario_nome text,matricula text,
  data_local date,inicio_em timestamptz,motivo_informado text,dias_em_aberto integer
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  select p.empresa_id into v_empresa
  from public.perfis p
  where p.id=auth.uid() and p.papel='administrador' and p.ativo=true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  return query
  select mj.id,mj.funcionario_id,f.nome,f.matricula,mj.data_local,mj.inicio_em,
         mj.motivo_informado,(v_hoje-mj.data_local)::integer
  from public.movimentacoes_jornada mj
  join public.funcionarios f on f.id=mj.funcionario_id
  where mj.empresa_id=v_empresa
    and mj.status='aberta'
    and mj.data_local<v_hoje
  order by mj.data_local asc,f.nome;
end;
$$;

revoke all on function public.registrar_movimentacao_dispositivo(text,text,text,text,text) from public;
grant execute on function public.registrar_movimentacao_dispositivo(text,text,text,text,text) to anon,authenticated;
revoke all on function public.listar_pendencias_retorno_funcionario(text) from public;
grant execute on function public.listar_pendencias_retorno_funcionario(text) to anon,authenticated;
revoke all on function public.listar_pendencias_retorno_admin() from public,anon;
grant execute on function public.listar_pendencias_retorno_admin() to authenticated;

commit;
notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 27 — RC4.5
-- Origem histórica: supabase-rc4-5-status-movimentacao.sql
-- =====================================================================

begin;

create or replace function public.status_movimentacao_funcionario(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_aberta public.movimentacoes_jornada%rowtype;
  v_pendencias integer := 0;
  v_mais_antiga date;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  select mj.*
    into v_aberta
  from public.movimentacoes_jornada mj
  where mj.funcionario_id = v_funcionario.id
    and mj.data_local = v_hoje
    and mj.status = 'aberta'
  order by mj.inicio_em desc
  limit 1;

  select count(*)::integer, min(mj.data_local)
    into v_pendencias, v_mais_antiga
  from public.movimentacoes_jornada mj
  where mj.funcionario_id = v_funcionario.id
    and mj.status = 'aberta'
    and mj.data_local < v_hoje;

  return jsonb_build_object(
    'data_servidor', v_hoje,
    'fora_da_loja', v_aberta.id is not null,
    'movimentacao_aberta', case
      when v_aberta.id is null then null
      else jsonb_build_object(
        'id', v_aberta.id,
        'data_local', v_aberta.data_local,
        'inicio_em', v_aberta.inicio_em,
        'motivo_informado', v_aberta.motivo_informado,
        'status', v_aberta.status
      )
    end,
    'pendencias_antigas', v_pendencias,
    'pendencia_mais_antiga', v_mais_antiga
  );
end;
$$;

revoke all on function public.status_movimentacao_funcionario(text) from public;
grant execute on function public.status_movimentacao_funcionario(text) to anon, authenticated;

commit;
notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 28 — RC4.6
-- Origem histórica: supabase-rc4-6-verificar-status-saida.sql
-- =====================================================================

-- Verificação da instalação e do estado atual da matrícula 999.

select
  to_regprocedure('public.status_movimentacao_funcionario(text)') is not null
    as rpc_status_instalada,
  to_regprocedure(
    'public.registrar_movimentacao_dispositivo(text,text,text,text,text)'
  ) is not null as rpc_registro_instalada;

select
  f.nome,
  f.matricula,
  mj.id,
  mj.data_local,
  mj.inicio_em,
  mj.fim_em,
  mj.motivo_informado,
  mj.status
from public.funcionarios f
join public.movimentacoes_jornada mj
  on mj.funcionario_id=f.id
where f.matricula='999'
  and mj.status='aberta'
order by mj.data_local desc,mj.inicio_em desc;



-- =====================================================================
-- SEÇÃO 29 — RC4.8
-- Origem histórica: supabase-rc4-8-correcao-auditoria-jsonb.sql
-- =====================================================================

begin;

-- RC4.8 — correção da página Auditoria
-- Causa: COALESCE tentava combinar dados_novos (jsonb) com dados (text).
-- PostgreSQL não permite COALESCE entre jsonb e text sem conversão explícita.

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
  select
    l.id,
    l.criado_em,
    l.usuario_id,
    coalesce(p.nome, 'Sistema')::text as usuario_nome,
    coalesce(u.email, '—')::text as usuario_email,
    l.acao::text,
    l.tabela::text,
    l.registro_id::text,
    coalesce(l.descricao, '')::text as descricao,
    coalesce(l.origem, 'sistema')::text as origem,
    l.dados_anteriores,
    coalesce(
      l.dados_novos,
      case
        when l.dados is null then null::jsonb
        else to_jsonb(l.dados)
      end
    ) as dados_novos
  from public.logs_auditoria as l
  left join public.perfis as p
    on p.id = l.usuario_id
  left join auth.users as u
    on u.id = l.usuario_id
  where l.empresa_id = v_empresa
    and (p_inicio is null or l.criado_em >= p_inicio)
    and (p_fim is null or l.criado_em <= p_fim)
    and (p_acao is null or p_acao = '' or upper(l.acao) = upper(p_acao))
    and (p_tabela is null or p_tabela = '' or l.tabela = p_tabela)
    and (
      p_busca is null
      or p_busca = ''
      or concat_ws(
        ' ',
        l.acao,
        l.tabela,
        l.registro_id,
        l.descricao,
        p.nome,
        u.email,
        l.dados::text,
        l.dados_anteriores::text,
        l.dados_novos::text
      ) ilike '%' || p_busca || '%'
    )
  order by l.criado_em desc
  limit greatest(1, least(coalesce(p_limite, 200), 500))
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.listar_auditoria_admin(
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  integer,
  integer
) from public, anon;

grant execute on function public.listar_auditoria_admin(
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  integer,
  integer
) to authenticated;

commit;

notify pgrst, 'reload schema';

-- Teste opcional: deve retornar registros sem erro de tipo.
-- select * from public.listar_auditoria_admin(
--   now() - interval '30 days',
--   now(),
--   null,
--   null,
--   null,
--   10,
--   0
-- );



-- =====================================================================
-- SEÇÃO 30 — RC4.10
-- Origem histórica: supabase-rc4-10-backup-seguro.sql
-- =====================================================================

begin;

-- RC4.10 — backup seguro via RPC administrativa
-- Evita consultas diretas às tabelas protegidas por RLS.

create or replace function public.exportar_backup_admin(
  p_inicio date,
  p_fim date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_resultado jsonb;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis as p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if p_inicio is null or p_fim is null then
    raise exception 'Informe a data inicial e a data final.';
  end if;

  if p_fim < p_inicio then
    raise exception 'O período informado é inválido.';
  end if;

  select jsonb_build_object(
    'funcionarios',
      coalesce((
        select jsonb_agg(to_jsonb(f) order by f.nome)
        from public.funcionarios f
        where f.empresa_id = v_empresa
      ), '[]'::jsonb),

    'jornadas',
      coalesce((
        select jsonb_agg(to_jsonb(j) order by j.funcionario_id, j.dia_semana)
        from public.jornadas j
        where j.empresa_id = v_empresa
      ), '[]'::jsonb),

    'marcacoes',
      coalesce((
        select jsonb_agg(to_jsonb(m) order by m.registrado_em)
        from public.marcacoes m
        where m.empresa_id = v_empresa
          and m.data_local between p_inicio and p_fim
      ), '[]'::jsonb),

    'ocorrencias',
      coalesce((
        select jsonb_agg(to_jsonb(o) order by o.data_inicio)
        from public.ocorrencias o
        where o.empresa_id = v_empresa
          and o.data_inicio <= p_fim
          and o.data_fim >= p_inicio
      ), '[]'::jsonb),

    'ajustes',
      coalesce((
        select jsonb_agg(to_jsonb(sa) order by sa.criado_em)
        from public.solicitacoes_ajuste sa
        where sa.empresa_id = v_empresa
          and sa.data_marcacao between p_inicio and p_fim
      ), '[]'::jsonb),

    'auditoria',
      coalesce((
        select jsonb_agg(to_jsonb(la) order by la.criado_em)
        from public.logs_auditoria la
        where la.empresa_id = v_empresa
          and la.criado_em >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
          and la.criado_em < ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
      ), '[]'::jsonb)
  )
  into v_resultado;

  return v_resultado;
end;
$$;

revoke all on function public.exportar_backup_admin(date,date)
from public, anon;

grant execute on function public.exportar_backup_admin(date,date)
to authenticated;

commit;

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 31 — RC4.13
-- Origem histórica: supabase-rc4-13-regularizar-retorno.sql
-- =====================================================================

begin;

-- RC4.13 — regularização administrativa de saída temporária sem retorno

create or replace function public.regularizar_retorno_movimentacao_admin(
  p_id uuid,
  p_fim_em timestamptz,
  p_observacao text default null
)
returns public.movimentacoes_jornada
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_mov public.movimentacoes_jornada%rowtype;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  select mj.*
    into v_mov
  from public.movimentacoes_jornada mj
  where mj.id = p_id
    and mj.empresa_id = v_empresa
  for update;

  if v_mov.id is null then
    raise exception 'Movimentação não encontrada.';
  end if;

  if v_mov.status <> 'aberta' then
    raise exception 'Esta movimentação não está mais aguardando retorno.';
  end if;

  if p_fim_em is null then
    raise exception 'Informe o horário correto do retorno.';
  end if;

  if p_fim_em < v_mov.inicio_em then
    raise exception 'O retorno não pode ser anterior à saída.';
  end if;

  if p_fim_em > clock_timestamp() + interval '5 minutes' then
    raise exception 'O retorno não pode estar no futuro.';
  end if;

  update public.movimentacoes_jornada mj
     set fim_em = p_fim_em,
         status = 'encerrada',
         observacao_admin = nullif(btrim(p_observacao), ''),
         analisado_por = auth.uid(),
         analisado_em = clock_timestamp(),
         atualizado_em = clock_timestamp()
   where mj.id = p_id
  returning mj.* into v_mov;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, tabela, registro_id, acao,
    dados_novos, origem, descricao
  )
  values(
    v_empresa,
    auth.uid(),
    'movimentacoes_jornada',
    v_mov.id::text,
    'RETORNO_REGULARIZADO_ADMIN',
    to_jsonb(v_mov),
    'web',
    'Retorno temporário regularizado manualmente pelo administrador.'
  );

  return v_mov;
end;
$$;

create or replace function public.arquivar_movimentacao_admin(
  p_id uuid,
  p_motivo text
)
returns public.movimentacoes_jornada
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_mov public.movimentacoes_jornada%rowtype;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Informe o motivo do arquivamento.';
  end if;

  update public.movimentacoes_jornada mj
     set status = 'cancelada',
         aprovado = false,
         efeito_calculo = 'pendente',
         observacao_admin = btrim(p_motivo),
         analisado_por = auth.uid(),
         analisado_em = clock_timestamp(),
         atualizado_em = clock_timestamp()
   where mj.id = p_id
     and mj.empresa_id = v_empresa
     and mj.status = 'aberta'
  returning mj.* into v_mov;

  if v_mov.id is null then
    raise exception 'Movimentação não encontrada ou já regularizada.';
  end if;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, tabela, registro_id, acao,
    dados_novos, origem, descricao
  )
  values(
    v_empresa,
    auth.uid(),
    'movimentacoes_jornada',
    v_mov.id::text,
    'MOVIMENTACAO_ARQUIVADA_ADMIN',
    to_jsonb(v_mov),
    'web',
    'Movimentação temporária arquivada pelo administrador.'
  );

  return v_mov;
end;
$$;

revoke all on function public.regularizar_retorno_movimentacao_admin(uuid,timestamptz,text)
from public, anon;

grant execute on function public.regularizar_retorno_movimentacao_admin(uuid,timestamptz,text)
to authenticated;

revoke all on function public.arquivar_movimentacao_admin(uuid,text)
from public, anon;

grant execute on function public.arquivar_movimentacao_admin(uuid,text)
to authenticated;

commit;

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 32 — RC4.16
-- Origem histórica: supabase-rc4-16-multiplos-dispositivos.sql
-- =====================================================================

begin;

-- RC4.16 — múltiplos computadores autorizados
--
-- Permite manter simultaneamente, por exemplo:
-- • computador da loja;
-- • computador de homologação;
-- • equipamento de contingência.
--
-- Cada navegador continua possuindo um token próprio e pode ser revogado
-- individualmente, sem bloquear os demais.

alter table public.dispositivos_ponto
  add column if not exists tipo text not null default 'terminal';

alter table public.dispositivos_ponto
  drop constraint if exists dispositivos_ponto_tipo_check;

alter table public.dispositivos_ponto
  add constraint dispositivos_ponto_tipo_check
  check (tipo in ('terminal','homologacao','contingencia'));

create index if not exists idx_dispositivos_ponto_empresa_tipo_ativo
  on public.dispositivos_ponto(empresa_id,tipo,ativo);

create or replace function public.autorizar_dispositivo_ponto_multi_master_admin(
  p_token text,
  p_nome text,
  p_tipo text default 'terminal',
  p_user_agent text default null,
  p_master_pin text default null
)
returns table(
  id uuid,
  nome text,
  tipo text,
  ativo boolean,
  autorizado_em timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_id uuid;
  v_tipo text;
  v_ativos integer;
begin
  if not public.usuario_e_admin() then
    raise exception 'Apenas administradores podem autorizar dispositivos.';
  end if;

  v_empresa := public.empresa_do_usuario();

  if v_empresa is null then
    raise exception 'Empresa não identificada.';
  end if;

  perform public.validar_pin_mestre_interno(v_empresa,p_master_pin);

  if length(coalesce(p_token,'')) < 32 then
    raise exception 'Token de dispositivo inválido.';
  end if;

  v_tipo := lower(coalesce(nullif(trim(p_tipo),''),'terminal'));

  if v_tipo not in ('terminal','homologacao','contingencia') then
    raise exception 'Tipo de dispositivo inválido.';
  end if;

  select count(*)::integer
    into v_ativos
  from public.dispositivos_ponto d
  where d.empresa_id = v_empresa
    and d.ativo = true;

  if v_ativos >= 10 then
    raise exception 'Limite de 10 dispositivos ativos atingido.';
  end if;

  if exists(
    select 1
    from public.dispositivos_ponto d
    where d.token_hash = encode(digest(p_token,'sha256'),'hex')
      and d.ativo = true
  ) then
    raise exception 'Este navegador já está autorizado.';
  end if;

  insert into public.dispositivos_ponto(
    empresa_id,
    nome,
    tipo,
    token_hash,
    ativo,
    autorizado_por,
    user_agent_autorizacao
  )
  values(
    v_empresa,
    coalesce(nullif(trim(p_nome),''),'Computador autorizado'),
    v_tipo,
    encode(digest(p_token,'sha256'),'hex'),
    true,
    auth.uid(),
    left(p_user_agent,1000)
  )
  returning dispositivos_ponto.id into v_id;

  perform public.registrar_evento_auditoria(
    'AUTORIZAR',
    'dispositivos_ponto',
    v_id::text,
    'Novo computador autorizado sem revogar os demais',
    jsonb_build_object(
      'nome',coalesce(nullif(trim(p_nome),''),'Computador autorizado'),
      'tipo',v_tipo,
      'dispositivos_ativos_apos_autorizacao',v_ativos + 1
    ),
    'web'
  );

  return query
  select d.id,d.nome,d.tipo,d.ativo,d.autorizado_em
  from public.dispositivos_ponto d
  where d.id = v_id;
end;
$$;

create or replace function public.listar_dispositivos_ponto_multi_admin()
returns table(
  id uuid,
  nome text,
  tipo text,
  ativo boolean,
  autorizado_em timestamptz,
  ultimo_uso_em timestamptz,
  revogado_em timestamptz,
  observacao text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso negado.';
  end if;

  return query
  select
    d.id,
    d.nome,
    d.tipo,
    d.ativo,
    d.autorizado_em,
    d.ultimo_uso_em,
    d.revogado_em,
    d.observacao
  from public.dispositivos_ponto d
  where d.empresa_id = public.empresa_do_usuario()
  order by d.ativo desc,d.autorizado_em desc;
end;
$$;

create or replace function public.validar_dispositivo_ponto_detalhado(p_token text)
returns table(
  id uuid,
  autorizado boolean,
  nome text,
  tipo text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return query
  select d.id,true,d.nome,d.tipo
  from public.dispositivos_ponto d
  where d.token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex')
    and d.ativo = true
  limit 1;

  if not found then
    return query select null::uuid,false,null::text,null::text;
  end if;
end;
$$;

revoke all on function public.autorizar_dispositivo_ponto_multi_master_admin(
  text,text,text,text,text
) from public,anon;

grant execute on function public.autorizar_dispositivo_ponto_multi_master_admin(
  text,text,text,text,text
) to authenticated;

revoke all on function public.listar_dispositivos_ponto_multi_admin()
from public,anon;

grant execute on function public.listar_dispositivos_ponto_multi_admin()
to authenticated;

grant execute on function public.validar_dispositivo_ponto_detalhado(text)
to anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 33 — RC4.17
-- Origem histórica: supabase-rc4-17-foto-no-ponto.sql
-- =====================================================================

begin;

-- RC4.17 — foto do funcionário no terminal de ponto
--
-- O login por matrícula + PIN usa sessão própria e não uma sessão Auth do
-- Supabase. Por isso o navegador do terminal não conseguia gerar URL assinada
-- para uma foto armazenada em bucket privado.
--
-- A correção torna público somente o bucket "funcionarios".
-- Os demais buckets permanecem inalterados.

update storage.buckets
set public = true
where id = 'funcionarios';

commit;

-- Conferência:
select id, name, public
from storage.buckets
where id = 'funcionarios';



-- =====================================================================
-- SEÇÃO 34 — RC4.18
-- Origem histórica: supabase-rc4-18-intervalo-minimo-30-min.sql
-- =====================================================================

begin;

-- RC4.18 — intervalo mínimo obrigatório de 30 minutos
--
-- Regra:
-- depois de registrar "Início do almoço", o "Retorno do almoço"
-- só pode ser registrado após pelo menos 30 minutos.
--
-- A validação é feita no servidor e vale para todos os computadores.

update public.empresas
set intervalo_minimo_minutos = 30
where intervalo_minimo_minutos is distinct from 30;

alter table public.empresas
  alter column intervalo_minimo_minutos set default 30;

alter table public.empresas
  drop constraint if exists empresas_intervalo_check;

alter table public.empresas
  add constraint empresas_intervalo_check
  check (
    intervalo_minimo_minutos between 30 and intervalo_maximo_minutos
    and intervalo_maximo_minutos <= 360
  );

create or replace function public.salvar_politicas_ponto(
  p_tolerancia_entrada integer,
  p_tolerancia_saida integer,
  p_intervalo_minimo integer,
  p_intervalo_maximo integer,
  p_horas_extras_automaticas boolean,
  p_limite_banco_horas integer
)
returns public.empresas
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_result public.empresas%rowtype;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if p_tolerancia_entrada not between 0 and 120
     or p_tolerancia_saida not between 0 and 120 then
    raise exception 'As tolerâncias devem ficar entre 0 e 120 minutos.';
  end if;

  if p_intervalo_minimo < 30 then
    raise exception 'O intervalo mínimo de almoço não pode ser inferior a 30 minutos.';
  end if;

  if p_intervalo_maximo < p_intervalo_minimo
     or p_intervalo_maximo > 360 then
    raise exception 'Configuração de intervalo inválida.';
  end if;

  update public.empresas
     set tolerancia_entrada_minutos = p_tolerancia_entrada,
         tolerancia_saida_minutos = p_tolerancia_saida,
         intervalo_minimo_minutos = p_intervalo_minimo,
         intervalo_maximo_minutos = p_intervalo_maximo,
         horas_extras_automaticas = p_horas_extras_automaticas,
         limite_banco_horas_minutos = p_limite_banco_horas,
         atualizada_em = clock_timestamp()
   where id = v_empresa
  returning * into v_result;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    acao,
    tabela,
    registro_id,
    dados_novos
  )
  values(
    v_empresa,
    auth.uid(),
    'POLITICAS_PONTO_ATUALIZADAS',
    'empresas',
    v_empresa,
    jsonb_build_object(
      'tolerancia_entrada', p_tolerancia_entrada,
      'tolerancia_saida', p_tolerancia_saida,
      'intervalo_minimo', p_intervalo_minimo,
      'intervalo_maximo', p_intervalo_maximo,
      'horas_extras_automaticas', p_horas_extras_automaticas,
      'limite_banco_horas', p_limite_banco_horas
    )
  );

  return v_result;
end;
$$;

create or replace function public.registrar_ponto_com_pin(p_token text)
returns public.marcacoes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_agora timestamptz := clock_timestamp();
  v_data date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_ultima_marcacao timestamptz;
  v_inicio_intervalo timestamptz;
  v_intervalo_minimo integer := 30;
  v_restante integer;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  perform pg_advisory_xact_lock(
    hashtextextended(v_funcionario.id::text, 20260730)
  );

  select max(m.registrado_em)
    into v_ultima_marcacao
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  if v_ultima_marcacao is not null
     and v_agora - v_ultima_marcacao < interval '5 seconds' then
    raise exception 'Aguarde alguns segundos antes de registrar novamente.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  if v_tipo = 'fim_intervalo'::public.tipo_marcacao then
    select m.registrado_em
      into v_inicio_intervalo
    from public.marcacoes m
    where m.funcionario_id = v_funcionario.id
      and m.data_local = v_data
      and m.tipo = 'inicio_intervalo'::public.tipo_marcacao
    order by m.registrado_em desc
    limit 1;

    select greatest(30, coalesce(e.intervalo_minimo_minutos, 30))
      into v_intervalo_minimo
    from public.empresas e
    where e.id = v_funcionario.empresa_id;

    v_restante := ceil(
      extract(epoch from (
        v_inicio_intervalo
        + make_interval(mins => v_intervalo_minimo)
        - v_agora
      )) / 60.0
    )::integer;

    if v_inicio_intervalo is not null and v_restante > 0 then
      raise exception
        'O retorno do almoço só pode ser registrado após % minutos. Aguarde mais % minuto(s).',
        v_intervalo_minimo,
        v_restante;
    end if;
  end if;

  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values(
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'pin'
  )
  returning * into v_marcacao;

  return v_marcacao;
end;
$$;

create or replace function public.registrar_ponto_dispositivo(
  p_token text,
  p_dispositivo_token text,
  p_user_agent text default null
)
returns public.marcacoes
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_agora timestamptz := clock_timestamp();
  v_data date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_ultima_marcacao timestamptz;
  v_inicio_intervalo timestamptz;
  v_intervalo_minimo integer := 30;
  v_restante integer;
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash =
        encode(extensions.digest(coalesce(p_dispositivo_token, ''), 'sha256'), 'hex')
    and d.ativo = true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Registro bloqueado: computador não autorizado.';
  end if;

  v_funcionario := public.funcionario_por_token(p_token);

  if v_funcionario.empresa_id <> v_dispositivo.empresa_id then
    raise exception 'Dispositivo não autorizado para esta empresa.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_funcionario.id::text, 20260730)
  );

  select max(m.registrado_em)
    into v_ultima_marcacao
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  if v_ultima_marcacao is not null
     and v_agora - v_ultima_marcacao < interval '5 seconds' then
    raise exception 'Aguarde alguns segundos antes de registrar novamente.';
  end if;

  select count(*)::integer
    into v_quantidade
  from public.marcacoes m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_data;

  v_tipo := case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo is null then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  if v_tipo = 'fim_intervalo'::public.tipo_marcacao then
    select m.registrado_em
      into v_inicio_intervalo
    from public.marcacoes m
    where m.funcionario_id = v_funcionario.id
      and m.data_local = v_data
      and m.tipo = 'inicio_intervalo'::public.tipo_marcacao
    order by m.registrado_em desc
    limit 1;

    select greatest(30, coalesce(e.intervalo_minimo_minutos, 30))
      into v_intervalo_minimo
    from public.empresas e
    where e.id = v_funcionario.empresa_id;

    v_restante := ceil(
      extract(epoch from (
        v_inicio_intervalo
        + make_interval(mins => v_intervalo_minimo)
        - v_agora
      )) / 60.0
    )::integer;

    if v_inicio_intervalo is not null and v_restante > 0 then
      raise exception
        'O retorno do almoço só pode ser registrado após % minutos. Aguarde mais % minuto(s).',
        v_intervalo_minimo,
        v_restante;
    end if;
  end if;

  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values(
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'dispositivo'
  )
  returning * into v_marcacao;

  update public.dispositivos_ponto
     set ultimo_uso_em = v_agora
   where id = v_dispositivo.id;

  return v_marcacao;
end;
$$;

revoke all on function public.registrar_ponto_com_pin(text)
from public, anon, authenticated;

revoke all on function public.registrar_ponto_dispositivo(text,text,text)
from public;

grant execute on function public.registrar_ponto_dispositivo(text,text,text)
to anon, authenticated;

grant execute on function public.salvar_politicas_ponto(
  integer,integer,integer,integer,boolean,integer
) to authenticated;

commit;

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 35 — RC5.0
-- Origem histórica: supabase-rc5-0-contingencia-offline.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 36 — RC5.22
-- Origem histórica: supabase-rc5-22-importacao-automatica-contingencia.sql
-- =====================================================================

-- Plenitude Ponto RC5.22
-- Importação automática das marcações de contingência para a jornada oficial.
--
-- Execute este arquivo inteiro no SQL Editor do Supabase.

begin;

-- Garante que o vínculo com public.marcacoes usa o mesmo tipo do ID oficial.
do $$
declare
  v_type text;
begin
  select data_type
    into v_type
  from information_schema.columns
  where table_schema='public'
    and table_name='marcacoes_contingencia'
    and column_name='marcacao_oficial_id';

  if v_type='uuid' then
    alter table public.marcacoes_contingencia
      drop constraint if exists marcacoes_contingencia_marcacao_oficial_id_fkey;

    update public.marcacoes_contingencia
       set marcacao_oficial_id=null;

    alter table public.marcacoes_contingencia
      alter column marcacao_oficial_id type bigint
      using null::bigint;

    alter table public.marcacoes_contingencia
      add constraint marcacoes_contingencia_marcacao_oficial_id_fkey
      foreign key (marcacao_oficial_id)
      references public.marcacoes(id);
  end if;
end;
$$;

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
  v_mark public.marcacoes%rowtype;
  v_existing_mark public.marcacoes%rowtype;
  v_tipo public.tipo_marcacao;
  v_conflito text;
  v_data_oficial date;
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash=encode(
          digest(coalesce(p_dispositivo_token,''),'sha256'),
          'hex'
        )
    and d.ativo=true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Dispositivo não autorizado para sincronizar contingência.';
  end if;

  select f.*
    into v_funcionario
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

  v_data_oficial :=
    (p_ocorrido_em_dispositivo at time zone 'America/Sao_Paulo')::date;

  if p_ocorrido_em_dispositivo > clock_timestamp()+interval '10 minutes' then
    v_conflito:='Horário do dispositivo está no futuro.';
  elsif abs(
    extract(
      epoch from (clock_timestamp()-p_ocorrido_em_dispositivo)
    )
  ) > 86400*7 then
    v_conflito:='Horário do dispositivo difere mais de 7 dias do servidor.';
  end if;

  -- Idempotência: o mesmo evento offline nunca é importado duas vezes.
  select c.*
    into v_result
  from public.marcacoes_contingencia c
  where c.dispositivo_id=v_dispositivo.id
    and c.evento_offline_id=p_evento_offline_id
  limit 1;

  if v_result.id is not null then
    update public.marcacoes_contingencia
       set sincronizado_em=clock_timestamp(),
           atualizado_em=clock_timestamp()
     where id=v_result.id
     returning * into v_result;

    return v_result;
  end if;

  -- Detecta marcação oficial equivalente já existente.
  select m.*
    into v_existing_mark
  from public.marcacoes m
  where m.funcionario_id=p_funcionario_id
    and m.data_local=v_data_oficial
    and m.tipo=v_tipo
  order by m.registrado_em
  limit 1;

  if v_existing_mark.id is not null then
    insert into public.marcacoes_contingencia(
      empresa_id,
      funcionario_id,
      dispositivo_id,
      evento_offline_id,
      tipo,
      ocorrido_em_dispositivo,
      data_local,
      fuso_horario,
      offset_minutos,
      criado_local_em,
      sincronizado_em,
      status,
      conflito,
      hash_evento,
      hash_anterior,
      user_agent,
      marcacao_oficial_id,
      observacao_admin,
      aprovado_em
    )
    values(
      v_dispositivo.empresa_id,
      p_funcionario_id,
      v_dispositivo.id,
      p_evento_offline_id,
      v_tipo,
      p_ocorrido_em_dispositivo,
      v_data_oficial,
      left(p_fuso_horario,80),
      p_offset_minutos,
      p_criado_local_em,
      clock_timestamp(),
      'duplicado',
      'Já existe marcação oficial do mesmo tipo nesta data.',
      p_hash_evento,
      p_hash_anterior,
      left(p_user_agent,1000),
      v_existing_mark.id,
      'Duplicidade detectada automaticamente na sincronização.',
      clock_timestamp()
    )
    returning * into v_result;

    return v_result;
  end if;

  -- Horários suspeitos continuam pendentes para análise administrativa.
  if v_conflito is not null then
    insert into public.marcacoes_contingencia(
      empresa_id,
      funcionario_id,
      dispositivo_id,
      evento_offline_id,
      tipo,
      ocorrido_em_dispositivo,
      data_local,
      fuso_horario,
      offset_minutos,
      criado_local_em,
      sincronizado_em,
      status,
      conflito,
      hash_evento,
      hash_anterior,
      user_agent
    )
    values(
      v_dispositivo.empresa_id,
      p_funcionario_id,
      v_dispositivo.id,
      p_evento_offline_id,
      v_tipo,
      p_ocorrido_em_dispositivo,
      v_data_oficial,
      left(p_fuso_horario,80),
      p_offset_minutos,
      p_criado_local_em,
      clock_timestamp(),
      'conflitante',
      v_conflito,
      p_hash_evento,
      p_hash_anterior,
      left(p_user_agent,1000)
    )
    returning * into v_result;

    return v_result;
  end if;

  -- Importa imediatamente para a jornada oficial.
  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values(
    v_dispositivo.empresa_id,
    p_funcionario_id,
    v_tipo,
    p_ocorrido_em_dispositivo,
    v_data_oficial,
    'contingencia'
  )
  returning * into v_mark;

  insert into public.marcacoes_contingencia(
    empresa_id,
    funcionario_id,
    dispositivo_id,
    evento_offline_id,
    tipo,
    ocorrido_em_dispositivo,
    data_local,
    fuso_horario,
    offset_minutos,
    criado_local_em,
    sincronizado_em,
    status,
    hash_evento,
    hash_anterior,
    user_agent,
    marcacao_oficial_id,
    observacao_admin,
    aprovado_em
  )
  values(
    v_dispositivo.empresa_id,
    p_funcionario_id,
    v_dispositivo.id,
    p_evento_offline_id,
    v_tipo,
    p_ocorrido_em_dispositivo,
    v_data_oficial,
    left(p_fuso_horario,80),
    p_offset_minutos,
    p_criado_local_em,
    clock_timestamp(),
    'aprovado',
    p_hash_evento,
    p_hash_anterior,
    left(p_user_agent,1000),
    v_mark.id,
    'Importação automática da contingência.',
    clock_timestamp()
  )
  returning * into v_result;

  update public.dispositivos_ponto
     set ultimo_uso_em=clock_timestamp()
   where id=v_dispositivo.id;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    tabela,
    registro_id,
    acao,
    dados_novos,
    origem,
    descricao
  )
  values(
    v_dispositivo.empresa_id,
    null,
    'marcacoes_contingencia',
    v_result.id::text,
    'CONTINGENCIA_IMPORTADA_AUTOMATICAMENTE',
    to_jsonb(v_result),
    'contingencia',
    'Marcação offline importada automaticamente para a jornada oficial.'
  );

  return v_result;
end;
$$;

revoke all on function public.sincronizar_marcacao_contingencia(
  text,uuid,uuid,text,timestamptz,date,text,integer,timestamptz,text,text,text
) from public,anon;

grant execute on function public.sincronizar_marcacao_contingencia(
  text,uuid,uuid,text,timestamptz,date,text,integer,timestamptz,text,text,text
) to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 37 — RC5.24
-- Origem histórica: supabase-rc5-24-permissao-sincronizacao-anon.sql
-- =====================================================================

-- Plenitude Ponto RC5.24
-- Corrige a autorização da sincronização de contingência.
--
-- Causa:
-- O funcionário usa sessão própria por matrícula/PIN e não uma sessão
-- Supabase Auth. Por isso as RPCs da tela do ponto são executadas pelo papel
-- `anon`. A RC5.22 havia concedido execução somente a `authenticated`,
-- provocando erro HTTP 401.
--
-- A função permanece SECURITY DEFINER e valida internamente:
-- - token do computador autorizado;
-- - empresa do dispositivo;
-- - funcionário ativo da mesma empresa;
-- - evento e tipo da marcação.

begin;

revoke all on function public.sincronizar_marcacao_contingencia(
  text,
  uuid,
  uuid,
  text,
  timestamptz,
  date,
  text,
  integer,
  timestamptz,
  text,
  text,
  text
) from public;

grant execute on function public.sincronizar_marcacao_contingencia(
  text,
  uuid,
  uuid,
  text,
  timestamptz,
  date,
  text,
  integer,
  timestamptz,
  text,
  text,
  text
) to anon, authenticated;

commit;

notify pgrst, 'reload schema';



-- =====================================================================
-- SEÇÃO 38 — RC5.25
-- Origem histórica: supabase-rc5-25-pendencia-jornada-incompleta.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 39 — RC5.26B
-- Origem histórica: supabase-rc5-26b-corrige-pendencia-funcionario.sql
-- =====================================================================

-- Plenitude Ponto RC5.26B
-- Corrige a consulta das pendências de jornada no ponto do funcionário.

begin;

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
set search_path=public,extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  perform public.atualizar_pendencias_jornada_empresa(
    v_funcionario.empresa_id,
    v_funcionario.id
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
  where pj.empresa_id=v_funcionario.empresa_id
    and pj.funcionario_id=v_funcionario.id
    and pj.status='pendente'
  order by pj.data_local,pj.detectada_em;
end;
$$;

revoke all on function public.listar_minhas_pendencias_jornada(text)
  from public;

grant execute on function public.listar_minhas_pendencias_jornada(text)
  to anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 40 — RC5.30
-- Origem histórica: supabase-rc5-30-assistente-fechamento-mensal.sql
-- =====================================================================

-- Plenitude Ponto RC5.30
-- Auditoria obrigatória e bloqueio inteligente do fechamento mensal.

begin;

create or replace function public.auditar_competencia_admin(
  p_ano integer,
  p_mes integer
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_inicio date;
  v_fim date;
  v_jornadas integer:=0;
  v_ajustes integer:=0;
  v_contingencias integer:=0;
  v_movimentacoes integer:=0;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if p_ano not between 2020 and 2100 or p_mes not between 1 and 12 then
    raise exception 'Competência inválida.';
  end if;

  v_empresa:=public.empresa_do_usuario();
  v_inicio:=make_date(p_ano,p_mes,1);
  v_fim:=(v_inicio+interval '1 month - 1 day')::date;

  -- Jornadas incompletas: qualquer dia da competência com 1 a 3 marcações.
  select count(*)
    into v_jornadas
  from (
    select m.funcionario_id,m.data_local
    from public.marcacoes m
    join public.funcionarios f on f.id=m.funcionario_id
    where f.empresa_id=v_empresa
      and m.data_local between v_inicio and v_fim
      and m.data_local<current_date
    group by m.funcionario_id,m.data_local
    having count(*) between 1 and 3
  ) jornadas;

  if to_regclass('public.solicitacoes_ajuste') is not null then
    execute
      'select count(*) from public.solicitacoes_ajuste
       where empresa_id=$1
         and data_marcacao between $2 and $3
         and status=''pendente'''
    into v_ajustes
    using v_empresa,v_inicio,v_fim;
  end if;

  if to_regclass('public.marcacoes_contingencia') is not null then
    execute
      'select count(*) from public.marcacoes_contingencia
       where empresa_id=$1
         and data_local between $2 and $3
         and status in (''pendente'',''conflitante'')'
    into v_contingencias
    using v_empresa,v_inicio,v_fim;
  end if;

  if to_regclass('public.movimentacoes_jornada') is not null then
    execute
      'select count(*) from public.movimentacoes_jornada
       where empresa_id=$1
         and data_local between $2 and $3
         and (status=''aberta'' or fim_em is null)'
    into v_movimentacoes
    using v_empresa,v_inicio,v_fim;
  end if;

  return jsonb_build_object(
    'ano',p_ano,
    'mes',p_mes,
    'inicio',v_inicio,
    'fim',v_fim,
    'jornadas_incompletas',coalesce(v_jornadas,0),
    'ajustes_pendentes',coalesce(v_ajustes,0),
    'contingencias_pendentes',coalesce(v_contingencias,0),
    'movimentacoes_abertas',coalesce(v_movimentacoes,0),
    'total_bloqueios',
      coalesce(v_jornadas,0)+
      coalesce(v_ajustes,0)+
      coalesce(v_contingencias,0)+
      coalesce(v_movimentacoes,0),
    'pronta',
      (
       coalesce(v_jornadas,0)+
       coalesce(v_ajustes,0)+
       coalesce(v_contingencias,0)+
       coalesce(v_movimentacoes,0)
      )=0,
    'auditada_em',clock_timestamp()
  );
end;
$$;

-- Defesa no servidor: não depende apenas do botão do navegador.
create or replace function public.fechar_competencia_master_admin(
  p_ano integer,
  p_mes integer,
  p_observacao text default null,
  p_master_pin text default null
)
returns public.fechamentos_mensais
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result public.fechamentos_mensais%rowtype;
  v_audit jsonb;
  v_total integer;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso negado.';
  end if;

  perform public.validar_pin_mestre_interno(
    public.empresa_do_usuario(),
    p_master_pin
  );

  v_audit:=public.auditar_competencia_admin(p_ano,p_mes);
  v_total:=coalesce((v_audit->>'total_bloqueios')::integer,0);

  if v_total>0 then
    raise exception
      'Fechamento bloqueado: existem % pendências na competência. Jornadas incompletas: %, ajustes: %, contingências: %, saídas temporárias: %.',
      v_total,
      v_audit->>'jornadas_incompletas',
      v_audit->>'ajustes_pendentes',
      v_audit->>'contingencias_pendentes',
      v_audit->>'movimentacoes_abertas';
  end if;

  v_result:=public.fechar_competencia_admin(
    p_ano,
    p_mes,
    p_observacao
  );

  return v_result;
end;
$$;

revoke all on function public.auditar_competencia_admin(integer,integer)
  from public,anon;

grant execute on function public.auditar_competencia_admin(integer,integer)
  to authenticated;

revoke all on function public.fechar_competencia_master_admin(
  integer,integer,text,text
) from public,anon;

grant execute on function public.fechar_competencia_master_admin(
  integer,integer,text,text
) to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 41 — RC5.32
-- Origem histórica: supabase-rc5-32-corrige-analise-contingencia.sql
-- =====================================================================

-- Plenitude Ponto RC5.32
-- Restaura e compatibiliza a análise administrativa de contingências.

begin;

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
  if not public.usuario_e_admin() then
    raise exception 'Acesso negado.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  select *
    into v_c
  from public.marcacoes_contingencia
  where id=p_id
    and empresa_id=v_empresa
  for update;

  if v_c.id is null then
    raise exception 'Registro não encontrado.';
  end if;

  if v_c.status not in ('pendente','conflitante') then
    raise exception 'Registro já analisado.';
  end if;

  if p_acao='aprovar' then
    v_horario:=coalesce(
      p_horario_corrigido,
      v_c.ocorrido_em_dispositivo
    );

    if exists(
      select 1
      from public.marcacoes m
      where m.funcionario_id=v_c.funcionario_id
        and m.data_local=(v_horario at time zone 'America/Sao_Paulo')::date
        and m.tipo=v_c.tipo
    ) then
      update public.marcacoes_contingencia
         set status='duplicado',
             observacao_admin=coalesce(
               nullif(trim(p_observacao),''),
               'Duplicidade detectada na aprovação.'
             ),
             aprovado_por=auth.uid(),
             aprovado_em=clock_timestamp(),
             atualizado_em=clock_timestamp()
       where id=p_id
       returning * into v_c;

      return v_c;
    end if;

    insert into public.marcacoes(
      empresa_id,
      funcionario_id,
      tipo,
      registrado_em,
      data_local,
      origem
    )
    values(
      v_c.empresa_id,
      v_c.funcionario_id,
      v_c.tipo,
      v_horario,
      (v_horario at time zone 'America/Sao_Paulo')::date,
      'contingencia'
    )
    returning * into v_mark;

    update public.marcacoes_contingencia
       set status='aprovado',
           marcacao_oficial_id=v_mark.id,
           observacao_admin=nullif(trim(p_observacao),''),
           aprovado_por=auth.uid(),
           aprovado_em=clock_timestamp(),
           atualizado_em=clock_timestamp()
     where id=p_id
     returning * into v_c;

  elsif p_acao='rejeitar' then
    if length(trim(coalesce(p_observacao,'')))<5 then
      raise exception 'Informe o motivo da rejeição.';
    end if;

    update public.marcacoes_contingencia
       set status='rejeitado',
           observacao_admin=trim(p_observacao),
           aprovado_por=auth.uid(),
           aprovado_em=clock_timestamp(),
           atualizado_em=clock_timestamp()
     where id=p_id
     returning * into v_c;
  else
    raise exception 'Ação inválida.';
  end if;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    tabela,
    registro_id,
    acao,
    dados_novos,
    origem,
    descricao
  )
  values(
    v_empresa,
    auth.uid(),
    'marcacoes_contingencia',
    v_c.id::text,
    case
      when p_acao='aprovar' then 'CONTINGENCIA_APROVADA'
      else 'CONTINGENCIA_REJEITADA'
    end,
    to_jsonb(v_c),
    'web',
    'Registro offline analisado pelo administrador.'
  );

  return v_c;
end;
$$;

revoke all on function public.analisar_contingencia_admin(
  uuid,text,text,timestamptz
) from public,anon;

grant execute on function public.analisar_contingencia_admin(
  uuid,text,text,timestamptz
) to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 42 — RC5.33
-- Origem histórica: supabase-rc5-33-rpc-contingencia-v2.sql
-- =====================================================================

-- Plenitude Ponto RC5.33
-- Cria uma RPC nova e limpa para análise de contingência.
-- A nova função usa p_horario_corrigido como text para eliminar
-- incompatibilidades de resolução no cache do PostgREST.

begin;

drop function if exists public.analisar_contingencia_admin_v2(
  uuid,text,text,text
);

create function public.analisar_contingencia_admin_v2(
  p_id uuid,
  p_acao text,
  p_observacao text default null,
  p_horario_corrigido text default null
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
  if not public.usuario_e_admin() then
    raise exception 'Acesso negado.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  select *
    into v_c
  from public.marcacoes_contingencia
  where id=p_id
    and empresa_id=v_empresa
  for update;

  if v_c.id is null then
    raise exception 'Registro não encontrado.';
  end if;

  if v_c.status not in ('pendente','conflitante') then
    raise exception 'Registro já analisado.';
  end if;

  if p_acao='aprovar' then
    v_horario:=coalesce(
      nullif(trim(p_horario_corrigido),'')::timestamptz,
      v_c.ocorrido_em_dispositivo
    );

    if exists(
      select 1
      from public.marcacoes m
      where m.funcionario_id=v_c.funcionario_id
        and m.data_local=(v_horario at time zone 'America/Sao_Paulo')::date
        and m.tipo=v_c.tipo
    ) then
      update public.marcacoes_contingencia
         set status='duplicado',
             observacao_admin=coalesce(
               nullif(trim(p_observacao),''),
               'Duplicidade detectada na aprovação.'
             ),
             aprovado_por=auth.uid(),
             aprovado_em=clock_timestamp(),
             atualizado_em=clock_timestamp()
       where id=p_id
       returning * into v_c;

      return v_c;
    end if;

    insert into public.marcacoes(
      empresa_id,
      funcionario_id,
      tipo,
      registrado_em,
      data_local,
      origem
    )
    values(
      v_c.empresa_id,
      v_c.funcionario_id,
      v_c.tipo,
      v_horario,
      (v_horario at time zone 'America/Sao_Paulo')::date,
      'contingencia'
    )
    returning * into v_mark;

    update public.marcacoes_contingencia
       set status='aprovado',
           marcacao_oficial_id=v_mark.id,
           observacao_admin=nullif(trim(p_observacao),''),
           aprovado_por=auth.uid(),
           aprovado_em=clock_timestamp(),
           atualizado_em=clock_timestamp()
     where id=p_id
     returning * into v_c;

  elsif p_acao='rejeitar' then
    if length(trim(coalesce(p_observacao,'')))<5 then
      raise exception 'Informe o motivo da rejeição.';
    end if;

    update public.marcacoes_contingencia
       set status='rejeitado',
           observacao_admin=trim(p_observacao),
           aprovado_por=auth.uid(),
           aprovado_em=clock_timestamp(),
           atualizado_em=clock_timestamp()
     where id=p_id
     returning * into v_c;
  else
    raise exception 'Ação inválida.';
  end if;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    tabela,
    registro_id,
    acao,
    dados_novos,
    origem,
    descricao
  )
  values(
    v_empresa,
    auth.uid(),
    'marcacoes_contingencia',
    v_c.id::text,
    case
      when p_acao='aprovar' then 'CONTINGENCIA_APROVADA'
      else 'CONTINGENCIA_REJEITADA'
    end,
    to_jsonb(v_c),
    'web',
    'Registro offline analisado pelo administrador.'
  );

  return v_c;
end;
$$;

revoke all on function public.analisar_contingencia_admin_v2(
  uuid,text,text,text
) from public,anon;

grant execute on function public.analisar_contingencia_admin_v2(
  uuid,text,text,text
) to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 43 — RC5.39
-- Origem histórica: supabase-rc5-39-controle-espelhos-assinados.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 44 — RC5.40
-- Origem histórica: supabase-rc5-40-corrige-ambiguidade-espelhos.sql
-- =====================================================================

-- Plenitude Ponto RC5.40
-- Corrige a ambiguidade de funcionario_id na listagem dos espelhos mensais.

begin;

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
#variable_conflict use_column
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
    raise exception
      'A competência precisa estar fechada para controlar os espelhos.';
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
  on conflict on constraint
    espelhos_mensais_empresa_id_funcionario_id_ano_mes_key
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

-- Também deixa a atualização protegida contra a mesma classe de conflito.
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
#variable_conflict use_column
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
  on conflict on constraint
    espelhos_mensais_empresa_id_funcionario_id_ano_mes_key
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

revoke all on function public.listar_espelhos_competencia_admin(
  integer,integer
) from public,anon;

grant execute on function public.listar_espelhos_competencia_admin(
  integer,integer
) to authenticated;

revoke all on function public.atualizar_status_espelho_admin(
  uuid,integer,integer,text,date,text
) from public,anon;

grant execute on function public.atualizar_status_espelho_admin(
  uuid,integer,integer,text,date,text
) to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 45 — RC5.43
-- Origem histórica: supabase-rc5-43-calendario-feriados.sql
-- =====================================================================

-- Plenitude Ponto RC5.43
-- Calendário de feriados nacionais, estaduais, municipais e internos.

begin;

create table if not exists public.feriados_empresa (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  data date not null,
  nome text not null,
  abrangencia text not null default 'empresa'
    check (abrangencia in ('nacional','estadual','municipal','empresa','facultativo')),
  regra_trabalho text not null default 'banco_simples'
    check (regra_trabalho in ('banco_simples','banco_dobro','folha','normal')),
  reduz_carga boolean not null default true,
  ativo boolean not null default true,
  observacao text,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default clock_timestamp(),
  atualizado_em timestamptz not null default clock_timestamp(),
  unique (empresa_id,data)
);

create index if not exists idx_feriados_empresa_data
  on public.feriados_empresa(empresa_id,data);

alter table public.feriados_empresa enable row level security;

drop policy if exists feriados_empresa_select_admin on public.feriados_empresa;
create policy feriados_empresa_select_admin
on public.feriados_empresa
for select
to authenticated
using (
  empresa_id=public.empresa_do_usuario()
  and public.usuario_e_admin()
);

create or replace function public.listar_feriados_empresa_admin(
  p_inicio date,
  p_fim date
)
returns setof public.feriados_empresa
language sql
security definer
set search_path=public
as $$
  select fe.*
  from public.feriados_empresa fe
  where public.usuario_e_admin()
    and fe.empresa_id=public.empresa_do_usuario()
    and fe.data between p_inicio and p_fim
  order by fe.data,fe.nome;
$$;

create or replace function public.salvar_feriado_empresa_admin(
  p_id uuid,
  p_data date,
  p_nome text,
  p_abrangencia text,
  p_regra_trabalho text,
  p_reduz_carga boolean,
  p_ativo boolean,
  p_observacao text default null
)
returns public.feriados_empresa
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_result public.feriados_empresa%rowtype;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  if p_data is null or length(trim(coalesce(p_nome,'')))<2 then
    raise exception 'Informe a data e o nome do feriado.';
  end if;

  if p_abrangencia not in ('nacional','estadual','municipal','empresa','facultativo') then
    raise exception 'Abrangência inválida.';
  end if;

  if p_regra_trabalho not in ('banco_simples','banco_dobro','folha','normal') then
    raise exception 'Regra de trabalho inválida.';
  end if;

  if p_id is null then
    insert into public.feriados_empresa(
      empresa_id,data,nome,abrangencia,regra_trabalho,
      reduz_carga,ativo,observacao,criado_por
    )
    values(
      v_empresa,p_data,trim(p_nome),p_abrangencia,p_regra_trabalho,
      coalesce(p_reduz_carga,true),coalesce(p_ativo,true),
      nullif(trim(coalesce(p_observacao,'')),''),auth.uid()
    )
    on conflict (empresa_id,data)
    do update set
      nome=excluded.nome,
      abrangencia=excluded.abrangencia,
      regra_trabalho=excluded.regra_trabalho,
      reduz_carga=excluded.reduz_carga,
      ativo=excluded.ativo,
      observacao=excluded.observacao,
      atualizado_em=clock_timestamp()
    returning * into v_result;
  else
    update public.feriados_empresa fe
       set data=p_data,
           nome=trim(p_nome),
           abrangencia=p_abrangencia,
           regra_trabalho=p_regra_trabalho,
           reduz_carga=coalesce(p_reduz_carga,true),
           ativo=coalesce(p_ativo,true),
           observacao=nullif(trim(coalesce(p_observacao,'')),''),
           atualizado_em=clock_timestamp()
     where fe.id=p_id
       and fe.empresa_id=v_empresa
     returning * into v_result;
  end if;

  if v_result.id is null then
    raise exception 'Feriado não encontrado.';
  end if;

  return v_result;
end;
$$;

create or replace function public.excluir_feriado_empresa_admin(
  p_id uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  delete from public.feriados_empresa fe
  where fe.id=p_id
    and fe.empresa_id=public.empresa_do_usuario();
end;
$$;

create or replace function public.gerar_feriados_padrao_serra_admin(
  p_ano integer
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_inseridos integer:=0;
  v_row record;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if p_ano not between 2020 and 2100 then
    raise exception 'Ano inválido.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  for v_row in
    select *
    from (
      values
        (make_date(p_ano,1,1),'Confraternização Universal','nacional','banco_simples',true,true),
        (make_date(p_ano,4,3),'Paixão de Cristo','nacional','banco_simples',true,true),
        (make_date(p_ano,4,13),'Nossa Senhora da Penha','estadual','banco_simples',true,true),
        (make_date(p_ano,4,21),'Tiradentes','nacional','banco_simples',true,true),
        (make_date(p_ano,5,1),'Dia do Trabalho','nacional','banco_simples',true,true),
        (make_date(p_ano,6,29),'São Pedro','municipal','banco_simples',true,true),
        (make_date(p_ano,9,7),'Independência do Brasil','nacional','banco_simples',true,true),
        (make_date(p_ano,10,12),'Nossa Senhora Aparecida','nacional','banco_simples',true,true),
        (make_date(p_ano,11,2),'Finados','nacional','banco_simples',true,true),
        (make_date(p_ano,11,15),'Proclamação da República','nacional','banco_simples',true,true),
        (make_date(p_ano,11,20),'Consciência Negra','nacional','banco_simples',true,true),
        (make_date(p_ano,12,8),'Nossa Senhora da Conceição','municipal','banco_simples',true,true),
        (make_date(p_ano,12,25),'Natal','nacional','banco_simples',true,true),
        (make_date(p_ano,12,26),'Dia do Serrano','municipal','banco_simples',true,true),
        (make_date(p_ano,2,16),'Carnaval — segunda-feira','facultativo','normal',false,false),
        (make_date(p_ano,2,17),'Carnaval — terça-feira','facultativo','normal',false,false),
        (make_date(p_ano,2,18),'Quarta-feira de Cinzas','facultativo','normal',false,false),
        (make_date(p_ano,6,4),'Corpus Christi','facultativo','normal',false,false),
        (make_date(p_ano,12,24),'Véspera de Natal','facultativo','normal',false,false),
        (make_date(p_ano,12,31),'Véspera de Ano-Novo','facultativo','normal',false,false)
    ) as x(data,nome,abrangencia,regra,reduz,ativo)
  loop
    insert into public.feriados_empresa(
      empresa_id,data,nome,abrangencia,regra_trabalho,
      reduz_carga,ativo,observacao,criado_por
    )
    values(
      v_empresa,v_row.data,v_row.nome,v_row.abrangencia,v_row.regra,
      v_row.reduz,v_row.ativo,
      'Calendário padrão Serra/ES. Confirme a aplicabilidade à empresa.',
      auth.uid()
    )
    on conflict (empresa_id,data) do nothing;

    if found then
      v_inseridos:=v_inseridos+1;
    end if;
  end loop;

  return jsonb_build_object(
    'ano',p_ano,
    'inseridos',v_inseridos
  );
end;
$$;

-- Banco de horas atualizado para consultar o calendário da empresa.
create or replace function public._calcular_banco_horas_json(
  p_funcionario_id uuid,
  p_inicio date,
  p_fim date
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_dias jsonb := '[]'::jsonb;
  v_resumo jsonb;
  v_dia record;
  v_previsto integer;
  v_trabalhado integer;
  v_saldo integer;
  v_count integer;
  v_tipos public.tipo_marcacao[];
  v_horarios timestamptz[];
  v_ocorrencia text;
  v_status text;
  v_feriado public.feriados_empresa%rowtype;
  v_total_previsto integer := 0;
  v_total_trabalhado integer := 0;
  v_total_saldo integer := 0;
  v_total_positivo integer := 0;
  v_total_negativo integer := 0;
  v_dias_trabalhados integer := 0;
  v_faltas integer := 0;
  v_pendencias integer := 0;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Período inválido.';
  end if;

  select * into v_funcionario
  from public.funcionarios
  where id = p_funcionario_id;

  if v_funcionario.id is null then
    raise exception 'Funcionário não encontrado.';
  end if;

  for v_dia in
    select gs::date as data
    from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs
    order by gs
  loop
    select
      case
        when j.id is null or j.ativo is false or j.entrada is null then 0
        else round(extract(epoch from (
          (j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)
        ))/60)::integer
      end
    into v_previsto
    from (select 1) x
    left join public.jornadas j
      on j.funcionario_id=p_funcionario_id
     and j.dia_semana=extract(isodow from v_dia.data)::smallint
    limit 1;

    v_feriado:=null;

    select fe.*
      into v_feriado
    from public.feriados_empresa fe
    where fe.empresa_id=v_funcionario.empresa_id
      and fe.data=v_dia.data
      and fe.ativo=true
    limit 1;

    select o.tipo::text
      into v_ocorrencia
    from public.ocorrencias o
    where o.funcionario_id=p_funcionario_id
      and o.aprovado=true
      and v_dia.data between o.data_inicio and o.data_fim
    order by o.criado_em desc
    limit 1;

    if v_feriado.id is not null and v_feriado.reduz_carga then
      v_previsto:=0;
    end if;

    if v_ocorrencia in ('folga','ferias','atestado') then
      v_previsto:=0;
    end if;

    select
      count(*)::integer,
      array_agg(m.tipo order by m.registrado_em),
      array_agg(m.registrado_em order by m.registrado_em)
    into v_count,v_tipos,v_horarios
    from public.marcacoes m
    where m.funcionario_id=p_funcionario_id
      and m.data_local=v_dia.data;

    v_trabalhado:=0;
    v_saldo:=null;

    if v_count>=2 then
      v_trabalhado:=v_trabalhado+
        greatest(0,round(extract(epoch from (v_horarios[2]-v_horarios[1]))/60)::integer);
    end if;

    if v_count>=4 then
      v_trabalhado:=v_trabalhado+
        greatest(0,round(extract(epoch from (v_horarios[4]-v_horarios[3]))/60)::integer);
    end if;

    if v_feriado.id is not null then
      if v_count=4 then
        case v_feriado.regra_trabalho
          when 'banco_dobro' then
            v_saldo:=v_trabalhado*2;
            v_status:='feriado_banco_dobro';
          when 'folha' then
            v_saldo:=0;
            v_status:='feriado_folha';
          when 'normal' then
            v_saldo:=v_trabalhado-v_previsto;
            v_status:='completo';
          else
            v_saldo:=v_trabalhado;
            v_status:='feriado_trabalhado';
        end case;
        v_dias_trabalhados:=v_dias_trabalhados+1;
      elsif v_count between 1 and 3 then
        v_status:='pendente';
        v_pendencias:=v_pendencias+1;
      else
        v_saldo:=0;
        v_status:='feriado';
      end if;
    elsif v_ocorrencia in ('folga','ferias','atestado') then
      v_status:=v_ocorrencia;
      v_saldo:=case when v_count=4 then v_trabalhado else 0 end;
    elsif v_previsto=0 then
      v_status:=case when v_count>0 then 'extra' else 'sem_jornada' end;
      v_saldo:=case when v_count=4 then v_trabalhado else 0 end;
    elsif v_count=4 then
      v_status:='completo';
      v_saldo:=v_trabalhado-v_previsto;
      v_dias_trabalhados:=v_dias_trabalhados+1;
    elsif v_dia.data<(clock_timestamp() at time zone 'America/Sao_Paulo')::date
      and v_count=0 then
      v_status:='falta';
      v_saldo:=-v_previsto;
      v_faltas:=v_faltas+1;
    elsif v_dia.data<=(clock_timestamp() at time zone 'America/Sao_Paulo')::date
      and v_count between 1 and 3 then
      v_status:='pendente';
      v_pendencias:=v_pendencias+1;
    elsif v_dia.data=(clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      v_status:='aguardando';
    else
      v_status:='futuro';
    end if;

    if v_dia.data<=(clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      v_total_previsto:=v_total_previsto+v_previsto;
      v_total_trabalhado:=v_total_trabalhado+v_trabalhado;

      if v_saldo is not null then
        v_total_saldo:=v_total_saldo+v_saldo;

        if v_saldo>0 then
          v_total_positivo:=v_total_positivo+v_saldo;
        elsif v_saldo<0 then
          v_total_negativo:=v_total_negativo+abs(v_saldo);
        end if;
      end if;
    end if;

    v_dias:=v_dias||jsonb_build_array(jsonb_build_object(
      'data',v_dia.data,
      'dia_semana',extract(isodow from v_dia.data)::integer,
      'previsto_minutos',v_previsto,
      'trabalhado_minutos',v_trabalhado,
      'saldo_minutos',v_saldo,
      'quantidade_marcacoes',v_count,
      'status',v_status,
      'ocorrencia',v_ocorrencia,
      'feriado',case when v_feriado.id is null then null else
        jsonb_build_object(
          'id',v_feriado.id,
          'nome',v_feriado.nome,
          'abrangencia',v_feriado.abrangencia,
          'regra_trabalho',v_feriado.regra_trabalho,
          'reduz_carga',v_feriado.reduz_carga
        )
      end,
      'marcacoes',coalesce(to_jsonb(v_horarios),'[]'::jsonb),
      'tipos',coalesce(to_jsonb(v_tipos),'[]'::jsonb)
    ));
  end loop;

  v_resumo:=jsonb_build_object(
    'funcionario_id',v_funcionario.id,
    'funcionario_nome',v_funcionario.nome,
    'matricula',v_funcionario.matricula,
    'inicio',p_inicio,
    'fim',p_fim,
    'previsto_minutos',v_total_previsto,
    'trabalhado_minutos',v_total_trabalhado,
    'saldo_minutos',v_total_saldo,
    'credito_minutos',v_total_positivo,
    'debito_minutos',v_total_negativo,
    'dias_trabalhados',v_dias_trabalhados,
    'faltas',v_faltas,
    'pendencias',v_pendencias
  );

  return jsonb_build_object('resumo',v_resumo,'dias',v_dias);
end;
$$;

revoke all on function public.listar_feriados_empresa_admin(date,date)
  from public,anon;
grant execute on function public.listar_feriados_empresa_admin(date,date)
  to authenticated;

revoke all on function public.salvar_feriado_empresa_admin(
  uuid,date,text,text,text,boolean,boolean,text
) from public,anon;
grant execute on function public.salvar_feriado_empresa_admin(
  uuid,date,text,text,text,boolean,boolean,text
) to authenticated;

revoke all on function public.excluir_feriado_empresa_admin(uuid)
  from public,anon;
grant execute on function public.excluir_feriado_empresa_admin(uuid)
  to authenticated;

revoke all on function public.gerar_feriados_padrao_serra_admin(integer)
  from public,anon;
grant execute on function public.gerar_feriados_padrao_serra_admin(integer)
  to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 46 — RC5.49
-- Origem histórica: supabase-rc5-49-corrige-pendencia-dia-atual.sql
-- =====================================================================

-- Plenitude Ponto RC5.49
-- Pendência de jornada somente após a virada do dia, usando o fuso da empresa.

begin;

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
  v_timezone text:='America/Sao_Paulo';
  v_hoje date;
begin
  select coalesce(e.timezone,'America/Sao_Paulo')
    into v_timezone
  from public.empresas e
  where e.id=p_empresa_id;

  v_hoje:=(clock_timestamp() at time zone v_timezone)::date;

  /*
   * Remove da fila qualquer pendência criada indevidamente para o dia atual
   * ou para uma data futura. A jornada ainda está em andamento.
   */
  update public.pendencias_jornada p
     set status='resolvida',
         resolvida_em=coalesce(p.resolvida_em,clock_timestamp()),
         atualizado_em=clock_timestamp(),
         observacao='Pendência removida porque a jornada ainda não havia encerrado.'
   where p.empresa_id=p_empresa_id
     and p.status='pendente'
     and (p_funcionario_id is null or p.funcionario_id=p_funcionario_id)
     and p.data_local>=v_hoje;

  /*
   * Resolve quando o dia anterior passa a possuir as quatro marcações.
   */
  update public.pendencias_jornada p
     set status='resolvida',
         resolvida_em=coalesce(p.resolvida_em,clock_timestamp()),
         atualizado_em=clock_timestamp(),
         observacao=coalesce(
           p.observacao,
           'Regularizada por marcação ou ajuste posterior.'
         )
   where p.empresa_id=p_empresa_id
     and p.status='pendente'
     and p.data_local<v_hoje
     and (p_funcionario_id is null or p.funcionario_id=p_funcionario_id)
     and (
       select count(*)
       from public.marcacoes m
       where m.funcionario_id=p.funcionario_id
         and m.data_local=p.data_local
     )>=4;

  /*
   * Gera pendência exclusivamente para dias anteriores no fuso da empresa.
   * Nunca usa current_date, pois ele segue o fuso da sessão do banco.
   */
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
  join public.funcionarios f
    on f.id=m.funcionario_id
  where f.empresa_id=p_empresa_id
    and f.ativo=true
    and m.data_local<v_hoje
    and (p_funcionario_id is null or f.id=p_funcionario_id)
  group by f.empresa_id,f.id,m.data_local
  having count(*) between 1 and 3
  on conflict (funcionario_id,data_local)
  do update set
    quantidade_marcacoes=excluded.quantidade_marcacoes,
    marcacao_faltante=excluded.marcacao_faltante,
    status='pendente',
    resolvida_em=null,
    atualizado_em=clock_timestamp(),
    observacao=null;

  get diagnostics v_count=row_count;
  return v_count;
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
  v_timezone text:='America/Sao_Paulo';
  v_hoje date;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id=v_user
    and p.papel='administrador';

  if v_empresa is null then
    raise exception 'Acesso administrativo necessário.';
  end if;

  select coalesce(e.timezone,'America/Sao_Paulo')
    into v_timezone
  from public.empresas e
  where e.id=v_empresa;

  v_hoje:=(clock_timestamp() at time zone v_timezone)::date;

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
  join public.funcionarios f
    on f.id=pj.funcionario_id
  where pj.empresa_id=v_empresa
    and pj.status='pendente'
    and pj.data_local<v_hoje
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
set search_path=public,extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_timezone text:='America/Sao_Paulo';
  v_hoje date;
begin
  v_funcionario:=public.funcionario_por_token(p_token);

  select coalesce(e.timezone,'America/Sao_Paulo')
    into v_timezone
  from public.empresas e
  where e.id=v_funcionario.empresa_id;

  v_hoje:=(clock_timestamp() at time zone v_timezone)::date;

  perform public.atualizar_pendencias_jornada_empresa(
    v_funcionario.empresa_id,
    v_funcionario.id
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
  where pj.empresa_id=v_funcionario.empresa_id
    and pj.funcionario_id=v_funcionario.id
    and pj.status='pendente'
    and pj.data_local<v_hoje
  order by pj.data_local,pj.detectada_em;
end;
$$;

revoke all on function public.atualizar_pendencias_jornada_empresa(uuid,uuid)
  from public,anon,authenticated;

revoke all on function public.listar_pendencias_jornada_admin()
  from public,anon;

grant execute on function public.listar_pendencias_jornada_admin()
  to authenticated;

revoke all on function public.listar_minhas_pendencias_jornada(text)
  from public;

grant execute on function public.listar_minhas_pendencias_jornada(text)
  to anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 47 — RC5.60
-- Origem histórica: supabase-rc5-60-protecao-registro-ponto.sql
-- =====================================================================

-- Plenitude Ponto RC5.60
-- Proteção transacional contra múltiplos cliques e intervalo mínimo do almoço.

begin;

create or replace function public.registrar_ponto_com_pin(p_token text)
returns public.marcacoes
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_empresa public.empresas%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_agora timestamptz:=clock_timestamp();
  v_data date;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_ultima_marcacao timestamptz;
  v_inicio_intervalo timestamptz;
  v_intervalo_minimo integer:=30;
  v_restante_segundos integer;
  v_restante_minutos integer;
begin
  v_funcionario:=public.funcionario_por_token(p_token);

  select *
    into v_empresa
  from public.empresas e
  where e.id=v_funcionario.empresa_id
    and e.ativa=true;

  if v_empresa.id is null then
    raise exception 'Empresa inativa ou não encontrada.';
  end if;

  v_data:=(v_agora at time zone coalesce(v_empresa.timezone,'America/Sao_Paulo'))::date;

  -- Uma única transação por funcionário, inclusive entre abas e computadores.
  perform pg_advisory_xact_lock(
    hashtextextended(v_funcionario.id::text,20260803)
  );

  select
    count(*)::integer,
    max(m.registrado_em)
  into
    v_quantidade,
    v_ultima_marcacao
  from public.marcacoes m
  where m.funcionario_id=v_funcionario.id
    and m.data_local=v_data;

  if v_quantidade>=4 then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  -- Bloqueia requisições repetidas e cliques múltiplos.
  if v_ultima_marcacao is not null
     and v_agora-v_ultima_marcacao<interval '5 seconds' then
    raise exception 'Marcação já recebida. Aguarde alguns segundos antes de tentar novamente.';
  end if;

  v_tipo:=case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  -- Validação estrutural: a sequência já gravada precisa estar íntegra.
  if exists(
    select 1
    from (
      select m.tipo,
             row_number() over(order by m.registrado_em,m.id) as posicao
      from public.marcacoes m
      where m.funcionario_id=v_funcionario.id
        and m.data_local=v_data
    ) sequencia
    where sequencia.tipo<>(
      array[
        'entrada'::public.tipo_marcacao,
        'inicio_intervalo'::public.tipo_marcacao,
        'fim_intervalo'::public.tipo_marcacao,
        'saida'::public.tipo_marcacao
      ]
    )[sequencia.posicao]
  ) then
    raise exception 'A sequência de marcações de hoje está inconsistente. Procure o administrador.';
  end if;

  if v_tipo='fim_intervalo'::public.tipo_marcacao then
    select m.registrado_em
      into v_inicio_intervalo
    from public.marcacoes m
    where m.funcionario_id=v_funcionario.id
      and m.data_local=v_data
      and m.tipo='inicio_intervalo'::public.tipo_marcacao
    order by m.registrado_em desc,m.id desc
    limit 1;

    if v_inicio_intervalo is null then
      raise exception 'Não foi encontrado o início do almoço.';
    end if;

    v_intervalo_minimo:=greatest(
      30,
      coalesce(v_empresa.intervalo_minimo_minutos,30)
    );

    v_restante_segundos:=ceil(
      extract(epoch from(
        v_inicio_intervalo+
        make_interval(mins=>v_intervalo_minimo)-
        v_agora
      ))
    )::integer;

    if v_restante_segundos>0 then
      v_restante_minutos:=ceil(v_restante_segundos/60.0)::integer;
      raise exception
        'Retorno do almoço bloqueado. O intervalo mínimo é de % minutos. Aguarde mais % minuto(s).',
        v_intervalo_minimo,
        v_restante_minutos;
    end if;
  end if;

  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem
  )
  values(
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'pin'
  )
  returning * into v_marcacao;

  return v_marcacao;
end;
$$;


create or replace function public.registrar_ponto_dispositivo(
  p_token text,
  p_dispositivo_token text,
  p_user_agent text default null
)
returns public.marcacoes
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
begin
  select d.*
    into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash=encode(
      extensions.digest(coalesce(p_dispositivo_token,''),'sha256'),
      'hex'
    )
    and d.ativo=true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Registro bloqueado: computador não autorizado.';
  end if;

  v_funcionario:=public.funcionario_por_token(p_token);

  if v_funcionario.empresa_id<>v_dispositivo.empresa_id then
    raise exception 'Dispositivo não autorizado para esta empresa.';
  end if;

  -- Toda regra crítica fica concentrada na função protegida.
  v_marcacao:=public.registrar_ponto_com_pin(p_token);

  update public.marcacoes
     set origem='dispositivo'
   where id=v_marcacao.id
   returning * into v_marcacao;

  update public.dispositivos_ponto
     set ultimo_uso_em=clock_timestamp()
   where id=v_dispositivo.id;

  return v_marcacao;
end;
$$;


create or replace function public.registrar_ponto_funcionario(
  p_funcionario_id uuid
)
returns public.marcacoes
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_perfil public.perfis%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_empresa public.empresas%rowtype;
  v_resultado public.marcacoes%rowtype;
  v_agora timestamptz:=clock_timestamp();
  v_data date;
  v_quantidade integer;
  v_tipo public.tipo_marcacao;
  v_ultima_marcacao timestamptz;
  v_inicio_intervalo timestamptz;
  v_intervalo_minimo integer:=30;
  v_restante_segundos integer;
begin
  select *
    into v_perfil
  from public.perfis p
  where p.id=auth.uid()
    and p.ativo=true;

  if v_perfil.id is null
     or v_perfil.papel<>'administrador'::public.perfil_papel then
    raise exception 'Apenas administradores podem registrar ponto para outro funcionário.';
  end if;

  select *
    into v_funcionario
  from public.funcionarios f
  where f.id=p_funcionario_id
    and f.empresa_id=v_perfil.empresa_id
    and f.ativo=true;

  if v_funcionario.id is null then
    raise exception 'Funcionário ativo não encontrado nesta empresa.';
  end if;

  select *
    into v_empresa
  from public.empresas e
  where e.id=v_funcionario.empresa_id
    and e.ativa=true;

  v_data:=(v_agora at time zone coalesce(v_empresa.timezone,'America/Sao_Paulo'))::date;

  perform pg_advisory_xact_lock(
    hashtextextended(v_funcionario.id::text,20260803)
  );

  select count(*)::integer,max(m.registrado_em)
    into v_quantidade,v_ultima_marcacao
  from public.marcacoes m
  where m.funcionario_id=v_funcionario.id
    and m.data_local=v_data;

  if v_quantidade>=4 then
    raise exception 'As quatro marcações do dia já foram realizadas.';
  end if;

  if v_ultima_marcacao is not null
     and v_agora-v_ultima_marcacao<interval '5 seconds' then
    raise exception 'Marcação já recebida. Aguarde alguns segundos antes de tentar novamente.';
  end if;

  v_tipo:=case v_quantidade
    when 0 then 'entrada'::public.tipo_marcacao
    when 1 then 'inicio_intervalo'::public.tipo_marcacao
    when 2 then 'fim_intervalo'::public.tipo_marcacao
    when 3 then 'saida'::public.tipo_marcacao
    else null
  end;

  if v_tipo='fim_intervalo'::public.tipo_marcacao then
    select m.registrado_em
      into v_inicio_intervalo
    from public.marcacoes m
    where m.funcionario_id=v_funcionario.id
      and m.data_local=v_data
      and m.tipo='inicio_intervalo'::public.tipo_marcacao
    order by m.registrado_em desc,m.id desc
    limit 1;

    v_intervalo_minimo:=greatest(
      30,
      coalesce(v_empresa.intervalo_minimo_minutos,30)
    );

    v_restante_segundos:=ceil(
      extract(epoch from(
        v_inicio_intervalo+
        make_interval(mins=>v_intervalo_minimo)-
        v_agora
      ))
    )::integer;

    if v_inicio_intervalo is null then
      raise exception 'Não foi encontrado o início do almoço.';
    elsif v_restante_segundos>0 then
      raise exception
        'Retorno do almoço bloqueado. Aguarde o intervalo mínimo de % minutos.',
        v_intervalo_minimo;
    end if;
  end if;

  insert into public.marcacoes(
    empresa_id,
    funcionario_id,
    tipo,
    registrado_em,
    data_local,
    origem,
    criado_por
  )
  values(
    v_funcionario.empresa_id,
    v_funcionario.id,
    v_tipo,
    v_agora,
    v_data,
    'painel_admin',
    auth.uid()
  )
  returning * into v_resultado;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    tabela,
    registro_id,
    acao,
    dados
  )
  values(
    v_funcionario.empresa_id,
    auth.uid(),
    'marcacoes',
    v_resultado.id::text,
    'INSERT_ADMIN',
    jsonb_build_object(
      'funcionario_id',v_funcionario.id,
      'tipo',v_resultado.tipo,
      'registrado_em',v_resultado.registrado_em
    )
  );

  return v_resultado;
end;
$$;


revoke all on function public.registrar_ponto_com_pin(text)
  from public,anon,authenticated;

revoke all on function public.registrar_ponto_dispositivo(text,text,text)
  from public;

grant execute on function public.registrar_ponto_dispositivo(text,text,text)
  to anon,authenticated;

revoke all on function public.registrar_ponto_funcionario(uuid)
  from public,anon;

grant execute on function public.registrar_ponto_funcionario(uuid)
  to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 48 — RC5.61
-- Origem histórica: supabase-rc5-61-gerenciar-exclusao-marcacoes.sql
-- =====================================================================

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



-- =====================================================================
-- SEÇÃO 49 — RC5.62
-- Origem histórica: supabase-rc5-62-tempo-oficial.sql
-- =====================================================================

-- Plenitude Ponto RC5.62
-- Hora oficial centralizada para o frontend.

begin;

create or replace function public.horario_oficial_sistema()
returns table(
  agora timestamptz,
  timezone text,
  data_local date
)
language sql
security definer
set search_path=public
as $$
  select
    clock_timestamp(),
    coalesce(
      (
        select e.timezone
        from public.empresas e
        where e.id=public.empresa_do_usuario()
        limit 1
      ),
      'America/Sao_Paulo'
    )::text,
    (
      clock_timestamp() at time zone coalesce(
        (
          select e.timezone
          from public.empresas e
          where e.id=public.empresa_do_usuario()
          limit 1
        ),
        'America/Sao_Paulo'
      )
    )::date;
$$;

revoke all on function public.horario_oficial_sistema()
  from public,anon;

grant execute on function public.horario_oficial_sistema()
  to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 50 — RC5.63
-- Origem histórica: supabase-rc5-63-corrige-hora-oficial-funcionario.sql
-- =====================================================================

-- Plenitude Ponto RC5.63
-- Corrige o acesso ao horário oficial na tela do funcionário.

begin;

create or replace function public.horario_oficial_sistema()
returns table(
  agora timestamptz,
  timezone text,
  data_local date
)
language sql
security definer
set search_path=public
as $$
  select
    clock_timestamp(),
    'America/Sao_Paulo'::text,
    (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
$$;

revoke all on function public.horario_oficial_sistema()
  from public;

grant execute on function public.horario_oficial_sistema()
  to anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 51 — RC5.67
-- Origem histórica: supabase-rc5-67-desativacao-funcionario.sql
-- =====================================================================

-- Plenitude Ponto RC5.67
-- Desativação de funcionário em dois níveis.

begin;

create or replace function public.alterar_atividade_funcionario_admin(
  p_funcionario_id uuid,
  p_acao text,
  p_motivo text default null,
  p_master_pin text default null,
  p_confirmacao text default null
)
returns table(
  funcionario_id uuid,
  nome text,
  ativo boolean,
  status text,
  dados_resetados boolean
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_funcionario public.funcionarios%rowtype;
  v_acao text:=lower(trim(coalesce(p_acao,'')));
  v_reset boolean:=false;
  v_resumo jsonb:='{}'::jsonb;
  v_count integer;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if length(trim(coalesce(p_motivo,'')))<8 then
    raise exception 'Informe um motivo com pelo menos 8 caracteres.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  select *
    into v_funcionario
  from public.funcionarios f
  where f.id=p_funcionario_id
    and f.empresa_id=v_empresa
  for update;

  if v_funcionario.id is null then
    raise exception 'Funcionário não encontrado nesta empresa.';
  end if;

  if v_acao='reativar' then
    update public.funcionarios
       set ativo=true,
           status='ativo',
           acesso_ponto_ativo=true
     where id=v_funcionario.id;

    perform public.registrar_evento_auditoria(
      'REATIVAR_FUNCIONARIO',
      'funcionarios',
      v_funcionario.id::text,
      'Funcionário reativado para uso no sistema',
      jsonb_build_object(
        'nome',v_funcionario.nome,
        'matricula',v_funcionario.matricula,
        'motivo',trim(p_motivo)
      ),
      'web'
    );

  elsif v_acao='desativar_manter' then
    update public.funcionarios
       set ativo=false,
           status='inativo',
           acesso_ponto_ativo=false
     where id=v_funcionario.id;

    update public.sessoes_funcionario
       set encerrado_em=coalesce(encerrado_em,clock_timestamp())
     where funcionario_id=v_funcionario.id
       and encerrado_em is null;

    perform public.registrar_evento_auditoria(
      'DESATIVAR_FUNCIONARIO',
      'funcionarios',
      v_funcionario.id::text,
      'Funcionário desativado com histórico preservado',
      jsonb_build_object(
        'nivel',1,
        'nome',v_funcionario.nome,
        'matricula',v_funcionario.matricula,
        'motivo',trim(p_motivo),
        'historico_preservado',true
      ),
      'web'
    );

  elsif v_acao='desativar_resetar' then
    if upper(trim(coalesce(p_confirmacao,'')))<>'RESETAR' then
      raise exception 'Digite RESETAR para confirmar a limpeza dos dados.';
    end if;

    perform public.validar_pin_mestre_interno(v_empresa,p_master_pin);
    v_reset:=true;

    -- Quantidades antes da limpeza para auditoria.
    select jsonb_build_object(
      'marcacoes',(select count(*) from public.marcacoes where funcionario_id=v_funcionario.id),
      'ajustes',(select count(*) from public.solicitacoes_ajuste where funcionario_id=v_funcionario.id),
      'contingencias',(select count(*) from public.marcacoes_contingencia where funcionario_id=v_funcionario.id),
      'movimentacoes',(select count(*) from public.movimentacoes_jornada where funcionario_id=v_funcionario.id),
      'pendencias',(select count(*) from public.pendencias_jornada where funcionario_id=v_funcionario.id),
      'espelhos',(select count(*) from public.espelhos_mensais where funcionario_id=v_funcionario.id)
    ) into v_resumo;

    -- Remove dados operacionais e mensais. Cadastro, PIN, foto e jornada semanal
    -- permanecem para permitir reativação rápida em futuras homologações.
    delete from public.solicitacoes_ajuste
     where funcionario_id=v_funcionario.id;

    delete from public.pendencias_jornada
     where funcionario_id=v_funcionario.id;

    delete from public.movimentacoes_jornada
     where funcionario_id=v_funcionario.id;

    delete from public.marcacoes_contingencia
     where funcionario_id=v_funcionario.id;

    delete from public.espelhos_mensais
     where funcionario_id=v_funcionario.id;

    delete from public.marcacoes_arquivadas
     where funcionario_id=v_funcionario.id;

    delete from public.marcacoes
     where funcionario_id=v_funcionario.id;

    delete from public.sessoes_funcionario
     where funcionario_id=v_funcionario.id;

    update public.funcionarios
       set ativo=false,
           status='inativo',
           acesso_ponto_ativo=false
     where id=v_funcionario.id;

    perform public.registrar_evento_auditoria(
      'DESATIVAR_RESETAR_FUNCIONARIO',
      'funcionarios',
      v_funcionario.id::text,
      'Funcionário desativado e dados operacionais resetados',
      jsonb_build_object(
        'nivel',2,
        'nome',v_funcionario.nome,
        'matricula',v_funcionario.matricula,
        'motivo',trim(p_motivo),
        'dados_removidos',v_resumo,
        'cadastro_preservado',true,
        'jornada_semanal_preservada',true
      ),
      'web'
    );

  else
    raise exception 'Ação inválida.';
  end if;

  return query
  select
    f.id,
    f.nome,
    f.ativo,
    f.status::text,
    v_reset
  from public.funcionarios f
  where f.id=v_funcionario.id;
end;
$$;

revoke all on function public.alterar_atividade_funcionario_admin(uuid,text,text,text,text)
  from public,anon;

grant execute on function public.alterar_atividade_funcionario_admin(uuid,text,text,text,text)
  to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 52 — RC5.68
-- Origem histórica: supabase-rc5-68-corrige-desativacao-funcionario.sql
-- =====================================================================

-- Plenitude Ponto RC5.68
-- Correção da função de desativação/reativação de funcionário.
-- Remove ambiguidade de nomes e retorna JSONB.

begin;

drop function if exists public.alterar_atividade_funcionario_admin(
  uuid,text,text,text,text
);

create or replace function public.alterar_atividade_funcionario_admin(
  p_funcionario_id uuid,
  p_acao text,
  p_motivo text default null,
  p_master_pin text default null,
  p_confirmacao text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa_id uuid;
  v_funcionario public.funcionarios%rowtype;
  v_acao_normalizada text:=lower(trim(coalesce(p_acao,'')));
  v_reset boolean:=false;
  v_resumo jsonb:='{}'::jsonb;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if length(trim(coalesce(p_motivo,'')))<8 then
    raise exception 'Informe um motivo com pelo menos 8 caracteres.';
  end if;

  v_empresa_id:=public.empresa_do_usuario();

  select f.*
    into v_funcionario
  from public.funcionarios f
  where f.id=p_funcionario_id
    and f.empresa_id=v_empresa_id
  for update;

  if v_funcionario.id is null then
    raise exception 'Funcionário não encontrado nesta empresa.';
  end if;

  if v_acao_normalizada='reativar' then
    update public.funcionarios f
       set ativo=true,
           status='ativo',
           acesso_ponto_ativo=true
     where f.id=v_funcionario.id
       and f.empresa_id=v_empresa_id;

    perform public.registrar_evento_auditoria(
      'REATIVAR_FUNCIONARIO',
      'funcionarios',
      v_funcionario.id::text,
      'Funcionário reativado para uso no sistema',
      jsonb_build_object(
        'nome',v_funcionario.nome,
        'matricula',v_funcionario.matricula,
        'motivo',trim(p_motivo)
      ),
      'web'
    );

  elsif v_acao_normalizada='desativar_manter' then
    update public.funcionarios f
       set ativo=false,
           status='inativo',
           acesso_ponto_ativo=false
     where f.id=v_funcionario.id
       and f.empresa_id=v_empresa_id;

    update public.sessoes_funcionario sf
       set encerrado_em=coalesce(sf.encerrado_em,clock_timestamp())
     where sf.funcionario_id=v_funcionario.id
       and sf.encerrado_em is null;

    perform public.registrar_evento_auditoria(
      'DESATIVAR_FUNCIONARIO',
      'funcionarios',
      v_funcionario.id::text,
      'Funcionário desativado com histórico preservado',
      jsonb_build_object(
        'nivel',1,
        'nome',v_funcionario.nome,
        'matricula',v_funcionario.matricula,
        'motivo',trim(p_motivo),
        'historico_preservado',true
      ),
      'web'
    );

  elsif v_acao_normalizada='desativar_resetar' then
    if upper(trim(coalesce(p_confirmacao,'')))<>'RESETAR' then
      raise exception 'Digite RESETAR para confirmar a limpeza dos dados.';
    end if;

    perform public.validar_pin_mestre_interno(
      v_empresa_id,
      p_master_pin
    );

    v_reset:=true;

    select jsonb_build_object(
      'marcacoes',(
        select count(*)
        from public.marcacoes m
        where m.funcionario_id=v_funcionario.id
      ),
      'ajustes',(
        select count(*)
        from public.solicitacoes_ajuste sa
        where sa.funcionario_id=v_funcionario.id
      ),
      'contingencias',(
        select count(*)
        from public.marcacoes_contingencia mc
        where mc.funcionario_id=v_funcionario.id
      ),
      'movimentacoes',(
        select count(*)
        from public.movimentacoes_jornada mj
        where mj.funcionario_id=v_funcionario.id
      ),
      'pendencias',(
        select count(*)
        from public.pendencias_jornada pj
        where pj.funcionario_id=v_funcionario.id
      ),
      'espelhos',(
        select count(*)
        from public.espelhos_mensais em
        where em.funcionario_id=v_funcionario.id
      ),
      'arquivadas',(
        select count(*)
        from public.marcacoes_arquivadas ma
        where ma.funcionario_id=v_funcionario.id
      )
    )
    into v_resumo;

    delete from public.solicitacoes_ajuste sa
     where sa.funcionario_id=v_funcionario.id;

    delete from public.pendencias_jornada pj
     where pj.funcionario_id=v_funcionario.id;

    delete from public.movimentacoes_jornada mj
     where mj.funcionario_id=v_funcionario.id;

    delete from public.marcacoes_contingencia mc
     where mc.funcionario_id=v_funcionario.id;

    delete from public.espelhos_mensais em
     where em.funcionario_id=v_funcionario.id;

    delete from public.marcacoes_arquivadas ma
     where ma.funcionario_id=v_funcionario.id;

    delete from public.marcacoes m
     where m.funcionario_id=v_funcionario.id;

    delete from public.sessoes_funcionario sf
     where sf.funcionario_id=v_funcionario.id;

    update public.funcionarios f
       set ativo=false,
           status='inativo',
           acesso_ponto_ativo=false
     where f.id=v_funcionario.id
       and f.empresa_id=v_empresa_id;

    perform public.registrar_evento_auditoria(
      'DESATIVAR_RESETAR_FUNCIONARIO',
      'funcionarios',
      v_funcionario.id::text,
      'Funcionário desativado e dados operacionais resetados',
      jsonb_build_object(
        'nivel',2,
        'nome',v_funcionario.nome,
        'matricula',v_funcionario.matricula,
        'motivo',trim(p_motivo),
        'dados_removidos',v_resumo,
        'cadastro_preservado',true,
        'jornada_semanal_preservada',true
      ),
      'web'
    );

  else
    raise exception 'Ação inválida.';
  end if;

  return (
    select jsonb_build_object(
      'id',f.id,
      'funcionario_id',f.id,
      'nome',f.nome,
      'matricula',f.matricula,
      'ativo',f.ativo,
      'status',f.status,
      'acesso_ponto_ativo',f.acesso_ponto_ativo,
      'dados_resetados',v_reset
    )
    from public.funcionarios f
    where f.id=v_funcionario.id
      and f.empresa_id=v_empresa_id
  );
end;
$$;

revoke all on function public.alterar_atividade_funcionario_admin(
  uuid,text,text,text,text
)
from public,anon;

grant execute on function public.alterar_atividade_funcionario_admin(
  uuid,text,text,text,text
)
to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 53 — RC5.75
-- Origem histórica: supabase-rc5-75-corrige-tolerancia-entrada.sql
-- =====================================================================

-- ============================================================
-- PLENITUDE PONTO RC5.75
-- CORREÇÃO DA TOLERÂNCIA DE ENTRADA NO BANCO DE HORAS
-- ============================================================
--
-- Regra:
-- - horário real continua registrado e visível;
-- - entrada dentro da tolerância é considerada como a hora prevista
--   somente para cálculo de horas/saldo;
-- - entrada depois do limite usa o horário real;
-- - não altera marcações gravadas.
--
-- Após executar, relatórios e espelhos são recalculados automaticamente
-- quando forem abertos novamente.

begin;

create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    /*
     * Tolerância de entrada:
     * - mantém o horário REAL registrado;
     * - para o cálculo, considera a entrada prevista quando a marcação ocorreu
     *   do primeiro segundo após a hora prevista até o final do minuto-limite.
     *
     * Exemplo com jornada 09:00 e tolerância 10:
     * 09:00:01 até 09:10:59 => entrada considerada 09:00.
     * 09:11:00 em diante     => utiliza o horário real.
     */
    if j.id is not null and entrada_real is not null
       and entrada_real > ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and entrada_real < (
         ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         + make_interval(mins=>coalesce(e.tolerancia_entrada_minutos,0)+1)
       ) then
      entrada_calc:=(d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null
       and saida_real < ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and saida_real >= (
         ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         - make_interval(mins=>coalesce(e.tolerancia_saida_minutos,0))
       ) then
      saida_calc:=(d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    select coalesce(sum(case when aprovado and efeito_calculo='descontar' and fim_em is not null then round(extract(epoch from (fim_em-inicio_em))/60)::int else 0 end),0),
           coalesce(sum(case when aprovado and efeito_calculo='abonar' and fim_em is not null then round(extract(epoch from (fim_em-inicio_em))/60)::int else 0 end),0),
           coalesce(bool_or(aprovado and efeito_calculo='credito'),false),
           coalesce(jsonb_agg(jsonb_build_object('id',id,'inicio_em',inicio_em,'fim_em',fim_em,'classificacao',classificacao,'efeito',efeito_calculo,'status',status,'aprovado',aprovado) order by inicio_em),'[]'::jsonb)
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada where funcionario_id=f.id and data_local=d.data and status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then status:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then status:='aguardando'; else status:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0 and not e.horas_extras_automaticas and not extra_autorizada then saldo:=0; end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date)
from public,anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 54 — RC5.76
-- Origem histórica: supabase-rc5-76-corrige-banco-horas-400.sql
-- =====================================================================

-- ============================================================
-- PLENITUDE PONTO RC5.76
-- CORREÇÃO DO ERRO 400 NO BANCO DE HORAS
-- ============================================================
--
-- Causa:
-- A RC5.75 instalou a versão completa do cálculo com movimentações.
-- Nessa função existia uma variável PL/pgSQL chamada "status" e uma coluna
-- também chamada "status" na tabela movimentacoes_jornada.
--
-- A consulta usava "status" sem informar a tabela, causando ambiguidade em
-- tempo de execução e fazendo banco_horas_admin retornar HTTP 400.
--
-- Esta correção:
-- 1. qualifica todas as colunas de movimentacoes_jornada com o alias "mj";
-- 2. mantém a correção da tolerância de entrada;
-- 3. não altera nenhuma marcação;
-- 4. não apaga dados.

begin;

create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    /*
     * Tolerância de entrada:
     * - mantém o horário REAL registrado;
     * - para o cálculo, considera a entrada prevista quando a marcação ocorreu
     *   do primeiro segundo após a hora prevista até o final do minuto-limite.
     *
     * Exemplo com jornada 09:00 e tolerância 10:
     * 09:00:01 até 09:10:59 => entrada considerada 09:00.
     * 09:11:00 em diante     => utiliza o horário real.
     */
    if j.id is not null and entrada_real is not null
       and entrada_real > ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and entrada_real < (
         ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         + make_interval(mins=>coalesce(e.tolerancia_entrada_minutos,0)+1)
       ) then
      entrada_calc:=(d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null
       and saida_real < ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and saida_real >= (
         ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         - make_interval(mins=>coalesce(e.tolerancia_saida_minutos,0))
       ) then
      saida_calc:=(d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    select
      coalesce(sum(
        case
          when mj.aprovado
           and mj.efeito_calculo='descontar'
           and mj.fim_em is not null
          then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int
          else 0
        end
      ),0),
      coalesce(sum(
        case
          when mj.aprovado
           and mj.efeito_calculo='abonar'
           and mj.fim_em is not null
          then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int
          else 0
        end
      ),0),
      coalesce(bool_or(
        mj.aprovado and mj.efeito_calculo='credito'
      ),false),
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id',mj.id,
            'inicio_em',mj.inicio_em,
            'fim_em',mj.fim_em,
            'classificacao',mj.classificacao,
            'efeito',mj.efeito_calculo,
            'status',mj.status,
            'aprovado',mj.aprovado
          )
          order by mj.inicio_em
        ),
        '[]'::jsonb
      )
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada mj
    where mj.funcionario_id=f.id
      and mj.data_local=d.data
      and mj.status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then status:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then status:='aguardando'; else status:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0 and not e.horas_extras_automaticas and not extra_autorizada then saldo:=0; end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date)
from public,anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 55 — RC5.77
-- Origem histórica: supabase-rc5-77-corrige-creditos-banco-horas.sql
-- =====================================================================

-- RC5.77 — correção dos créditos positivos no banco de horas

begin;

create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    if j.id is not null and entrada_real is not null and entrada_real > (d.data+j.entrada) at time zone e.timezone
       and entrada_real <= ((d.data+j.entrada) at time zone e.timezone)+make_interval(mins=>e.tolerancia_entrada_minutos) then
      entrada_calc:=(d.data+j.entrada) at time zone e.timezone; tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null and saida_real < (d.data+j.saida) at time zone e.timezone
       and saida_real >= ((d.data+j.saida) at time zone e.timezone)-make_interval(mins=>e.tolerancia_saida_minutos) then
      saida_calc:=(d.data+j.saida) at time zone e.timezone; tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    select coalesce(sum(case when aprovado and efeito_calculo='descontar' and fim_em is not null then round(extract(epoch from (fim_em-inicio_em))/60)::int else 0 end),0),
           coalesce(sum(case when aprovado and efeito_calculo='abonar' and fim_em is not null then round(extract(epoch from (fim_em-inicio_em))/60)::int else 0 end),0),
           coalesce(bool_or(aprovado and efeito_calculo='credito'),false),
           coalesce(jsonb_agg(jsonb_build_object('id',id,'inicio_em',inicio_em,'fim_em',fim_em,'classificacao',classificacao,'efeito',efeito_calculo,'status',status,'aprovado',aprovado) order by inicio_em),'[]'::jsonb)
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada where funcionario_id=f.id and data_local=d.data and status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then status:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then status:='aguardando'; else status:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0
           and coalesce(e.horas_extras_automaticas,false) is not true
           and extra_autorizada is not true then
          saldo:=0;
        end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date) from public,anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 56 — RC5.78
-- Origem histórica: supabase-rc5-78-corrige-creditos-positivos.sql
-- =====================================================================

-- PLENITUDE PONTO RC5.78
-- Corrige o credito positivo no banco de horas.
-- Mantem a correcao RC5.76 do erro 400 e todas as regras atuais.
-- Nao altera nem apaga marcacoes.

begin;

create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    /*
     * Tolerância de entrada:
     * - mantém o horário REAL registrado;
     * - para o cálculo, considera a entrada prevista quando a marcação ocorreu
     *   do primeiro segundo após a hora prevista até o final do minuto-limite.
     *
     * Exemplo com jornada 09:00 e tolerância 10:
     * 09:00:01 até 09:10:59 => entrada considerada 09:00.
     * 09:11:00 em diante     => utiliza o horário real.
     */
    if j.id is not null and entrada_real is not null
       and entrada_real > ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and entrada_real < (
         ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         + make_interval(mins=>coalesce(e.tolerancia_entrada_minutos,0)+1)
       ) then
      entrada_calc:=(d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null
       and saida_real < ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and saida_real >= (
         ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         - make_interval(mins=>coalesce(e.tolerancia_saida_minutos,0))
       ) then
      saida_calc:=(d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    select
      coalesce(sum(
        case
          when mj.aprovado
           and mj.efeito_calculo='descontar'
           and mj.fim_em is not null
          then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int
          else 0
        end
      ),0),
      coalesce(sum(
        case
          when mj.aprovado
           and mj.efeito_calculo='abonar'
           and mj.fim_em is not null
          then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int
          else 0
        end
      ),0),
      coalesce(bool_or(
        mj.aprovado and mj.efeito_calculo='credito'
      ),false),
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id',mj.id,
            'inicio_em',mj.inicio_em,
            'fim_em',mj.fim_em,
            'classificacao',mj.classificacao,
            'efeito',mj.efeito_calculo,
            'status',mj.status,
            'aprovado',mj.aprovado
          )
          order by mj.inicio_em
        ),
        '[]'::jsonb
      )
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada mj
    where mj.funcionario_id=f.id
      and mj.data_local=d.data
      and mj.status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then status:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then status:='aguardando'; else status:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0
           and coalesce(e.horas_extras_automaticas,false) is not true
           and coalesce(extra_autorizada,false) is not true then
          saldo:=0;
        end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date)
from public,anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 57 — RC5.79
-- Origem histórica: supabase-rc5-79-corrige-status-ambiguo-banco-horas.sql
-- =====================================================================

-- PLENITUDE PONTO RC5.79
-- Corrige o credito positivo no banco de horas.
-- Mantem a correcao RC5.76 do erro 400 e todas as regras atuais.
-- Nao altera nem apaga marcacoes.

begin;

create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; v_status_dia text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    /*
     * Tolerância de entrada:
     * - mantém o horário REAL registrado;
     * - para o cálculo, considera a entrada prevista quando a marcação ocorreu
     *   do primeiro segundo após a hora prevista até o final do minuto-limite.
     *
     * Exemplo com jornada 09:00 e tolerância 10:
     * 09:00:01 até 09:10:59 => entrada considerada 09:00.
     * 09:11:00 em diante     => utiliza o horário real.
     */
    if j.id is not null and entrada_real is not null
       and entrada_real > ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and entrada_real < (
         ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         + make_interval(mins=>coalesce(e.tolerancia_entrada_minutos,0)+1)
       ) then
      entrada_calc:=(d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null
       and saida_real < ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and saida_real >= (
         ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         - make_interval(mins=>coalesce(e.tolerancia_saida_minutos,0))
       ) then
      saida_calc:=(d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    select
      coalesce(sum(
        case
          when mj.aprovado
           and mj.efeito_calculo='descontar'
           and mj.fim_em is not null
          then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int
          else 0
        end
      ),0),
      coalesce(sum(
        case
          when mj.aprovado
           and mj.efeito_calculo='abonar'
           and mj.fim_em is not null
          then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int
          else 0
        end
      ),0),
      coalesce(bool_or(
        mj.aprovado and mj.efeito_calculo='credito'
      ),false),
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id',mj.id,
            'inicio_em',mj.inicio_em,
            'fim_em',mj.fim_em,
            'classificacao',mj.classificacao,
            'efeito',mj.efeito_calculo,
            'status',mj.status,
            'aprovado',mj.aprovado
          )
          order by mj.inicio_em
        ),
        '[]'::jsonb
      )
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada mj
    where mj.funcionario_id=f.id
      and mj.data_local=d.data
      and mj.status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then v_status_dia:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then v_status_dia:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif abono_mov>0 and trabalhado>=previsto then v_status_dia:='abonado'; saldo:=0; trabalhados:=trabalhados+1;
    elsif qtd=4 then v_status_dia:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then v_status_dia:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then v_status_dia:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then v_status_dia:='aguardando'; else v_status_dia:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0
           and coalesce(e.horas_extras_automaticas,false) is not true
           and coalesce(extra_autorizada,false) is not true then
          saldo:=0;
        end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',v_status_dia,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date)
from public,anon,authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 58 — RC5.82
-- Origem histórica: supabase-rc5-82-politicas-empresa.sql
-- =====================================================================

-- ============================================================
-- PLENITUDE PONTO RC5.82
-- FONTE ÚNICA DAS POLÍTICAS DA EMPRESA
-- ============================================================

begin;

create or replace function public.politicas_empresa_admin()
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa_id uuid;
  v_empresa public.empresas%rowtype;
begin
  select p.empresa_id
    into v_empresa_id
  from public.perfis p
  where p.id=auth.uid()
    and p.papel='administrador'
    and p.ativo=true;

  if v_empresa_id is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  select e.*
    into v_empresa
  from public.empresas e
  where e.id=v_empresa_id;

  if v_empresa.id is null then
    raise exception 'Empresa não encontrada.';
  end if;

  return jsonb_build_object(
    'empresa_id',v_empresa.id,
    'timezone',coalesce(v_empresa.timezone,'America/Sao_Paulo'),
    'tolerancia_entrada_minutos',coalesce(v_empresa.tolerancia_entrada_minutos,0),
    'tolerancia_saida_minutos',coalesce(v_empresa.tolerancia_saida_minutos,0),
    'intervalo_minimo_minutos',coalesce(v_empresa.intervalo_minimo_minutos,30),
    'intervalo_maximo_minutos',coalesce(v_empresa.intervalo_maximo_minutos,120),
    'horas_extras_automaticas',coalesce(v_empresa.horas_extras_automaticas,false),
    'limite_banco_horas_minutos',coalesce(v_empresa.limite_banco_horas_minutos,2400),
    'atualizada_em',v_empresa.atualizada_em
  );
end;
$$;

revoke all on function public.politicas_empresa_admin()
from public,anon;

grant execute on function public.politicas_empresa_admin()
to authenticated;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- SEÇÃO 59 — RC6.1
-- Origem histórica: supabase-rc6-1-banco-horas-acumulado.sql
-- =====================================================================

-- ============================================================
-- PLENITUDE PONTO RC6.1
-- BANCO DE HORAS ACUMULADO ENTRE COMPETÊNCIAS
-- ============================================================
--
-- Regra:
-- 1. O saldo mensal continua existindo separadamente.
-- 2. Ao FECHAR uma competência, o saldo daquele mês é congelado em snapshot.
-- 3. Competências fechadas anteriores formam o "saldo anterior".
-- 4. O banco acumulado exibido = saldo anterior consolidado + saldo da competência.
-- 5. Ao REABRIR uma competência, o snapshot daquele mês é removido.
-- 6. Ao FECHAR novamente, um novo snapshot é calculado.
--
-- Nenhuma marcação original é alterada.

begin;

create table if not exists public.banco_horas_competencias (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  ano integer not null check (ano between 2020 and 2100),
  mes integer not null check (mes between 1 and 12),
  saldo_competencia_minutos integer not null default 0,
  fechamento_id uuid references public.fechamentos_mensais(id) on delete set null,
  fechado_em timestamptz,
  calculado_em timestamptz not null default clock_timestamp(),
  unique (empresa_id, funcionario_id, ano, mes)
);

create index if not exists idx_banco_horas_competencias_funcionario
  on public.banco_horas_competencias(funcionario_id,ano,mes);

create index if not exists idx_banco_horas_competencias_empresa
  on public.banco_horas_competencias(empresa_id,ano,mes);

alter table public.banco_horas_competencias enable row level security;

revoke all on table public.banco_horas_competencias
  from public,anon,authenticated;


-- Função interna: consolida os saldos de todos os funcionários da empresa
-- quando uma competência é fechada.
create or replace function public._consolidar_banco_horas_competencia(
  p_empresa_id uuid,
  p_ano integer,
  p_mes integer,
  p_fechamento_id uuid default null,
  p_fechado_em timestamptz default null
)
returns void
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_inicio date;
  v_fim date;
  v_funcionario record;
  v_calculo jsonb;
  v_saldo integer;
begin
  if p_empresa_id is null then
    raise exception 'Empresa não informada.';
  end if;

  if p_ano not between 2020 and 2100 or p_mes not between 1 and 12 then
    raise exception 'Competência inválida.';
  end if;

  v_inicio:=make_date(p_ano,p_mes,1);
  v_fim:=(v_inicio+interval '1 month - 1 day')::date;

  for v_funcionario in
    select f.id
    from public.funcionarios f
    where f.empresa_id=p_empresa_id
      and (f.data_admissao is null or f.data_admissao<=v_fim)
    order by f.id
  loop
    v_calculo:=public._calcular_banco_horas_json(
      v_funcionario.id,
      v_inicio,
      v_fim
    );

    v_saldo:=coalesce(
      (v_calculo->'resumo'->>'saldo_minutos')::integer,
      0
    );

    insert into public.banco_horas_competencias(
      empresa_id,
      funcionario_id,
      ano,
      mes,
      saldo_competencia_minutos,
      fechamento_id,
      fechado_em,
      calculado_em
    )
    values(
      p_empresa_id,
      v_funcionario.id,
      p_ano,
      p_mes,
      v_saldo,
      p_fechamento_id,
      coalesce(p_fechado_em,clock_timestamp()),
      clock_timestamp()
    )
    on conflict(empresa_id,funcionario_id,ano,mes)
    do update set
      saldo_competencia_minutos=excluded.saldo_competencia_minutos,
      fechamento_id=excluded.fechamento_id,
      fechado_em=excluded.fechado_em,
      calculado_em=clock_timestamp();
  end loop;
end;
$$;

revoke all on function public._consolidar_banco_horas_competencia(
  uuid,integer,integer,uuid,timestamptz
) from public,anon,authenticated;


-- Trigger desacoplado do fluxo de fechamento atual.
-- Assim, tanto fechamento normal quanto fechamento com PIN Mestre
-- passam automaticamente a consolidar o banco.
create or replace function public.sincronizar_banco_horas_fechamento()
returns trigger
language plpgsql
security definer
set search_path=public,extensions
as $$
begin
  if new.status='fechado'
     and (
       tg_op='INSERT'
       or old.status is distinct from new.status
       or old.fechado_em is distinct from new.fechado_em
     ) then

    perform public._consolidar_banco_horas_competencia(
      new.empresa_id,
      new.ano,
      new.mes,
      new.id,
      new.fechado_em
    );

  elsif new.status='reaberto'
        and (
          tg_op='INSERT'
          or old.status is distinct from new.status
        ) then

    delete from public.banco_horas_competencias bh
    where bh.empresa_id=new.empresa_id
      and bh.ano=new.ano
      and bh.mes=new.mes;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sincronizar_banco_horas_fechamento
  on public.fechamentos_mensais;

create trigger trg_sincronizar_banco_horas_fechamento
after insert or update of status,fechado_em
on public.fechamentos_mensais
for each row
execute function public.sincronizar_banco_horas_fechamento();


-- Consulta do banco acumulado para o administrador.
create or replace function public.banco_horas_acumulado_admin(
  p_funcionario_id uuid,
  p_ano integer,
  p_mes integer
)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa_id uuid;
  v_inicio date;
  v_fim date;
  v_saldo_anterior integer:=0;
  v_saldo_competencia integer:=0;
  v_saldo_acumulado integer:=0;
  v_snapshot integer;
  v_calculo jsonb;
  v_competencias_consolidadas integer:=0;
  v_fechada boolean:=false;
  v_ultimo_fechamento date;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if p_ano not between 2020 and 2100 or p_mes not between 1 and 12 then
    raise exception 'Competência inválida.';
  end if;

  v_empresa_id:=public.empresa_do_usuario();

  if not exists(
    select 1
    from public.funcionarios f
    where f.id=p_funcionario_id
      and f.empresa_id=v_empresa_id
  ) then
    raise exception 'Funcionário não pertence à sua empresa.';
  end if;

  v_inicio:=make_date(p_ano,p_mes,1);
  v_fim:=(v_inicio+interval '1 month - 1 day')::date;

  select
    coalesce(sum(bh.saldo_competencia_minutos),0)::integer,
    count(*)::integer,
    max(make_date(bh.ano,bh.mes,1))
  into
    v_saldo_anterior,
    v_competencias_consolidadas,
    v_ultimo_fechamento
  from public.banco_horas_competencias bh
  where bh.empresa_id=v_empresa_id
    and bh.funcionario_id=p_funcionario_id
    and make_date(bh.ano,bh.mes,1)<v_inicio;

  select bh.saldo_competencia_minutos
    into v_snapshot
  from public.banco_horas_competencias bh
  where bh.empresa_id=v_empresa_id
    and bh.funcionario_id=p_funcionario_id
    and bh.ano=p_ano
    and bh.mes=p_mes;

  if found then
    v_saldo_competencia:=coalesce(v_snapshot,0);
    v_fechada:=true;
  else
    v_calculo:=public._calcular_banco_horas_json(
      p_funcionario_id,
      v_inicio,
      v_fim
    );

    v_saldo_competencia:=coalesce(
      (v_calculo->'resumo'->>'saldo_minutos')::integer,
      0
    );
  end if;

  v_saldo_acumulado:=v_saldo_anterior+v_saldo_competencia;

  return jsonb_build_object(
    'funcionario_id',p_funcionario_id,
    'ano',p_ano,
    'mes',p_mes,
    'competencia_fechada',v_fechada,
    'saldo_anterior_minutos',v_saldo_anterior,
    'saldo_competencia_minutos',v_saldo_competencia,
    'saldo_acumulado_minutos',v_saldo_acumulado,
    'competencias_consolidadas',v_competencias_consolidadas,
    'ultimo_fechamento',v_ultimo_fechamento,
    'regra','competencias_fechadas_mais_competencia_atual'
  );
end;
$$;

revoke all on function public.banco_horas_acumulado_admin(
  uuid,integer,integer
) from public,anon;

grant execute on function public.banco_horas_acumulado_admin(
  uuid,integer,integer
) to authenticated;


-- Reconstrução administrativa dos snapshots já existentes.
create or replace function public.reconstruir_banco_horas_fechamentos_admin()
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa_id uuid;
  v_fechamento record;
  v_total integer:=0;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  v_empresa_id:=public.empresa_do_usuario();

  for v_fechamento in
    select fm.*
    from public.fechamentos_mensais fm
    where fm.empresa_id=v_empresa_id
      and fm.status='fechado'
    order by fm.ano,fm.mes
  loop
    perform public._consolidar_banco_horas_competencia(
      v_fechamento.empresa_id,
      v_fechamento.ano,
      v_fechamento.mes,
      v_fechamento.id,
      v_fechamento.fechado_em
    );
    v_total:=v_total+1;
  end loop;

  perform public.registrar_evento_auditoria(
    'RECONSTRUIR_BANCO_HORAS',
    'banco_horas_competencias',
    null,
    format('%s competência(s) fechada(s) reconstruída(s)',v_total),
    jsonb_build_object('competencias_reconstruidas',v_total),
    'sql'
  );

  return jsonb_build_object(
    'sucesso',true,
    'competencias_reconstruidas',v_total
  );
end;
$$;

revoke all on function public.reconstruir_banco_horas_fechamentos_admin()
from public,anon;

grant execute on function public.reconstruir_banco_horas_fechamentos_admin()
to authenticated;


-- Migração inicial:
-- consolida automaticamente todas as competências que já estavam fechadas
-- antes da instalação da RC6.1. Isso permite que o saldo de meses anteriores
-- apareça imediatamente no banco acumulado.
do $$
declare
  v_fechamento record;
begin
  for v_fechamento in
    select fm.*
    from public.fechamentos_mensais fm
    where fm.status='fechado'
    order by fm.empresa_id,fm.ano,fm.mes
  loop
    perform public._consolidar_banco_horas_competencia(
      v_fechamento.empresa_id,
      v_fechamento.ano,
      v_fechamento.mes,
      v_fechamento.id,
      v_fechamento.fechado_em
    );
  end loop;
end;
$$;

commit;

notify pgrst,'reload schema';



-- =====================================================================
-- PÓS-INSTALAÇÃO — VINCULAR O PRIMEIRO ADMINISTRADOR
-- =====================================================================
-- 1) Crie primeiro o usuário no painel Authentication > Users.
-- 2) Substitua o e-mail abaixo e execute SOMENTE este bloco.
--
-- begin;
-- update public.perfis p
-- set
--   empresa_id = (
--     select e.id
--     from public.empresas e
--     where e.nome_fantasia = 'Presentes Plenitude e Artigos Religiosos'
--     order by e.criada_em
--     limit 1
--   ),
--   papel = 'administrador'::public.perfil_papel,
--   nome = coalesce(nullif(p.nome,''),'Administrador'),
--   ativo = true
-- from auth.users u
-- where p.id=u.id
--   and lower(u.email)=lower('TROQUE_AQUI_PELO_EMAIL_DO_ADMINISTRADOR');
-- commit;
--
-- =====================================================================
-- VALIDAÇÃO FINAL DA INSTALAÇÃO
-- =====================================================================

select
  'empresas' as objeto,
  to_regclass('public.empresas') is not null as instalado
union all select 'funcionarios',to_regclass('public.funcionarios') is not null
union all select 'jornadas',to_regclass('public.jornadas') is not null
union all select 'marcacoes',to_regclass('public.marcacoes') is not null
union all select 'solicitacoes_ajuste',to_regclass('public.solicitacoes_ajuste') is not null
union all select 'movimentacoes_jornada',to_regclass('public.movimentacoes_jornada') is not null
union all select 'fechamentos_mensais',to_regclass('public.fechamentos_mensais') is not null
union all select 'banco_horas_competencias',to_regclass('public.banco_horas_competencias') is not null
union all select 'pendencias_jornada',to_regclass('public.pendencias_jornada') is not null
union all select 'marcacoes_contingencia',to_regclass('public.marcacoes_contingencia') is not null;

select
  p.proname as funcao,
  pg_get_function_identity_arguments(p.oid) as argumentos
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'registrar_ponto_com_pin',
    'registrar_ponto_dispositivo',
    'banco_horas_admin',
    'banco_horas_acumulado_admin',
    'listar_ajustes_admin',
    'listar_pendencias_jornada_admin',
    'fechar_competencia_master_admin',
    'reabrir_competencia_master_admin',
    'politicas_empresa_admin'
  )
order by p.proname;

notify pgrst,'reload schema';


-- SEÇÃO FINAL — RC6.4
-- ============================================================
-- PLENITUDE PONTO RC6.4
-- ATESTADOS / ABONOS MULTIDIA LIMITADOS À JORNADA PREVISTA
-- ============================================================
-- Execute no SQL Editor do Supabase atual.
-- Não apaga nem altera marcações reais.
-- Corrige movimentações que atravessam vários dias: cada dia recebe apenas
-- a interseção com os dois trechos efetivamente trabalháveis da jornada,
-- excluindo o intervalo. O abono nunca gera crédito acima da carga prevista.

begin;

create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; v_status_dia text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  dia_ini timestamptz; dia_fim timestamptz; seg1_ini timestamptz; seg1_fim timestamptz; seg2_ini timestamptz; seg2_fim timestamptz;
  v_inicio_apuracao date;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;

  /*
   * RC6.2 — início real da apuração.
   * Prioridade:
   * 1. data_inicio_apuracao definida pelo administrador;
   * 2. primeira marcação existente;
   * 3. data de admissão;
   * 4. início do período solicitado.
   *
   * Isso impede que jornadas históricas sem marcações virem faltas retroativas.
   */
  select coalesce(
    f.data_inicio_apuracao,
    (select min(m.data_local) from public.marcacoes m where m.funcionario_id=f.id),
    f.data_admissao,
    p_inicio
  )
  into v_inicio_apuracao;

  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop

    if d.data < v_inicio_apuracao then
      dias:=dias||jsonb_build_array(jsonb_build_object(
        'data',d.data,
        'dia_semana',extract(isodow from d.data)::int,
        'previsto_minutos',0,
        'trabalhado_minutos',0,
        'saldo_minutos',0,
        'quantidade_marcacoes',0,
        'status','pre_apuracao',
        'ocorrencia',null,
        'marcacoes','[]'::jsonb,
        'tipos','[]'::jsonb,
        'tolerancia_aplicada',false,
        'intervalo_minutos',null,
        'alerta_intervalo',null,
        'movimentacoes','[]'::jsonb,
        'minutos_descontados',0,
        'minutos_abonados',0,
        'hora_extra_autorizada',false
      ));
      continue;
    end if;

    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    /*
     * Tolerância de entrada:
     * - mantém o horário REAL registrado;
     * - para o cálculo, considera a entrada prevista quando a marcação ocorreu
     *   do primeiro segundo após a hora prevista até o final do minuto-limite.
     *
     * Exemplo com jornada 09:00 e tolerância 10:
     * 09:00:01 até 09:10:59 => entrada considerada 09:00.
     * 09:11:00 em diante     => utiliza o horário real.
     */
    if j.id is not null and entrada_real is not null
       and entrada_real > ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and entrada_real < (
         ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         + make_interval(mins=>coalesce(e.tolerancia_entrada_minutos,0)+1)
       ) then
      entrada_calc:=(d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null
       and saida_real < ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and saida_real >= (
         ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         - make_interval(mins=>coalesce(e.tolerancia_saida_minutos,0))
       ) then
      saida_calc:=(d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    /* RC6.4 — movimentações podem atravessar vários dias.
       O efeito é calculado somente sobre os trechos da jornada prevista
       (antes e depois do intervalo), nunca sobre horas corridas. */
    dia_ini := d.data::timestamp at time zone coalesce(e.timezone,'America/Sao_Paulo');
    dia_fim := (d.data + 1)::timestamp at time zone coalesce(e.timezone,'America/Sao_Paulo');
    if j.id is not null and j.entrada is not null then
      seg1_ini := (d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      seg1_fim := (d.data+j.inicio_intervalo) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      seg2_ini := (d.data+j.fim_intervalo) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      seg2_fim := (d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo');
    else
      seg1_ini:=null; seg1_fim:=null; seg2_ini:=null; seg2_fim:=null;
    end if;

    select
      coalesce(sum(case when x.aprovado and x.efeito_calculo='descontar' then x.minutos_jornada else 0 end),0)::int,
      coalesce(sum(case when x.aprovado and x.efeito_calculo='abonar' then x.minutos_jornada else 0 end),0)::int,
      coalesce(bool_or(x.aprovado and x.efeito_calculo='credito'),false),
      coalesce(jsonb_agg(jsonb_build_object(
        'id',x.id,'inicio_em',x.inicio_em,'fim_em',x.fim_em,
        'classificacao',x.classificacao,'efeito',x.efeito_calculo,
        'status',x.status,'aprovado',x.aprovado,
        'minutos_jornada_dia',x.minutos_jornada
      ) order by x.inicio_em),'[]'::jsonb)
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from (
      select mj.*,
        case when j.id is null or mj.fim_em is null then 0 else
          greatest(0,round(extract(epoch from (least(mj.fim_em,seg1_fim)-greatest(mj.inicio_em,seg1_ini)))/60)::int)
          + greatest(0,round(extract(epoch from (least(mj.fim_em,seg2_fim)-greatest(mj.inicio_em,seg2_ini)))/60)::int)
        end as minutos_jornada
      from public.movimentacoes_jornada mj
      where mj.funcionario_id=f.id
        and mj.status<>'cancelada'
        and mj.fim_em is not null
        and mj.inicio_em < dia_fim
        and mj.fim_em > dia_ini
    ) x;

    /* Abono recompõe somente o que falta da carga prevista.
       Assim atestado não gera crédito positivo nem inclui almoço. */
    abono_mov:=least(abono_mov,greatest(0,previsto-trabalhado));

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then v_status_dia:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then v_status_dia:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif abono_mov>0 and trabalhado>=previsto then v_status_dia:='abonado'; saldo:=0; trabalhados:=trabalhados+1;
    elsif qtd=4 then v_status_dia:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then v_status_dia:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then v_status_dia:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then v_status_dia:='aguardando'; else v_status_dia:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0
           and coalesce(e.horas_extras_automaticas,false) is not true
           and coalesce(extra_autorizada,false) is not true then
          saldo:=0;
        end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',v_status_dia,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'data_inicio_apuracao',v_inicio_apuracao,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;

-- Faz a tela Movimentações localizar também lançamentos que atravessam
-- o período filtrado, e não apenas pela data de início.
create or replace function public.listar_movimentacoes_admin(p_inicio date,p_fim date,p_funcionario_id uuid default null,p_pendentes boolean default false)
returns table(
  id uuid,funcionario_id uuid,funcionario_nome text,matricula text,data_local date,inicio_em timestamptz,fim_em timestamptz,
  origem text,motivo_informado text,classificacao text,efeito_calculo text,status text,aprovado boolean,observacao_admin text
)
language plpgsql security definer set search_path=public as $$
declare emp uuid; tz text;
begin
  select p.empresa_id into emp from public.perfis p where p.id=auth.uid() and p.papel='administrador' and p.ativo=true;
  if emp is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  select coalesce(e.timezone,'America/Sao_Paulo') into tz from public.empresas e where e.id=emp;
  return query select m.id,m.funcionario_id,f.nome,f.matricula,m.data_local,m.inicio_em,m.fim_em,m.origem,m.motivo_informado,
    m.classificacao,m.efeito_calculo,m.status,m.aprovado,m.observacao_admin
  from public.movimentacoes_jornada m join public.funcionarios f on f.id=m.funcionario_id
  where m.empresa_id=emp
    and m.inicio_em < ((p_fim+1)::timestamp at time zone tz)
    and coalesce(m.fim_em,m.inicio_em) >= (p_inicio::timestamp at time zone tz)
    and (p_funcionario_id is null or m.funcionario_id=p_funcionario_id)
    and (not p_pendentes or m.efeito_calculo='pendente' or m.status='aberta')
  order by m.inicio_em desc;
end $$;

commit;
notify pgrst,'reload schema';
