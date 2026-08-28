-- ============================================================
-- PLENITUDE PONTO RC6.5
-- CORREÇÃO DE HORÁRIO DE MARCAÇÃO PELO FLUXO DE AJUSTES
-- ============================================================
-- Permite ao funcionário:
--   a) solicitar inclusão de marcação não realizada (fluxo existente);
--   b) solicitar correção do horário de uma marcação já existente.
--
-- Ao aprovar uma CORREÇÃO:
--   - a marcação original NÃO é apagada;
--   - o mesmo ID é preservado;
--   - registrado_em é alterado para o horário aprovado;
--   - ajustada=true;
--   - a auditoria registra horário anterior e novo.
-- ============================================================

begin;

alter table public.solicitacoes_ajuste
  add column if not exists modalidade text not null default 'inclusao',
  add column if not exists marcacao_original_id bigint references public.marcacoes(id) on delete set null,
  add column if not exists horario_original time;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='solicitacoes_ajuste_modalidade_check'
      and conrelid='public.solicitacoes_ajuste'::regclass
  ) then
    alter table public.solicitacoes_ajuste
      add constraint solicitacoes_ajuste_modalidade_check
      check (modalidade in ('inclusao','correcao'));
  end if;
end $$;

create index if not exists idx_solicitacoes_ajuste_original
  on public.solicitacoes_ajuste(marcacao_original_id)
  where marcacao_original_id is not null;

-- Nova RPC específica para corrigir marcação existente.
create or replace function public.solicitar_correcao_ponto(
  p_token text,
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
  v_funcionario public.funcionarios%rowtype;
  v_marcacao public.marcacoes%rowtype;
  v_solicitacao public.solicitacoes_ajuste%rowtype;
  v_horario_original time;
begin
  v_funcionario:=public.funcionario_por_token(p_token);

  if p_data>(clock_timestamp() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Não é possível solicitar correção para uma data futura.';
  end if;

  if char_length(btrim(coalesce(p_justificativa,'')))<10 then
    raise exception 'Informe uma justificativa com pelo menos 10 caracteres.';
  end if;

  select m.*
    into v_marcacao
  from public.marcacoes m
  where m.funcionario_id=v_funcionario.id
    and m.data_local=p_data
    and m.tipo=p_tipo
  order by m.registrado_em
  limit 1;

  if v_marcacao.id is null then
    raise exception 'Essa marcação não existe. Use a opção de marcação não registrada.';
  end if;

  v_horario_original:=(v_marcacao.registrado_em at time zone 'America/Sao_Paulo')::time;

  if date_trunc('minute',v_horario_original)=date_trunc('minute',p_horario) then
    raise exception 'O horário solicitado é igual ao horário atualmente registrado.';
  end if;

  if exists(
    select 1
    from public.solicitacoes_ajuste sa
    where sa.funcionario_id=v_funcionario.id
      and sa.data_marcacao=p_data
      and sa.tipo_marcacao=p_tipo
      and sa.status='pendente'
  ) then
    raise exception 'Já existe uma solicitação pendente para essa marcação.';
  end if;

  insert into public.solicitacoes_ajuste(
    empresa_id,funcionario_id,data_marcacao,tipo_marcacao,
    horario_solicitado,justificativa,modalidade,
    marcacao_original_id,horario_original
  )
  values(
    v_funcionario.empresa_id,v_funcionario.id,p_data,p_tipo,
    p_horario,btrim(p_justificativa),'correcao',
    v_marcacao.id,v_horario_original
  )
  returning * into v_solicitacao;

  insert into public.logs_auditoria(
    empresa_id,usuario_id,tabela,registro_id,acao,dados,origem,descricao
  )
  values(
    v_funcionario.empresa_id,null,'solicitacoes_ajuste',v_solicitacao.id::text,
    'CORRECAO_SOLICITADA',
    jsonb_build_object(
      'funcionario_id',v_funcionario.id,
      'marcacao_id',v_marcacao.id,
      'data',p_data,
      'tipo',p_tipo,
      'horario_original',v_horario_original,
      'horario_solicitado',p_horario
    ),
    'funcionario',
    'Funcionário solicitou correção do horário de uma marcação existente'
  );

  return v_solicitacao;
end $$;

revoke all on function public.solicitar_correcao_ponto(text,date,public.tipo_marcacao,time,text)
from public;

grant execute on function public.solicitar_correcao_ponto(text,date,public.tipo_marcacao,time,text)
to anon,authenticated;

-- Listagem administrativa enriquecida sem quebrar consumidores antigos.
create or replace function public.listar_ajustes_admin_v2(p_status text default null)
returns table(
  id uuid,funcionario_id uuid,funcionario_nome text,matricula text,
  data_marcacao date,tipo_marcacao public.tipo_marcacao,
  horario_solicitado time,horario_original time,modalidade text,
  marcacao_original_id bigint,
  justificativa text,status text,resposta_administrador text,
  criado_em timestamptz,analisado_em timestamptz
)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare v_empresa uuid;
begin
  select p.empresa_id into v_empresa
  from public.perfis p
  where p.id=auth.uid() and p.papel='administrador' and p.ativo=true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  return query
  select sa.id,sa.funcionario_id,f.nome,f.matricula,
         sa.data_marcacao,sa.tipo_marcacao,
         sa.horario_solicitado,sa.horario_original,sa.modalidade,
         sa.marcacao_original_id,
         sa.justificativa,sa.status,sa.resposta_administrador,
         sa.criado_em,sa.analisado_em
  from public.solicitacoes_ajuste sa
  join public.funcionarios f on f.id=sa.funcionario_id
  where sa.empresa_id=v_empresa
    and (p_status is null or p_status='' or sa.status=p_status)
  order by case when sa.status='pendente' then 0 else 1 end,sa.criado_em desc;
end $$;

revoke all on function public.listar_ajustes_admin_v2(text) from public,anon;
grant execute on function public.listar_ajustes_admin_v2(text) to authenticated;

-- Aprovação passa a saber incluir ou corrigir.
create or replace function public.analisar_ajuste_ponto(
  p_solicitacao_id uuid,
  p_decisao text,
  p_resposta text default null
)
returns public.solicitacoes_ajuste
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa uuid;
  v_s public.solicitacoes_ajuste%rowtype;
  v_m public.marcacoes%rowtype;
  v_marcacao_id bigint;
  v_instante timestamptz;
  v_anterior timestamptz;
  v_ordem int;
  v_prev timestamptz;
  v_next timestamptz;
begin
  select p.empresa_id into v_empresa
  from public.perfis p
  where p.id=auth.uid() and p.papel='administrador' and p.ativo=true;

  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  if p_decisao not in ('aprovada','rejeitada') then raise exception 'Decisão inválida.'; end if;

  select * into v_s
  from public.solicitacoes_ajuste sa
  where sa.id=p_solicitacao_id and sa.empresa_id=v_empresa
  for update;

  if v_s.id is null then raise exception 'Solicitação não encontrada.'; end if;
  if v_s.status<>'pendente' then raise exception 'Esta solicitação já foi analisada.'; end if;
  if public.competencia_fechada(v_empresa,v_s.data_marcacao) then
    raise exception 'A competência desta marcação está fechada.';
  end if;

  if p_decisao='aprovada' then
    v_instante:=(v_s.data_marcacao+v_s.horario_solicitado) at time zone 'America/Sao_Paulo';

    if coalesce(v_s.modalidade,'inclusao')='correcao' then
      select * into v_m
      from public.marcacoes m
      where m.id=v_s.marcacao_original_id
        and m.funcionario_id=v_s.funcionario_id
        and m.data_local=v_s.data_marcacao
        and m.tipo=v_s.tipo_marcacao
      for update;

      if v_m.id is null then
        raise exception 'A marcação original não existe mais. A correção foi interrompida.';
      end if;

      v_ordem:=case v_s.tipo_marcacao
        when 'entrada' then 1
        when 'inicio_intervalo' then 2
        when 'fim_intervalo' then 3
        when 'saida' then 4 end;

      select max(m.registrado_em) into v_prev
      from public.marcacoes m
      where m.funcionario_id=v_s.funcionario_id
        and m.data_local=v_s.data_marcacao
        and case m.tipo when 'entrada' then 1 when 'inicio_intervalo' then 2 when 'fim_intervalo' then 3 when 'saida' then 4 end < v_ordem;

      select min(m.registrado_em) into v_next
      from public.marcacoes m
      where m.funcionario_id=v_s.funcionario_id
        and m.data_local=v_s.data_marcacao
        and case m.tipo when 'entrada' then 1 when 'inicio_intervalo' then 2 when 'fim_intervalo' then 3 when 'saida' then 4 end > v_ordem;

      if v_prev is not null and v_instante<=v_prev then
        raise exception 'O horário solicitado conflita com a marcação anterior.';
      end if;
      if v_next is not null and v_instante>=v_next then
        raise exception 'O horário solicitado conflita com a marcação seguinte.';
      end if;

      v_anterior:=v_m.registrado_em;
      update public.marcacoes
      set registrado_em=v_instante,
          ajustada=true,
          observacao=concat_ws(' | ',nullif(observacao,''),
            'Horário corrigido pela solicitação '||v_s.id::text||
            '. Justificativa: '||v_s.justificativa)
      where id=v_m.id
      returning id into v_marcacao_id;

      insert into public.logs_auditoria(
        empresa_id,usuario_id,tabela,registro_id,acao,dados,dados_novos,origem,descricao
      )
      values(
        v_empresa,auth.uid(),'marcacoes',v_marcacao_id::text,'HORARIO_CORRIGIDO',
        jsonb_build_object(
          'registrado_em',v_anterior,
          'horario_local',(v_anterior at time zone 'America/Sao_Paulo')::time,
          'solicitacao_id',v_s.id
        ),
        jsonb_build_object(
          'registrado_em',v_instante,
          'horario_local',v_s.horario_solicitado,
          'solicitacao_id',v_s.id,
          'justificativa',v_s.justificativa
        ),
        'ajuste_aprovado',
        'Horário de marcação existente corrigido após aprovação administrativa'
      );
    else
      if exists(
        select 1 from public.marcacoes m
        where m.funcionario_id=v_s.funcionario_id
          and m.data_local=v_s.data_marcacao
          and m.tipo=v_s.tipo_marcacao
      ) then
        raise exception 'A marcação solicitada já existe e a aprovação foi interrompida.';
      end if;

      insert into public.marcacoes(
        empresa_id,funcionario_id,tipo,registrado_em,data_local,origem,
        observacao,criado_por,ajustada
      )
      values(
        v_s.empresa_id,v_s.funcionario_id,v_s.tipo_marcacao,v_instante,
        v_s.data_marcacao,'ajuste_aprovado',
        'Incluída pela solicitação '||v_s.id::text||'. Justificativa: '||v_s.justificativa,
        auth.uid(),true
      )
      returning id into v_marcacao_id;
    end if;
  end if;

  update public.solicitacoes_ajuste
  set status=p_decisao,
      resposta_administrador=nullif(btrim(coalesce(p_resposta,'')),''),
      marcacao_gerada_id=v_marcacao_id,
      analisado_por=auth.uid(),
      analisado_em=clock_timestamp()
  where id=v_s.id
  returning * into v_s;

  insert into public.logs_auditoria(
    empresa_id,usuario_id,tabela,registro_id,acao,dados,origem,descricao
  )
  values(
    v_empresa,auth.uid(),'solicitacoes_ajuste',v_s.id::text,
    upper(p_decisao),
    jsonb_build_object(
      'funcionario_id',v_s.funcionario_id,
      'data',v_s.data_marcacao,
      'tipo',v_s.tipo_marcacao,
      'modalidade',v_s.modalidade,
      'horario_original',v_s.horario_original,
      'horario_solicitado',v_s.horario_solicitado,
      'marcacao_id',v_marcacao_id
    ),
    'web',
    case when v_s.modalidade='correcao'
      then 'Solicitação de correção de horário analisada'
      else 'Solicitação de inclusão de marcação analisada' end
  );

  return v_s;
end $$;

commit;

notify pgrst,'reload schema';
