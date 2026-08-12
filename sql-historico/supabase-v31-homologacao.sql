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
    insert into public.funcionarios(empresa_id,nome,cargo,matricula,carga_semanal_minutos,ativo,status,acesso_ponto_ativo,pin_hash,exigir_troca_pin,tentativas_pin)
    values(v_empresa,'TESTE HOMOLOGAÇÃO','Funcionário de testes','999',2640,true,'ativo',true,extensions.crypt('9999',extensions.gen_salt('bf',10)),false,0)
    returning id into v_id;
  else
    update public.funcionarios f set nome='TESTE HOMOLOGAÇÃO',cargo='Funcionário de testes',ativo=true,status='ativo',
      acesso_ponto_ativo=true,pin_hash=extensions.crypt('9999',extensions.gen_salt('bf',10)),exigir_troca_pin=false,
      tentativas_pin=0,bloqueado_ate=null where f.id=v_id;
  end if;

  if not exists(select 1 from public.jornadas j where j.funcionario_id=v_id) then
    insert into public.jornadas(empresa_id,funcionario_id,dia_semana,entrada,inicio_intervalo,fim_intervalo,saida,ativo)
    select v_empresa,v_id,d,'09:00'::time,'13:00'::time,'13:30'::time,
      case when d=3 then '18:00'::time when d=4 then '18:30'::time when d=5 then '17:00'::time else '19:00'::time end,true
    from generate_series(1,5) d;
  end if;

  insert into public.logs_auditoria(empresa_id,usuario_id,acao,tabela,registro_id,dados_novos)
  values(v_empresa,auth.uid(),'HOMOLOGACAO_CRIADA','funcionarios',v_id::text,jsonb_build_object('matricula','999'));

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
  update public.funcionarios f set tentativas_pin=0,bloqueado_ate=null,ultimo_acesso_em=null,
    acesso_ponto_ativo=true,pin_hash=extensions.crypt('9999',extensions.gen_salt('bf',10)),exigir_troca_pin=false where f.id=v_id;

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
