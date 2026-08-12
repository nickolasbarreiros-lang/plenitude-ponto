begin;

-- RC3.2 — correção da solicitação de ajuste
-- A função possuía uma variável PL/pgSQL chamada "s" e também usava
-- "s" como alias da tabela solicitacoes_ajuste. Isso tornava
-- s.funcionario_id ambíguo no PostgreSQL.

create or replace function public.solicitar_ajuste_ponto(
  p_token text,
  p_data date,
  p_tipo public.tipo_marcacao,
  p_horario time,
  p_justificativa text
)
returns public.solicitacoes_ajuste
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_solicitacao public.solicitacoes_ajuste%rowtype;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  if p_data > (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Não é possível solicitar ajuste para uma data futura.';
  end if;

  if char_length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'Informe uma justificativa com pelo menos 10 caracteres.';
  end if;

  if exists (
    select 1
    from public.marcacoes as m
    where m.funcionario_id = v_funcionario.id
      and m.data_local = p_data
      and m.tipo = p_tipo
  ) then
    raise exception 'Essa marcação já existe. Para alterar um horário existente, procure o administrador.';
  end if;

  if exists (
    select 1
    from public.solicitacoes_ajuste as sa
    where sa.funcionario_id = v_funcionario.id
      and sa.data_marcacao = p_data
      and sa.tipo_marcacao = p_tipo
      and sa.status = 'pendente'
  ) then
    raise exception 'Já existe uma solicitação pendente para essa marcação.';
  end if;

  insert into public.solicitacoes_ajuste (
    empresa_id,
    funcionario_id,
    data_marcacao,
    tipo_marcacao,
    horario_solicitado,
    justificativa
  )
  values (
    v_funcionario.empresa_id,
    v_funcionario.id,
    p_data,
    p_tipo,
    p_horario,
    btrim(p_justificativa)
  )
  returning * into v_solicitacao;

  return v_solicitacao;
end;
$$;

revoke all on function public.solicitar_ajuste_ponto(
  text,
  date,
  public.tipo_marcacao,
  time,
  text
) from public;

grant execute on function public.solicitar_ajuste_ponto(
  text,
  date,
  public.tipo_marcacao,
  time,
  text
) to anon, authenticated;

commit;

notify pgrst, 'reload schema';
