-- Plenitude Ponto RC6.6.1 — proteção de atribuição a funcionário inativo.
-- Executar após o SQL RC6.6. Não altera marcações ou jornadas anteriores.
begin;
create or replace function public.rc661_validar_atribuicao_ativa()
returns trigger language plpgsql set search_path=public as $$
begin
 if not exists(select 1 from public.funcionarios f where f.id=new.funcionario_id and f.empresa_id=new.empresa_id and f.ativo=true and coalesce(f.status,'ativo')<>'inativo') then
   raise exception 'Não é permitido atribuir jornada a funcionário inativo.';
 end if;
 return new;
end $$;
drop trigger if exists trg_rc661_atribuicao_ativa on public.atribuicoes_modelo_jornada;
create trigger trg_rc661_atribuicao_ativa before insert or update on public.atribuicoes_modelo_jornada for each row execute function public.rc661_validar_atribuicao_ativa();
-- A função de atribuição da RC6.6 atualiza jornadas antes de inserir o vínculo,
-- mas a exceção do trigger reverte toda a transação, incluindo essas atualizações.
commit;
notify pgrst, 'reload schema';
