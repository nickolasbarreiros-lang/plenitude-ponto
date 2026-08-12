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
