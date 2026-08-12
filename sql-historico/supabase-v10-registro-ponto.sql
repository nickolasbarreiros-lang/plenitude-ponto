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
