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
