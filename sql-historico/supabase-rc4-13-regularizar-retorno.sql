begin;

-- RC4.13 — regularização administrativa de saída temporária sem retorno

create or replace function public.regularizar_retorno_movimentacao_admin(
  p_id uuid,
  p_fim_em timestamptz,
  p_observacao text default null
)
returns public.movimentacoes_jornada
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_mov public.movimentacoes_jornada%rowtype;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  select mj.*
    into v_mov
  from public.movimentacoes_jornada mj
  where mj.id = p_id
    and mj.empresa_id = v_empresa
  for update;

  if v_mov.id is null then
    raise exception 'Movimentação não encontrada.';
  end if;

  if v_mov.status <> 'aberta' then
    raise exception 'Esta movimentação não está mais aguardando retorno.';
  end if;

  if p_fim_em is null then
    raise exception 'Informe o horário correto do retorno.';
  end if;

  if p_fim_em < v_mov.inicio_em then
    raise exception 'O retorno não pode ser anterior à saída.';
  end if;

  if p_fim_em > clock_timestamp() + interval '5 minutes' then
    raise exception 'O retorno não pode estar no futuro.';
  end if;

  update public.movimentacoes_jornada mj
     set fim_em = p_fim_em,
         status = 'encerrada',
         observacao_admin = nullif(btrim(p_observacao), ''),
         analisado_por = auth.uid(),
         analisado_em = clock_timestamp(),
         atualizado_em = clock_timestamp()
   where mj.id = p_id
  returning mj.* into v_mov;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, tabela, registro_id, acao,
    dados_novos, origem, descricao
  )
  values(
    v_empresa,
    auth.uid(),
    'movimentacoes_jornada',
    v_mov.id::text,
    'RETORNO_REGULARIZADO_ADMIN',
    to_jsonb(v_mov),
    'web',
    'Retorno temporário regularizado manualmente pelo administrador.'
  );

  return v_mov;
end;
$$;

create or replace function public.arquivar_movimentacao_admin(
  p_id uuid,
  p_motivo text
)
returns public.movimentacoes_jornada
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_mov public.movimentacoes_jornada%rowtype;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Informe o motivo do arquivamento.';
  end if;

  update public.movimentacoes_jornada mj
     set status = 'cancelada',
         aprovado = false,
         efeito_calculo = 'pendente',
         observacao_admin = btrim(p_motivo),
         analisado_por = auth.uid(),
         analisado_em = clock_timestamp(),
         atualizado_em = clock_timestamp()
   where mj.id = p_id
     and mj.empresa_id = v_empresa
     and mj.status = 'aberta'
  returning mj.* into v_mov;

  if v_mov.id is null then
    raise exception 'Movimentação não encontrada ou já regularizada.';
  end if;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, tabela, registro_id, acao,
    dados_novos, origem, descricao
  )
  values(
    v_empresa,
    auth.uid(),
    'movimentacoes_jornada',
    v_mov.id::text,
    'MOVIMENTACAO_ARQUIVADA_ADMIN',
    to_jsonb(v_mov),
    'web',
    'Movimentação temporária arquivada pelo administrador.'
  );

  return v_mov;
end;
$$;

revoke all on function public.regularizar_retorno_movimentacao_admin(uuid,timestamptz,text)
from public, anon;

grant execute on function public.regularizar_retorno_movimentacao_admin(uuid,timestamptz,text)
to authenticated;

revoke all on function public.arquivar_movimentacao_admin(uuid,text)
from public, anon;

grant execute on function public.arquivar_movimentacao_admin(uuid,text)
to authenticated;

commit;

notify pgrst, 'reload schema';
