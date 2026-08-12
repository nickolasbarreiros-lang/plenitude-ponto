-- ============================================================
-- PLENITUDE PONTO RC6.1
-- BANCO DE HORAS ACUMULADO ENTRE COMPETÊNCIAS
-- ============================================================
--
-- Regra:
-- 1. O saldo mensal continua existindo separadamente.
-- 2. Ao FECHAR uma competência, o saldo daquele mês é congelado em snapshot.
-- 3. Competências fechadas anteriores formam o "saldo anterior".
-- 4. O banco acumulado exibido = saldo anterior consolidado + saldo da competência.
-- 5. Ao REABRIR uma competência, o snapshot daquele mês é removido.
-- 6. Ao FECHAR novamente, um novo snapshot é calculado.
--
-- Nenhuma marcação original é alterada.

begin;

create table if not exists public.banco_horas_competencias (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  ano integer not null check (ano between 2020 and 2100),
  mes integer not null check (mes between 1 and 12),
  saldo_competencia_minutos integer not null default 0,
  fechamento_id uuid references public.fechamentos_mensais(id) on delete set null,
  fechado_em timestamptz,
  calculado_em timestamptz not null default clock_timestamp(),
  unique (empresa_id, funcionario_id, ano, mes)
);

create index if not exists idx_banco_horas_competencias_funcionario
  on public.banco_horas_competencias(funcionario_id,ano,mes);

create index if not exists idx_banco_horas_competencias_empresa
  on public.banco_horas_competencias(empresa_id,ano,mes);

alter table public.banco_horas_competencias enable row level security;

revoke all on table public.banco_horas_competencias
  from public,anon,authenticated;


-- Função interna: consolida os saldos de todos os funcionários da empresa
-- quando uma competência é fechada.
create or replace function public._consolidar_banco_horas_competencia(
  p_empresa_id uuid,
  p_ano integer,
  p_mes integer,
  p_fechamento_id uuid default null,
  p_fechado_em timestamptz default null
)
returns void
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_inicio date;
  v_fim date;
  v_funcionario record;
  v_calculo jsonb;
  v_saldo integer;
begin
  if p_empresa_id is null then
    raise exception 'Empresa não informada.';
  end if;

  if p_ano not between 2020 and 2100 or p_mes not between 1 and 12 then
    raise exception 'Competência inválida.';
  end if;

  v_inicio:=make_date(p_ano,p_mes,1);
  v_fim:=(v_inicio+interval '1 month - 1 day')::date;

  for v_funcionario in
    select f.id
    from public.funcionarios f
    where f.empresa_id=p_empresa_id
      and (f.data_admissao is null or f.data_admissao<=v_fim)
    order by f.id
  loop
    v_calculo:=public._calcular_banco_horas_json(
      v_funcionario.id,
      v_inicio,
      v_fim
    );

    v_saldo:=coalesce(
      (v_calculo->'resumo'->>'saldo_minutos')::integer,
      0
    );

    insert into public.banco_horas_competencias(
      empresa_id,
      funcionario_id,
      ano,
      mes,
      saldo_competencia_minutos,
      fechamento_id,
      fechado_em,
      calculado_em
    )
    values(
      p_empresa_id,
      v_funcionario.id,
      p_ano,
      p_mes,
      v_saldo,
      p_fechamento_id,
      coalesce(p_fechado_em,clock_timestamp()),
      clock_timestamp()
    )
    on conflict(empresa_id,funcionario_id,ano,mes)
    do update set
      saldo_competencia_minutos=excluded.saldo_competencia_minutos,
      fechamento_id=excluded.fechamento_id,
      fechado_em=excluded.fechado_em,
      calculado_em=clock_timestamp();
  end loop;
end;
$$;

revoke all on function public._consolidar_banco_horas_competencia(
  uuid,integer,integer,uuid,timestamptz
) from public,anon,authenticated;


-- Trigger desacoplado do fluxo de fechamento atual.
-- Assim, tanto fechamento normal quanto fechamento com PIN Mestre
-- passam automaticamente a consolidar o banco.
create or replace function public.sincronizar_banco_horas_fechamento()
returns trigger
language plpgsql
security definer
set search_path=public,extensions
as $$
begin
  if new.status='fechado'
     and (
       tg_op='INSERT'
       or old.status is distinct from new.status
       or old.fechado_em is distinct from new.fechado_em
     ) then

    perform public._consolidar_banco_horas_competencia(
      new.empresa_id,
      new.ano,
      new.mes,
      new.id,
      new.fechado_em
    );

  elsif new.status='reaberto'
        and (
          tg_op='INSERT'
          or old.status is distinct from new.status
        ) then

    delete from public.banco_horas_competencias bh
    where bh.empresa_id=new.empresa_id
      and bh.ano=new.ano
      and bh.mes=new.mes;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sincronizar_banco_horas_fechamento
  on public.fechamentos_mensais;

create trigger trg_sincronizar_banco_horas_fechamento
after insert or update of status,fechado_em
on public.fechamentos_mensais
for each row
execute function public.sincronizar_banco_horas_fechamento();


-- Consulta do banco acumulado para o administrador.
create or replace function public.banco_horas_acumulado_admin(
  p_funcionario_id uuid,
  p_ano integer,
  p_mes integer
)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa_id uuid;
  v_inicio date;
  v_fim date;
  v_saldo_anterior integer:=0;
  v_saldo_competencia integer:=0;
  v_saldo_acumulado integer:=0;
  v_snapshot integer;
  v_calculo jsonb;
  v_competencias_consolidadas integer:=0;
  v_fechada boolean:=false;
  v_ultimo_fechamento date;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  if p_ano not between 2020 and 2100 or p_mes not between 1 and 12 then
    raise exception 'Competência inválida.';
  end if;

  v_empresa_id:=public.empresa_do_usuario();

  if not exists(
    select 1
    from public.funcionarios f
    where f.id=p_funcionario_id
      and f.empresa_id=v_empresa_id
  ) then
    raise exception 'Funcionário não pertence à sua empresa.';
  end if;

  v_inicio:=make_date(p_ano,p_mes,1);
  v_fim:=(v_inicio+interval '1 month - 1 day')::date;

  select
    coalesce(sum(bh.saldo_competencia_minutos),0)::integer,
    count(*)::integer,
    max(make_date(bh.ano,bh.mes,1))
  into
    v_saldo_anterior,
    v_competencias_consolidadas,
    v_ultimo_fechamento
  from public.banco_horas_competencias bh
  where bh.empresa_id=v_empresa_id
    and bh.funcionario_id=p_funcionario_id
    and make_date(bh.ano,bh.mes,1)<v_inicio;

  select bh.saldo_competencia_minutos
    into v_snapshot
  from public.banco_horas_competencias bh
  where bh.empresa_id=v_empresa_id
    and bh.funcionario_id=p_funcionario_id
    and bh.ano=p_ano
    and bh.mes=p_mes;

  if found then
    v_saldo_competencia:=coalesce(v_snapshot,0);
    v_fechada:=true;
  else
    v_calculo:=public._calcular_banco_horas_json(
      p_funcionario_id,
      v_inicio,
      v_fim
    );

    v_saldo_competencia:=coalesce(
      (v_calculo->'resumo'->>'saldo_minutos')::integer,
      0
    );
  end if;

  v_saldo_acumulado:=v_saldo_anterior+v_saldo_competencia;

  return jsonb_build_object(
    'funcionario_id',p_funcionario_id,
    'ano',p_ano,
    'mes',p_mes,
    'competencia_fechada',v_fechada,
    'saldo_anterior_minutos',v_saldo_anterior,
    'saldo_competencia_minutos',v_saldo_competencia,
    'saldo_acumulado_minutos',v_saldo_acumulado,
    'competencias_consolidadas',v_competencias_consolidadas,
    'ultimo_fechamento',v_ultimo_fechamento,
    'regra','competencias_fechadas_mais_competencia_atual'
  );
end;
$$;

revoke all on function public.banco_horas_acumulado_admin(
  uuid,integer,integer
) from public,anon;

grant execute on function public.banco_horas_acumulado_admin(
  uuid,integer,integer
) to authenticated;


-- Reconstrução administrativa dos snapshots já existentes.
create or replace function public.reconstruir_banco_horas_fechamentos_admin()
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa_id uuid;
  v_fechamento record;
  v_total integer:=0;
begin
  if not public.usuario_e_admin() then
    raise exception 'Acesso administrativo necessário.';
  end if;

  v_empresa_id:=public.empresa_do_usuario();

  for v_fechamento in
    select fm.*
    from public.fechamentos_mensais fm
    where fm.empresa_id=v_empresa_id
      and fm.status='fechado'
    order by fm.ano,fm.mes
  loop
    perform public._consolidar_banco_horas_competencia(
      v_fechamento.empresa_id,
      v_fechamento.ano,
      v_fechamento.mes,
      v_fechamento.id,
      v_fechamento.fechado_em
    );
    v_total:=v_total+1;
  end loop;

  perform public.registrar_evento_auditoria(
    'RECONSTRUIR_BANCO_HORAS',
    'banco_horas_competencias',
    null,
    format('%s competência(s) fechada(s) reconstruída(s)',v_total),
    jsonb_build_object('competencias_reconstruidas',v_total),
    'sql'
  );

  return jsonb_build_object(
    'sucesso',true,
    'competencias_reconstruidas',v_total
  );
end;
$$;

revoke all on function public.reconstruir_banco_horas_fechamentos_admin()
from public,anon;

grant execute on function public.reconstruir_banco_horas_fechamentos_admin()
to authenticated;


-- Migração inicial:
-- consolida automaticamente todas as competências que já estavam fechadas
-- antes da instalação da RC6.1. Isso permite que o saldo de meses anteriores
-- apareça imediatamente no banco acumulado.
do $$
declare
  v_fechamento record;
begin
  for v_fechamento in
    select fm.*
    from public.fechamentos_mensais fm
    where fm.status='fechado'
    order by fm.empresa_id,fm.ano,fm.mes
  loop
    perform public._consolidar_banco_horas_competencia(
      v_fechamento.empresa_id,
      v_fechamento.ano,
      v_fechamento.mes,
      v_fechamento.id,
      v_fechamento.fechado_em
    );
  end loop;
end;
$$;

commit;

notify pgrst,'reload schema';
