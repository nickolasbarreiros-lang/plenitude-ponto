-- Execute DEPOIS de criar o usuário em Authentication > Users.
-- Troque o e-mail abaixo pelo e-mail usado na conta do administrador.

begin;

update public.perfis p
set
  empresa_id = '15964919-68be-4cc3-9c12-618c93dbb99e',
  papel = 'administrador',
  nome = coalesce(nullif(p.nome, ''), 'Administrador'),
  ativo = true
from auth.users u
where p.id = u.id
  and lower(u.email) = lower('TROQUE_AQUI_PELO_EMAIL_DO_ADMINISTRADOR');

commit;

select
  u.email,
  p.nome,
  p.papel,
  p.empresa_id,
  p.ativo
from auth.users u
join public.perfis p on p.id = u.id
where lower(u.email) = lower('TROQUE_AQUI_PELO_EMAIL_DO_ADMINISTRADOR');
