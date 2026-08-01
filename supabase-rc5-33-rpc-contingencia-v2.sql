-- Plenitude Ponto RC5.33
-- Cria uma RPC nova e limpa para análise de contingência.
-- A nova função usa p_horario_corrigido como text para eliminar
-- incompatibilidades de resolução no cache do PostgREST.

begin;

drop function if exists public.analisar_contingencia_admin_v2(
  uuid,text,text,text
);

create function public.analisar_contingencia_admin_v2(
  p_id uuid,
  p_acao text,
  p_observacao text default null,
  p_horario_corrigido text default null
)
returns public.marcacoes_contingencia
language plpgsql
security definer
set search_path=public
as $$
declare
  v_empresa uuid;
  v_c public.marcacoes_contingencia%rowtype;
  v_mark public.marcacoes%rowtype;
  v_horario timestamptz;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso negado.';
  end if;

  v_empresa:=public.empresa_do_usuario();

  select *
    into v_c
  from public.marcacoes_contingencia
  where id=p_id
    and empresa_id=v_empresa
  for update;

  if v_c.id is null then
    raise exception 'Registro não encontrado.';
  end if;

  if v_c.status not in ('pendente','conflitante') then
    raise exception 'Registro já analisado.';
  end if;

  if p_acao='aprovar' then
    v_horario:=coalesce(
      nullif(trim(p_horario_corrigido),'')::timestamptz,
      v_c.ocorrido_em_dispositivo
    );

    if exists(
      select 1
      from public.marcacoes m
      where m.funcionario_id=v_c.funcionario_id
        and m.data_local=(v_horario at time zone 'America/Sao_Paulo')::date
        and m.tipo=v_c.tipo
    ) then
      update public.marcacoes_contingencia
         set status='duplicado',
             observacao_admin=coalesce(
               nullif(trim(p_observacao),''),
               'Duplicidade detectada na aprovação.'
             ),
             aprovado_por=auth.uid(),
             aprovado_em=clock_timestamp(),
             atualizado_em=clock_timestamp()
       where id=p_id
       returning * into v_c;

      return v_c;
    end if;

    insert into public.marcacoes(
      empresa_id,
      funcionario_id,
      tipo,
      registrado_em,
      data_local,
      origem
    )
    values(
      v_c.empresa_id,
      v_c.funcionario_id,
      v_c.tipo,
      v_horario,
      (v_horario at time zone 'America/Sao_Paulo')::date,
      'contingencia'
    )
    returning * into v_mark;

    update public.marcacoes_contingencia
       set status='aprovado',
           marcacao_oficial_id=v_mark.id,
           observacao_admin=nullif(trim(p_observacao),''),
           aprovado_por=auth.uid(),
           aprovado_em=clock_timestamp(),
           atualizado_em=clock_timestamp()
     where id=p_id
     returning * into v_c;

  elsif p_acao='rejeitar' then
    if length(trim(coalesce(p_observacao,'')))<5 then
      raise exception 'Informe o motivo da rejeição.';
    end if;

    update public.marcacoes_contingencia
       set status='rejeitado',
           observacao_admin=trim(p_observacao),
           aprovado_por=auth.uid(),
           aprovado_em=clock_timestamp(),
           atualizado_em=clock_timestamp()
     where id=p_id
     returning * into v_c;
  else
    raise exception 'Ação inválida.';
  end if;

  insert into public.logs_auditoria(
    empresa_id,
    usuario_id,
    tabela,
    registro_id,
    acao,
    dados_novos,
    origem,
    descricao
  )
  values(
    v_empresa,
    auth.uid(),
    'marcacoes_contingencia',
    v_c.id::text,
    case
      when p_acao='aprovar' then 'CONTINGENCIA_APROVADA'
      else 'CONTINGENCIA_REJEITADA'
    end,
    to_jsonb(v_c),
    'web',
    'Registro offline analisado pelo administrador.'
  );

  return v_c;
end;
$$;

revoke all on function public.analisar_contingencia_admin_v2(
  uuid,text,text,text
) from public,anon;

grant execute on function public.analisar_contingencia_admin_v2(
  uuid,text,text,text
) to authenticated;

commit;

notify pgrst,'reload schema';
