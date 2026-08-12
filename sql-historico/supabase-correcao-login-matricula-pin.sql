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
