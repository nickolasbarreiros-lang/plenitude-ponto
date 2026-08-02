-- Plenitude Ponto RC5.49
-- Pendência de jornada somente após a virada do dia, usando o fuso da empresa.

begin;

create or replace function public.atualizar_pendencias_jornada_empresa(
  p_empresa_id uuid,
  p_funcionario_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer:=0;
  v_timezone text:='America/Sao_Paulo';
  v_hoje date;
begin
  select coalesce(e.timezone,'America/Sao_Paulo')
    into v_timezone
  from public.empresas e
  where e.id=p_empresa_id;

  v_hoje:=(clock_timestamp() at time zone v_timezone)::date;

  /*
   * Remove da fila qualquer pendência criada indevidamente para o dia atual
   * ou para uma data futura. A jornada ainda está em andamento.
   */
  update public.pendencias_jornada p
     set status='resolvida',
         resolvida_em=coalesce(p.resolvida_em,clock_timestamp()),
         atualizado_em=clock_timestamp(),
         observacao='Pendência removida porque a jornada ainda não havia encerrado.'
   where p.empresa_id=p_empresa_id
     and p.status='pendente'
     and (p_funcionario_id is null or p.funcionario_id=p_funcionario_id)
     and p.data_local>=v_hoje;

  /*
   * Resolve quando o dia anterior passa a possuir as quatro marcações.
   */
  update public.pendencias_jornada p
     set status='resolvida',
         resolvida_em=coalesce(p.resolvida_em,clock_timestamp()),
         atualizado_em=clock_timestamp(),
         observacao=coalesce(
           p.observacao,
           'Regularizada por marcação ou ajuste posterior.'
         )
   where p.empresa_id=p_empresa_id
     and p.status='pendente'
     and p.data_local<v_hoje
     and (p_funcionario_id is null or p.funcionario_id=p_funcionario_id)
     and (
       select count(*)
       from public.marcacoes m
       where m.funcionario_id=p.funcionario_id
         and m.data_local=p.data_local
     )>=4;

  /*
   * Gera pendência exclusivamente para dias anteriores no fuso da empresa.
   * Nunca usa current_date, pois ele segue o fuso da sessão do banco.
   */
  insert into public.pendencias_jornada(
    empresa_id,
    funcionario_id,
    data_local,
    quantidade_marcacoes,
    marcacao_faltante,
    status,
    detectada_em,
    atualizado_em
  )
  select
    f.empresa_id,
    f.id,
    m.data_local,
    count(*)::integer,
    public.tipo_marcacao_faltante_jornada(count(*)::integer),
    'pendente',
    clock_timestamp(),
    clock_timestamp()
  from public.marcacoes m
  join public.funcionarios f
    on f.id=m.funcionario_id
  where f.empresa_id=p_empresa_id
    and f.ativo=true
    and m.data_local<v_hoje
    and (p_funcionario_id is null or f.id=p_funcionario_id)
  group by f.empresa_id,f.id,m.data_local
  having count(*) between 1 and 3
  on conflict (funcionario_id,data_local)
  do update set
    quantidade_marcacoes=excluded.quantidade_marcacoes,
    marcacao_faltante=excluded.marcacao_faltante,
    status='pendente',
    resolvida_em=null,
    atualizado_em=clock_timestamp(),
    observacao=null;

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function public.listar_pendencias_jornada_admin()
returns table(
  id uuid,
  funcionario_id uuid,
  funcionario_nome text,
  matricula text,
  data_local date,
  quantidade_marcacoes integer,
  marcacao_faltante text,
  marcacao_faltante_label text,
  status text,
  detectada_em timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user uuid:=auth.uid();
  v_empresa uuid;
  v_timezone text:='America/Sao_Paulo';
  v_hoje date;
begin
  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id=v_user
    and p.papel='administrador';

  if v_empresa is null then
    raise exception 'Acesso administrativo necessário.';
  end if;

  select coalesce(e.timezone,'America/Sao_Paulo')
    into v_timezone
  from public.empresas e
  where e.id=v_empresa;

  v_hoje:=(clock_timestamp() at time zone v_timezone)::date;

  perform public.atualizar_pendencias_jornada_empresa(v_empresa,null);

  return query
  select
    pj.id,
    pj.funcionario_id,
    f.nome,
    f.matricula,
    pj.data_local,
    pj.quantidade_marcacoes,
    pj.marcacao_faltante,
    public.rotulo_marcacao_jornada(pj.marcacao_faltante),
    pj.status,
    pj.detectada_em
  from public.pendencias_jornada pj
  join public.funcionarios f
    on f.id=pj.funcionario_id
  where pj.empresa_id=v_empresa
    and pj.status='pendente'
    and pj.data_local<v_hoje
  order by pj.data_local,pj.detectada_em;
end;
$$;

create or replace function public.listar_minhas_pendencias_jornada(
  p_token text
)
returns table(
  id uuid,
  data_local date,
  quantidade_marcacoes integer,
  marcacao_faltante text,
  marcacao_faltante_label text,
  status text,
  detectada_em timestamptz
)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
  v_timezone text:='America/Sao_Paulo';
  v_hoje date;
begin
  v_funcionario:=public.funcionario_por_token(p_token);

  select coalesce(e.timezone,'America/Sao_Paulo')
    into v_timezone
  from public.empresas e
  where e.id=v_funcionario.empresa_id;

  v_hoje:=(clock_timestamp() at time zone v_timezone)::date;

  perform public.atualizar_pendencias_jornada_empresa(
    v_funcionario.empresa_id,
    v_funcionario.id
  );

  return query
  select
    pj.id,
    pj.data_local,
    pj.quantidade_marcacoes,
    pj.marcacao_faltante,
    public.rotulo_marcacao_jornada(pj.marcacao_faltante),
    pj.status,
    pj.detectada_em
  from public.pendencias_jornada pj
  where pj.empresa_id=v_funcionario.empresa_id
    and pj.funcionario_id=v_funcionario.id
    and pj.status='pendente'
    and pj.data_local<v_hoje
  order by pj.data_local,pj.detectada_em;
end;
$$;

revoke all on function public.atualizar_pendencias_jornada_empresa(uuid,uuid)
  from public,anon,authenticated;

revoke all on function public.listar_pendencias_jornada_admin()
  from public,anon;

grant execute on function public.listar_pendencias_jornada_admin()
  to authenticated;

revoke all on function public.listar_minhas_pendencias_jornada(text)
  from public;

grant execute on function public.listar_minhas_pendencias_jornada(text)
  to anon,authenticated;

commit;

notify pgrst,'reload schema';
