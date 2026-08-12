begin;

-- RC4.8 — correção da página Auditoria
-- Causa: COALESCE tentava combinar dados_novos (jsonb) com dados (text).
-- PostgreSQL não permite COALESCE entre jsonb e text sem conversão explícita.

create or replace function public.listar_auditoria_admin(
  p_inicio timestamptz default null,
  p_fim timestamptz default null,
  p_acao text default null,
  p_tabela text default null,
  p_busca text default null,
  p_limite integer default 200,
  p_offset integer default 0
)
returns table(
  id bigint,
  criado_em timestamptz,
  usuario_id uuid,
  usuario_nome text,
  usuario_email text,
  acao text,
  tabela text,
  registro_id text,
  descricao text,
  origem text,
  dados_anteriores jsonb,
  dados_novos jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso permitido somente ao administrador.';
  end if;

  v_empresa := public.empresa_do_usuario();

  return query
  select
    l.id,
    l.criado_em,
    l.usuario_id,
    coalesce(p.nome, 'Sistema')::text as usuario_nome,
    coalesce(u.email, '—')::text as usuario_email,
    l.acao::text,
    l.tabela::text,
    l.registro_id::text,
    coalesce(l.descricao, '')::text as descricao,
    coalesce(l.origem, 'sistema')::text as origem,
    l.dados_anteriores,
    coalesce(
      l.dados_novos,
      case
        when l.dados is null then null::jsonb
        else to_jsonb(l.dados)
      end
    ) as dados_novos
  from public.logs_auditoria as l
  left join public.perfis as p
    on p.id = l.usuario_id
  left join auth.users as u
    on u.id = l.usuario_id
  where l.empresa_id = v_empresa
    and (p_inicio is null or l.criado_em >= p_inicio)
    and (p_fim is null or l.criado_em <= p_fim)
    and (p_acao is null or p_acao = '' or upper(l.acao) = upper(p_acao))
    and (p_tabela is null or p_tabela = '' or l.tabela = p_tabela)
    and (
      p_busca is null
      or p_busca = ''
      or concat_ws(
        ' ',
        l.acao,
        l.tabela,
        l.registro_id,
        l.descricao,
        p.nome,
        u.email,
        l.dados::text,
        l.dados_anteriores::text,
        l.dados_novos::text
      ) ilike '%' || p_busca || '%'
    )
  order by l.criado_em desc
  limit greatest(1, least(coalesce(p_limite, 200), 500))
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.listar_auditoria_admin(
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  integer,
  integer
) from public, anon;

grant execute on function public.listar_auditoria_admin(
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  integer,
  integer
) to authenticated;

commit;

notify pgrst, 'reload schema';

-- Teste opcional: deve retornar registros sem erro de tipo.
-- select * from public.listar_auditoria_admin(
--   now() - interval '30 days',
--   now(),
--   null,
--   null,
--   null,
--   10,
--   0
-- );
