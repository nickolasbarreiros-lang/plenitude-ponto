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
