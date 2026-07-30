begin;

create or replace function public.diagnostico_homologacao_admin()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_funcionario record;
  v_checks jsonb := '[]'::jsonb;
  v_ok boolean;
  v_total integer := 0;
  v_aprovados integer := 0;
begin
  select p.empresa_id into v_empresa
  from public.perfis p
  where p.id = auth.uid() and p.papel = 'administrador' and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  -- Tabelas essenciais
  foreach v_ok in array array[
    to_regclass('public.funcionarios') is not null,
    to_regclass('public.jornadas') is not null,
    to_regclass('public.marcacoes') is not null,
    to_regclass('public.solicitacoes_ajuste') is not null,
    to_regclass('public.movimentacoes_jornada') is not null,
    to_regclass('public.dispositivos_ponto') is not null,
    to_regclass('public.logs_auditoria') is not null
  ] loop
    null;
  end loop;

  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Banco','item','Tabela funcionários','ok',to_regclass('public.funcionarios') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Banco','item','Tabela jornadas','ok',to_regclass('public.jornadas') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Banco','item','Tabela marcações','ok',to_regclass('public.marcacoes') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Banco','item','Tabela ajustes','ok',to_regclass('public.solicitacoes_ajuste') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Banco','item','Tabela movimentações','ok',to_regclass('public.movimentacoes_jornada') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Segurança','item','Tabela dispositivos','ok',to_regclass('public.dispositivos_ponto') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Segurança','item','Tabela auditoria','ok',to_regclass('public.logs_auditoria') is not null));

  -- RPCs essenciais
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','RPC','item','Login por dispositivo','ok',to_regprocedure('public.login_funcionario_pin_dispositivo(text,text,text,text)') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','RPC','item','Registro de ponto por dispositivo','ok',to_regprocedure('public.registrar_ponto_dispositivo(text,text,text)') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','RPC','item','Banco de horas do funcionário','ok',to_regprocedure('public.banco_horas_funcionario_token(text,date,date)') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','RPC','item','Listar meus ajustes','ok',to_regprocedure('public.listar_meus_ajustes(text)') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','RPC','item','Criar funcionário de homologação','ok',to_regprocedure('public.criar_funcionario_homologacao_admin()') is not null));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','RPC','item','Resetar homologação','ok',to_regprocedure('public.resetar_funcionario_homologacao_admin()') is not null));

  select f.id, f.nome, f.matricula, f.ativo, f.acesso_ponto_ativo, (f.pin_hash is not null) as pin_configurado
  into v_funcionario
  from public.funcionarios f
  where f.empresa_id = v_empresa and f.matricula = '999'
  limit 1;

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'grupo','Homologação','item','Funcionário 999 criado','ok',v_funcionario.id is not null,
    'detalhe',coalesce(v_funcionario.nome,'Não criado')
  ));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Homologação','item','PIN do funcionário 999 configurado','ok',coalesce(v_funcionario.pin_configurado,false)));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('grupo','Homologação','item','Acesso do funcionário 999 ativo','ok',coalesce(v_funcionario.ativo,false) and coalesce(v_funcionario.acesso_ponto_ativo,false)));

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'grupo','Segurança','item','Existe dispositivo autorizado','ok',
    exists(select 1 from public.dispositivos_ponto d where d.empresa_id = v_empresa and d.ativo = true)
  ));

  select count(*), count(*) filter (where (x->>'ok')::boolean)
  into v_total, v_aprovados
  from jsonb_array_elements(v_checks) x;

  return jsonb_build_object(
    'gerado_em', clock_timestamp(),
    'total', v_total,
    'aprovados', v_aprovados,
    'pendentes', v_total - v_aprovados,
    'status', case when v_total = v_aprovados then 'aprovado' else 'atencao' end,
    'checks', v_checks
  );
end;
$$;

revoke all on function public.diagnostico_homologacao_admin() from public, anon;
grant execute on function public.diagnostico_homologacao_admin() to authenticated;

commit;
notify pgrst, 'reload schema';
