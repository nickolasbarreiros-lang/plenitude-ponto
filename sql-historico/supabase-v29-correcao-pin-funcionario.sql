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
