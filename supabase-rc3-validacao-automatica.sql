begin;

-- Plenitude Ponto 1.0.0 RC3
-- Validação automática dos itens do checklist que podem ser comprovados
-- diretamente pelo banco de dados. Itens visuais ou que dependem de ação
-- humana continuam manuais.

create or replace function public.validar_homologacao_automatica_admin()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_funcionario public.funcionarios%rowtype;
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_checks jsonb := '{}'::jsonb;
  v_tipos public.tipo_marcacao[];
  v_qtd integer;
  v_mov_aberta integer;
  v_mov_encerrada integer;
  v_aj_pendentes integer;
  v_aj_aprovados integer;
  v_aj_rejeitados integer;
  v_auditoria integer;
  v_fechado boolean;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis as p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  select f.*
    into v_funcionario
  from public.funcionarios as f
  where f.empresa_id = v_empresa
    and f.matricula = '999'
  limit 1;

  -- Preparação
  v_checks := v_checks || jsonb_build_object(
    'diagnostico_tecnico',
    jsonb_build_object(
      'ok', public.diagnostico_homologacao_admin()->>'status' = 'aprovado',
      'detalhe', 'Diagnóstico técnico consultado no Supabase.'
    ),
    'funcionario_999',
    jsonb_build_object(
      'ok', v_funcionario.id is not null,
      'detalhe', coalesce(v_funcionario.nome, 'Funcionário 999 não encontrado.')
    ),
    'pin_999',
    jsonb_build_object(
      'ok', v_funcionario.pin_hash is not null,
      'detalhe', case when v_funcionario.pin_hash is not null then 'PIN configurado.' else 'PIN não configurado.' end
    ),
    'acesso_999',
    jsonb_build_object(
      'ok', coalesce(v_funcionario.ativo,false) and coalesce(v_funcionario.acesso_ponto_ativo,false),
      'detalhe', case when coalesce(v_funcionario.acesso_ponto_ativo,false) then 'Acesso ativo.' else 'Acesso bloqueado.' end
    ),
    'dispositivo_autorizado',
    jsonb_build_object(
      'ok', exists(
        select 1 from public.dispositivos_ponto as d
        where d.empresa_id = v_empresa and d.ativo = true
      ),
      'detalhe', 'Verificação de dispositivo ativo da empresa.'
    )
  );

  if v_funcionario.id is null then
    return jsonb_build_object(
      'gerado_em', clock_timestamp(),
      'funcionario_id', null,
      'data', v_hoje,
      'checks', v_checks
    );
  end if;

  select count(*)::integer,
         array_agg(m.tipo order by m.registrado_em, m.id)
    into v_qtd, v_tipos
  from public.marcacoes as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_hoje;

  -- Jornada
  v_checks := v_checks || jsonb_build_object(
    'entrada_registrada',
    jsonb_build_object(
      'ok', 'entrada'::public.tipo_marcacao = any(coalesce(v_tipos, array[]::public.tipo_marcacao[])),
      'detalhe', format('%s marcação(ões) hoje.', coalesce(v_qtd,0))
    ),
    'almoco_registrado',
    jsonb_build_object(
      'ok', 'inicio_intervalo'::public.tipo_marcacao = any(coalesce(v_tipos, array[]::public.tipo_marcacao[])),
      'detalhe', 'Início do intervalo consultado.'
    ),
    'retorno_registrado',
    jsonb_build_object(
      'ok', 'fim_intervalo'::public.tipo_marcacao = any(coalesce(v_tipos, array[]::public.tipo_marcacao[])),
      'detalhe', 'Retorno do intervalo consultado.'
    ),
    'saida_registrada',
    jsonb_build_object(
      'ok', 'saida'::public.tipo_marcacao = any(coalesce(v_tipos, array[]::public.tipo_marcacao[])),
      'detalhe', 'Saída final consultada.'
    ),
    'ordem_jornada',
    jsonb_build_object(
      'ok', coalesce(v_tipos, array[]::public.tipo_marcacao[]) <@ array[
        'entrada'::public.tipo_marcacao,
        'inicio_intervalo'::public.tipo_marcacao,
        'fim_intervalo'::public.tipo_marcacao,
        'saida'::public.tipo_marcacao
      ]
      and (
        v_qtd = 0
        or v_tipos = array[
          'entrada'::public.tipo_marcacao,
          'inicio_intervalo'::public.tipo_marcacao,
          'fim_intervalo'::public.tipo_marcacao,
          'saida'::public.tipo_marcacao
        ][1:v_qtd]
      ),
      'detalhe', 'Sequência esperada: Entrada → Almoço → Retorno → Saída.'
    ),
    'jornada_concluida',
    jsonb_build_object(
      'ok', v_qtd = 4 and v_tipos = array[
        'entrada'::public.tipo_marcacao,
        'inicio_intervalo'::public.tipo_marcacao,
        'fim_intervalo'::public.tipo_marcacao,
        'saida'::public.tipo_marcacao
      ],
      'detalhe', format('%s de 4 marcações válidas.', coalesce(v_qtd,0))
    ),
    'sem_quinta_marcacao',
    jsonb_build_object(
      'ok', coalesce(v_qtd,0) <= 4,
      'detalhe', format('%s marcação(ões) encontradas hoje.', coalesce(v_qtd,0))
    )
  );

  -- Movimentações temporárias
  select count(*) filter (where m.status = 'aberta')::integer,
         count(*) filter (where m.status = 'encerrada')::integer
    into v_mov_aberta, v_mov_encerrada
  from public.movimentacoes_jornada as m
  where m.funcionario_id = v_funcionario.id
    and m.data_local = v_hoje;

  v_checks := v_checks || jsonb_build_object(
    'movimentacao_saida',
    jsonb_build_object(
      'ok', (v_mov_aberta + v_mov_encerrada) > 0,
      'detalhe', format('%s movimentação(ões) hoje.', v_mov_aberta + v_mov_encerrada)
    ),
    'movimentacao_fora',
    jsonb_build_object(
      'ok', v_mov_aberta > 0,
      'detalhe', format('%s saída(s) aguardando retorno.', v_mov_aberta)
    ),
    'movimentacao_retorno',
    jsonb_build_object(
      'ok', v_mov_encerrada > 0,
      'detalhe', format('%s movimentação(ões) encerrada(s).', v_mov_encerrada)
    ),
    'movimentacao_classificada',
    jsonb_build_object(
      'ok', exists(
        select 1
        from public.movimentacoes_jornada as m
        where m.funcionario_id = v_funcionario.id
          and m.classificacao is not null
          and m.efeito_calculo <> 'pendente'
      ),
      'detalhe', 'Classificação e efeito administrativo consultados.'
    )
  );

  -- Ajustes
  select count(*) filter (where s.status = 'pendente')::integer,
         count(*) filter (where s.status = 'aprovada')::integer,
         count(*) filter (where s.status = 'rejeitada')::integer
    into v_aj_pendentes, v_aj_aprovados, v_aj_rejeitados
  from public.solicitacoes_ajuste as s
  where s.funcionario_id = v_funcionario.id;

  v_checks := v_checks || jsonb_build_object(
    'ajuste_solicitado',
    jsonb_build_object(
      'ok', (v_aj_pendentes + v_aj_aprovados + v_aj_rejeitados) > 0,
      'detalhe', format('%s solicitação(ões) encontradas.', v_aj_pendentes + v_aj_aprovados + v_aj_rejeitados)
    ),
    'ajuste_aprovado',
    jsonb_build_object(
      'ok', v_aj_aprovados > 0,
      'detalhe', format('%s solicitação(ões) aprovada(s).', v_aj_aprovados)
    ),
    'ajuste_rejeitado',
    jsonb_build_object(
      'ok', v_aj_rejeitados > 0,
      'detalhe', format('%s solicitação(ões) rejeitada(s).', v_aj_rejeitados)
    ),
    'ajuste_refletido',
    jsonb_build_object(
      'ok', exists(
        select 1
        from public.solicitacoes_ajuste as s
        join public.marcacoes as m on m.id = s.marcacao_gerada_id
        where s.funcionario_id = v_funcionario.id
          and s.status = 'aprovada'
      ),
      'detalhe', 'Marcação gerada por ajuste aprovado.'
    )
  );

  -- Auditoria
  select count(*)::integer
    into v_auditoria
  from public.logs_auditoria as l
  where l.empresa_id = v_empresa
    and (
      l.registro_id = v_funcionario.id::text
      or coalesce(l.dados::text,'') like '%' || v_funcionario.id::text || '%'
      or coalesce(l.dados_novos::text,'') like '%' || v_funcionario.id::text || '%'
    );

  v_checks := v_checks || jsonb_build_object(
    'auditoria_funcionario',
    jsonb_build_object(
      'ok', v_auditoria > 0,
      'detalhe', format('%s evento(s) relacionado(s) ao funcionário teste.', v_auditoria)
    ),
    'banco_horas_disponivel',
    jsonb_build_object(
      'ok', to_regprocedure('public.banco_horas_funcionario_token(text,date,date)') is not null,
      'detalhe', 'RPC do banco de horas instalada.'
    ),
    'backup_disponivel',
    jsonb_build_object(
      'ok', to_regclass('public.funcionarios') is not null
            and to_regclass('public.marcacoes') is not null
            and to_regclass('public.logs_auditoria') is not null,
      'detalhe', 'Estruturas necessárias para exportação disponíveis.'
    )
  );

  -- Fechamento da competência atual
  select exists(
    select 1
    from public.fechamentos_mensais as fm
    where fm.empresa_id = v_empresa
      and fm.ano = extract(year from v_hoje)::integer
      and fm.mes = extract(month from v_hoje)::integer
      and fm.status = 'fechada'
  ) into v_fechado;

  v_checks := v_checks || jsonb_build_object(
    'competencia_fechada',
    jsonb_build_object(
      'ok', v_fechado,
      'detalhe', case when v_fechado then 'Competência atual fechada.' else 'Competência atual está aberta.' end
    ),
    'competencia_reaberta',
    jsonb_build_object(
      'ok', exists(
        select 1
        from public.logs_auditoria as l
        where l.empresa_id = v_empresa
          and upper(coalesce(l.acao,'')) like '%REABR%'
      ),
      'detalhe', 'Evento de reabertura consultado na auditoria.'
    )
  );

  return jsonb_build_object(
    'gerado_em', clock_timestamp(),
    'funcionario_id', v_funcionario.id,
    'data', v_hoje,
    'checks', v_checks
  );
end;
$$;

revoke all on function public.validar_homologacao_automatica_admin()
from public, anon;

grant execute on function public.validar_homologacao_automatica_admin()
to authenticated;

commit;

notify pgrst, 'reload schema';
