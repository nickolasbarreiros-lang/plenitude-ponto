-- PLENITUDE PONTO V11 — perfil visual e identificação do funcionário
-- Execute uma única vez no SQL Editor do Supabase antes de publicar a V11.

begin;

alter table public.funcionarios
  add column if not exists status text not null default 'ativo',
  add column if not exists foto_url text,
  add column if not exists codigo_qr text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'funcionarios_status_check'
  ) then
    alter table public.funcionarios
      add constraint funcionarios_status_check
      check (status in ('ativo','ferias','afastado','inativo'));
  end if;
end $$;

update public.funcionarios
set codigo_qr = 'PLENITUDE-' || upper(substr(replace(id::text,'-',''),1,12))
where codigo_qr is null;

create unique index if not exists funcionarios_codigo_qr_unique
  on public.funcionarios(codigo_qr)
  where codigo_qr is not null;

create or replace function public.definir_codigo_qr_funcionario()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.codigo_qr is null or btrim(new.codigo_qr) = '' then
    new.codigo_qr := 'PLENITUDE-' || upper(substr(replace(new.id::text,'-',''),1,12));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_funcionarios_codigo_qr on public.funcionarios;
create trigger trg_funcionarios_codigo_qr
before insert or update of codigo_qr on public.funcionarios
for each row execute function public.definir_codigo_qr_funcionario();

commit;

select id,nome,status,codigo_qr from public.funcionarios order by nome;
