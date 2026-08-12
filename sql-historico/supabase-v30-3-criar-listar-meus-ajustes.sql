begin;

-- Correção V30.3
-- O frontend chama public.listar_meus_ajustes(p_token), mas a função
-- não existe no banco. Este script recria a função usada pela tela
-- da funcionária e força a atualização do cache do PostgREST.

create or replace function public.listar_meus_ajustes(p_token text)
returns setof public.solicitacoes_ajuste
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_funcionario public.funcionarios%rowtype;
begin
  v_funcionario := public.funcionario_por_token(p_token);

  return query
  select s.*
  from public.solicitacoes_ajuste as s
  where s.funcionario_id = v_funcionario.id
  order by s.criado_em desc
  limit 50;
end;
$$;

revoke all on function public.listar_meus_ajustes(text)
from public;

grant execute on function public.listar_meus_ajustes(text)
to anon, authenticated;

commit;

-- Solicita ao Supabase/PostgREST que recarregue imediatamente as funções.
notify pgrst, 'reload schema';
