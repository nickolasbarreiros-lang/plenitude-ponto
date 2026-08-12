begin;

create or replace function public.status_movimentacao_funcionario(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_aberta public.movimentacoes_jornada%rowtype;
  v_pendencias integer := 0;
  v_mais_antiga date;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  select mj.*
    into v_aberta
  from public.movimentacoes_jornada mj
  where mj.funcionario_id = v_funcionario.id
    and mj.data_local = v_hoje
    and mj.status = 'aberta'
  order by mj.inicio_em desc
  limit 1;

  select count(*)::integer, min(mj.data_local)
    into v_pendencias, v_mais_antiga
  from public.movimentacoes_jornada mj
  where mj.funcionario_id = v_funcionario.id
    and mj.status = 'aberta'
    and mj.data_local < v_hoje;

  return jsonb_build_object(
    'data_servidor', v_hoje,
    'fora_da_loja', v_aberta.id is not null,
    'movimentacao_aberta', case
      when v_aberta.id is null then null
      else jsonb_build_object(
        'id', v_aberta.id,
        'data_local', v_aberta.data_local,
        'inicio_em', v_aberta.inicio_em,
        'motivo_informado', v_aberta.motivo_informado,
        'status', v_aberta.status
      )
    end,
    'pendencias_antigas', v_pendencias,
    'pendencia_mais_antiga', v_mais_antiga
  );
end;
$$;

revoke all on function public.status_movimentacao_funcionario(text) from public;
grant execute on function public.status_movimentacao_funcionario(text) to anon, authenticated;

commit;
notify pgrst, 'reload schema';
