begin;

create or replace function public.registrar_movimentacao_dispositivo(
  p_token text,
  p_dispositivo_token text,
  p_acao text,
  p_motivo text default null,
  p_user_agent text default null
)
returns public.movimentacoes_jornada
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_dispositivo public.dispositivos_ponto%rowtype;
  v_funcionario public.funcionarios%rowtype;
  v_movimentacao public.movimentacoes_jornada%rowtype;
  v_agora timestamptz := clock_timestamp();
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  select d.* into v_dispositivo
  from public.dispositivos_ponto d
  where d.token_hash=encode(extensions.digest(coalesce(p_dispositivo_token,''),'sha256'),'hex')
    and d.ativo=true
  limit 1;

  if v_dispositivo.id is null then
    raise exception 'Registro bloqueado: computador não autorizado.';
  end if;

  v_funcionario:=public.funcionario_por_token(p_token);

  if v_funcionario.empresa_id<>v_dispositivo.empresa_id then
    raise exception 'Dispositivo não autorizado para esta empresa.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_funcionario.id::text||':movimentacao',20260731));

  if p_acao='saida' then
    if exists(
      select 1 from public.movimentacoes_jornada mj
      where mj.funcionario_id=v_funcionario.id
        and mj.data_local=v_hoje
        and mj.status='aberta'
    ) then
      raise exception 'Já existe uma saída temporária de hoje aguardando retorno.';
    end if;

    insert into public.movimentacoes_jornada(
      empresa_id,funcionario_id,data_local,inicio_em,origem,motivo_informado,status
    ) values(
      v_funcionario.empresa_id,v_funcionario.id,v_hoje,v_agora,
      'funcionario',nullif(btrim(p_motivo),''),'aberta'
    )
    returning * into v_movimentacao;

  elsif p_acao='retorno' then
    select mj.* into v_movimentacao
    from public.movimentacoes_jornada mj
    where mj.funcionario_id=v_funcionario.id
      and mj.data_local=v_hoje
      and mj.status='aberta'
    order by mj.inicio_em desc
    limit 1
    for update;

    if v_movimentacao.id is null then
      raise exception 'Não existe saída temporária aberta hoje.';
    end if;

    update public.movimentacoes_jornada mj
       set fim_em=v_agora,status='encerrada',atualizado_em=v_agora
     where mj.id=v_movimentacao.id
    returning mj.* into v_movimentacao;
  else
    raise exception 'Ação inválida.';
  end if;

  update public.dispositivos_ponto
     set ultimo_uso_em=v_agora
   where id=v_dispositivo.id;

  return v_movimentacao;
end;
$$;

create or replace function public.listar_pendencias_retorno_funcionario(p_token text)
returns table(
  id uuid,data_local date,inicio_em timestamptz,motivo_informado text,dias_em_aberto integer
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  v_funcionario:=public.funcionario_por_token(p_token);
  return query
  select mj.id,mj.data_local,mj.inicio_em,mj.motivo_informado,(v_hoje-mj.data_local)::integer
  from public.movimentacoes_jornada mj
  where mj.funcionario_id=v_funcionario.id
    and mj.status='aberta'
    and mj.data_local<v_hoje
  order by mj.data_local desc,mj.inicio_em desc;
end;
$$;

create or replace function public.listar_pendencias_retorno_admin()
returns table(
  id uuid,funcionario_id uuid,funcionario_nome text,matricula text,
  data_local date,inicio_em timestamptz,motivo_informado text,dias_em_aberto integer
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_hoje date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  select p.empresa_id into v_empresa
  from public.perfis p
  where p.id=auth.uid() and p.papel='administrador' and p.ativo=true
  limit 1;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  return query
  select mj.id,mj.funcionario_id,f.nome,f.matricula,mj.data_local,mj.inicio_em,
         mj.motivo_informado,(v_hoje-mj.data_local)::integer
  from public.movimentacoes_jornada mj
  join public.funcionarios f on f.id=mj.funcionario_id
  where mj.empresa_id=v_empresa
    and mj.status='aberta'
    and mj.data_local<v_hoje
  order by mj.data_local asc,f.nome;
end;
$$;

revoke all on function public.registrar_movimentacao_dispositivo(text,text,text,text,text) from public;
grant execute on function public.registrar_movimentacao_dispositivo(text,text,text,text,text) to anon,authenticated;
revoke all on function public.listar_pendencias_retorno_funcionario(text) from public;
grant execute on function public.listar_pendencias_retorno_funcionario(text) to anon,authenticated;
revoke all on function public.listar_pendencias_retorno_admin() from public,anon;
grant execute on function public.listar_pendencias_retorno_admin() to authenticated;

commit;
notify pgrst,'reload schema';
