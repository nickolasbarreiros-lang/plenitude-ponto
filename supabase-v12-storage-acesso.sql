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
