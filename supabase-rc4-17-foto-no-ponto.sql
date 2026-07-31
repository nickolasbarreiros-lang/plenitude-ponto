begin;

-- RC4.17 — foto do funcionário no terminal de ponto
--
-- O login por matrícula + PIN usa sessão própria e não uma sessão Auth do
-- Supabase. Por isso o navegador do terminal não conseguia gerar URL assinada
-- para uma foto armazenada em bucket privado.
--
-- A correção torna público somente o bucket "funcionarios".
-- Os demais buckets permanecem inalterados.

update storage.buckets
set public = true
where id = 'funcionarios';

commit;

-- Conferência:
select id, name, public
from storage.buckets
where id = 'funcionarios';
