-- ============================================================
-- PLENITUDE PONTO RC6.5.3
-- AUTOATENDIMENTO NA TELA DE PONTO ABERTA PELO ADMINISTRADOR
-- ============================================================
-- Corrige o caso em que ponto.html é aberto com sessão administrativa.
-- Nesse modo ponto-pin.js não é carregado por segurança, portanto as ações
-- laterais precisam de RPCs administrativas próprias e auditadas.

begin;

create or replace function public.registrar_movimentacao_admin_agora(
  p_funcionario_id uuid,
  p_acao text,
  p_motivo text default null
)
returns public.movimentacoes_jornada
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa uuid;
  v_mov public.movimentacoes_jornada%rowtype;
  v_agora timestamptz:=clock_timestamp();
  v_hoje date:=(clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  select p.empresa_id into v_empresa
  from public.perfis p
  where p.id=auth.uid() and p.papel='administrador' and p.ativo=true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if not exists(
    select 1 from public.funcionarios f
    where f.id=p_funcionario_id and f.empresa_id=v_empresa
      and f.ativo=true and f.status<>'inativo'
  ) then
    raise exception 'Funcionário inválido ou inativo.';
  end if;

  if public.competencia_fechada(v_empresa,v_hoje) then
    raise exception 'A competência atual está fechada.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_funcionario_id::text||':movimentacao-admin',20260828));

  if p_acao='saida' then
    if char_length(btrim(coalesce(p_motivo,'')))<3 then
      raise exception 'Informe resumidamente o motivo da saída.';
    end if;

    if exists(
      select 1 from public.movimentacoes_jornada mj
      where mj.funcionario_id=p_funcionario_id
        and mj.data_local=v_hoje
        and mj.status='aberta'
    ) then
      raise exception 'Já existe uma saída temporária de hoje aguardando retorno.';
    end if;

    insert into public.movimentacoes_jornada(
      empresa_id,funcionario_id,data_local,inicio_em,origem,
      motivo_informado,status,criado_por
    ) values(
      v_empresa,p_funcionario_id,v_hoje,v_agora,'administrador',
      btrim(p_motivo),'aberta',auth.uid()
    ) returning * into v_mov;

    insert into public.logs_auditoria(
      empresa_id,usuario_id,tabela,registro_id,acao,dados,origem,descricao
    ) values(
      v_empresa,auth.uid(),'movimentacoes_jornada',v_mov.id::text,
      'SAIDA_TEMPORARIA_ADMIN',
      jsonb_build_object('funcionario_id',p_funcionario_id,'inicio_em',v_mov.inicio_em,'motivo',v_mov.motivo_informado),
      'administrador','Saída temporária registrada na tela de ponto pelo administrador'
    );

  elsif p_acao='retorno' then
    select mj.* into v_mov
    from public.movimentacoes_jornada mj
    where mj.funcionario_id=p_funcionario_id
      and mj.data_local=v_hoje
      and mj.status='aberta'
    order by mj.inicio_em desc
    limit 1
    for update;

    if v_mov.id is null then
      raise exception 'Não existe saída temporária aberta hoje.';
    end if;

    update public.movimentacoes_jornada mj
       set fim_em=v_agora,status='encerrada',atualizado_em=v_agora
     where mj.id=v_mov.id
    returning mj.* into v_mov;

    insert into public.logs_auditoria(
      empresa_id,usuario_id,tabela,registro_id,acao,dados,origem,descricao
    ) values(
      v_empresa,auth.uid(),'movimentacoes_jornada',v_mov.id::text,
      'RETORNO_TEMPORARIO_ADMIN',
      jsonb_build_object('funcionario_id',p_funcionario_id,'fim_em',v_mov.fim_em),
      'administrador','Retorno temporário registrado na tela de ponto pelo administrador'
    );
  else
    raise exception 'Ação inválida.';
  end if;

  return v_mov;
end;
$$;

revoke all on function public.registrar_movimentacao_admin_agora(uuid,text,text) from public,anon;
grant execute on function public.registrar_movimentacao_admin_agora(uuid,text,text) to authenticated;

create or replace function public.solicitar_ajuste_admin_em_nome_funcionario(
  p_funcionario_id uuid,
  p_modalidade text,
  p_data date,
  p_tipo public.tipo_marcacao,
  p_horario time,
  p_justificativa text
)
returns public.solicitacoes_ajuste
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa uuid;
  v_marcacao public.marcacoes%rowtype;
  v_solicitacao public.solicitacoes_ajuste%rowtype;
  v_horario_original time;
begin
  select p.empresa_id into v_empresa
  from public.perfis p
  where p.id=auth.uid() and p.papel='administrador' and p.ativo=true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if not exists(
    select 1 from public.funcionarios f
    where f.id=p_funcionario_id and f.empresa_id=v_empresa
      and f.ativo=true and f.status<>'inativo'
  ) then
    raise exception 'Funcionário inválido ou inativo.';
  end if;

  if p_modalidade not in ('inclusao','correcao') then
    raise exception 'Modalidade inválida.';
  end if;

  if p_data>(clock_timestamp() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Não é possível solicitar ajuste para uma data futura.';
  end if;

  if public.competencia_fechada(v_empresa,p_data) then
    raise exception 'A competência desta marcação está fechada.';
  end if;

  if char_length(btrim(coalesce(p_justificativa,'')))<10 then
    raise exception 'Informe uma justificativa com pelo menos 10 caracteres.';
  end if;

  if exists(
    select 1 from public.solicitacoes_ajuste sa
    where sa.funcionario_id=p_funcionario_id
      and sa.data_marcacao=p_data
      and sa.tipo_marcacao=p_tipo
      and sa.status='pendente'
  ) then
    raise exception 'Já existe uma solicitação pendente para essa marcação.';
  end if;

  select m.* into v_marcacao
  from public.marcacoes m
  where m.funcionario_id=p_funcionario_id
    and m.data_local=p_data
    and m.tipo=p_tipo
  order by m.registrado_em
  limit 1;

  if p_modalidade='inclusao' then
    if v_marcacao.id is not null then
      raise exception 'Essa marcação já existe. Use a opção de correção de horário.';
    end if;

    insert into public.solicitacoes_ajuste(
      empresa_id,funcionario_id,data_marcacao,tipo_marcacao,
      horario_solicitado,justificativa,modalidade
    ) values(
      v_empresa,p_funcionario_id,p_data,p_tipo,
      p_horario,btrim(p_justificativa),'inclusao'
    ) returning * into v_solicitacao;
  else
    if v_marcacao.id is null then
      raise exception 'Essa marcação não existe. Use a opção de marcação não registrada.';
    end if;

    v_horario_original:=(v_marcacao.registrado_em at time zone 'America/Sao_Paulo')::time;

    if date_trunc('minute',v_horario_original)=date_trunc('minute',p_horario) then
      raise exception 'O horário solicitado é igual ao horário atualmente registrado.';
    end if;

    insert into public.solicitacoes_ajuste(
      empresa_id,funcionario_id,data_marcacao,tipo_marcacao,
      horario_solicitado,justificativa,modalidade,
      marcacao_original_id,horario_original
    ) values(
      v_empresa,p_funcionario_id,p_data,p_tipo,
      p_horario,btrim(p_justificativa),'correcao',
      v_marcacao.id,v_horario_original
    ) returning * into v_solicitacao;
  end if;

  insert into public.logs_auditoria(
    empresa_id,usuario_id,tabela,registro_id,acao,dados,origem,descricao
  ) values(
    v_empresa,auth.uid(),'solicitacoes_ajuste',v_solicitacao.id::text,
    case when p_modalidade='correcao' then 'CORRECAO_SOLICITADA_ADMIN' else 'AJUSTE_SOLICITADO_ADMIN' end,
    jsonb_build_object(
      'funcionario_id',p_funcionario_id,
      'modalidade',p_modalidade,
      'data',p_data,
      'tipo',p_tipo,
      'horario_original',v_horario_original,
      'horario_solicitado',p_horario
    ),
    'administrador','Solicitação criada em nome do funcionário pela tela de ponto administrativa'
  );

  return v_solicitacao;
end;
$$;

revoke all on function public.solicitar_ajuste_admin_em_nome_funcionario(uuid,text,date,public.tipo_marcacao,time,text) from public,anon;
grant execute on function public.solicitar_ajuste_admin_em_nome_funcionario(uuid,text,date,public.tipo_marcacao,time,text) to authenticated;

commit;
notify pgrst,'reload schema';
