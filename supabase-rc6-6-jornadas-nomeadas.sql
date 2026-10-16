-- RC6.6: jornadas-modelo e atribuição administrativa.
-- Instalar APÓS a RC6.5.7. Não apaga jornadas ou marcações existentes.
begin;
create table if not exists public.modelos_jornada (
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 nome text not null check(length(trim(nome)) between 3 and 100),
 descricao text not null default '',
 criado_em timestamptz not null default now(),
 unique(empresa_id,nome), unique(id,empresa_id)
);
create table if not exists public.modelos_jornada_dias (
 modelo_id uuid not null references public.modelos_jornada(id) on delete cascade,
 dia_semana smallint not null check(dia_semana between 1 and 7),
 entrada time, inicio_intervalo time, fim_intervalo time, saida time,
 primary key(modelo_id,dia_semana),
 constraint rc66_horarios_validos check (
  (entrada is null and inicio_intervalo is null and fim_intervalo is null and saida is null)
  or (entrada is not null and inicio_intervalo is not null and fim_intervalo is not null and saida is not null
  and entrada < inicio_intervalo and inicio_intervalo < fim_intervalo and fim_intervalo < saida)
 )
);
create table if not exists public.atribuicoes_modelo_jornada (
 id bigint generated always as identity primary key,
 empresa_id uuid not null references public.empresas(id),
 funcionario_id uuid not null references public.funcionarios(id),
 modelo_id uuid not null references public.modelos_jornada(id),
 vigencia_inicio date not null,
 aplicado_em timestamptz not null default now(),
 criado_por uuid,
 unique(funcionario_id,vigencia_inicio)
);
create index if not exists idx_rc66_atribuicoes_funcionario on public.atribuicoes_modelo_jornada(funcionario_id,vigencia_inicio desc);
-- Acesso às tabelas somente pelas funções SECURITY DEFINER.
alter table public.modelos_jornada enable row level security;
alter table public.modelos_jornada_dias enable row level security;
alter table public.atribuicoes_modelo_jornada enable row level security;
revoke all on public.modelos_jornada,public.modelos_jornada_dias,public.atribuicoes_modelo_jornada from anon,authenticated;
create or replace function public.rc66_empresa_admin() returns uuid language plpgsql stable security definer set search_path=public as $$
declare v uuid;
begin
 select empresa_id into v from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
 if v is null then raise exception 'Acesso administrativo não autorizado'; end if;
 return v;
end $$;
create or replace function public.rc66_listar_modelos() returns jsonb language plpgsql security definer set search_path=public as $$
declare emp uuid; result jsonb;
begin
 emp:=public.rc66_empresa_admin();
 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'nome',m.nome,'descricao',m.descricao,'dias',
  (select coalesce(jsonb_agg(jsonb_build_object('dia_semana',d.dia_semana,'entrada',to_char(d.entrada,'HH24:MI'),'almoco',to_char(d.inicio_intervalo,'HH24:MI'),'retorno',to_char(d.fim_intervalo,'HH24:MI'),'saida',to_char(d.saida,'HH24:MI')) order by d.dia_semana),'[]'::jsonb) from public.modelos_jornada_dias d where d.modelo_id=m.id)) order by m.nome),'[]'::jsonb)
 into result from public.modelos_jornada m where m.empresa_id=emp;
 return result;
end $$;
create or replace function public.rc66_salvar_modelo(p_id uuid,p_nome text,p_descricao text,p_dias jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare emp uuid; mid uuid; item jsonb; n integer; dia integer; ent time; alm time; ret time; sai time;
begin
 emp:=public.rc66_empresa_admin();
 if length(trim(coalesce(p_nome,''))) not between 3 and 100 then raise exception 'Informe um nome entre 3 e 100 caracteres'; end if;
 if jsonb_typeof(p_dias)<>'array' or jsonb_array_length(p_dias)<>7 then raise exception 'A jornada deve conter sete dias'; end if;
 if p_id is null then
  insert into public.modelos_jornada(empresa_id,nome,descricao) values(emp,trim(p_nome),coalesce(p_descricao,'')) returning id into mid;
 else
  update public.modelos_jornada set nome=trim(p_nome),descricao=coalesce(p_descricao,'') where id=p_id and empresa_id=emp returning id into mid;
  if mid is null then raise exception 'Modelo não encontrado'; end if;
  if exists(select 1 from public.atribuicoes_modelo_jornada where modelo_id=mid) then
   raise exception 'Jornada já atribuída. Crie outra jornada para alterar horários sem afetar o histórico.';
  end if;
  delete from public.modelos_jornada_dias where modelo_id=mid;
 end if;
 for n in 0..6 loop
  item:=p_dias->n; dia:=(item->>'dia_semana')::int;
  if dia<>n+1 then raise exception 'Ordem inválida dos dias'; end if;
  ent:=nullif(item->>'entrada','')::time;
  alm:=nullif(item->>'almoco','')::time;
  ret:=nullif(item->>'retorno','')::time;
  sai:=nullif(item->>'saida','')::time;
  insert into public.modelos_jornada_dias(modelo_id,dia_semana,entrada,inicio_intervalo,fim_intervalo,saida)
   values(mid,dia,ent,alm,ret,sai);
 end loop;
 return mid;
end $$;
create or replace function public.rc66_atribuir_modelo(p_funcionario uuid,p_modelo uuid,p_vigencia date default current_date)
returns void language plpgsql security definer set search_path=public as $$
declare emp uuid; n int;
begin
 emp:=public.rc66_empresa_admin();
 if not exists(select 1 from public.funcionarios where id=p_funcionario and empresa_id=emp) then raise exception 'Funcionário não pertence à empresa'; end if;
 if not exists(select 1 from public.modelos_jornada where id=p_modelo and empresa_id=emp) then raise exception 'Jornada não pertence à empresa'; end if;
 if p_vigencia is null or p_vigencia>current_date then raise exception 'Agendamento futuro ainda não suportado nesta versão'; end if;
 -- Atribuições retroativas exigem motor de cálculo histórico, ainda não migrado.
 if p_vigencia<>current_date then raise exception 'A atribuição deve começar hoje nesta versão'; end if;
 -- A rotina atual de apuração lê public.jornadas: atualizar as sete linhas atomicamente.
 insert into public.jornadas(empresa_id,funcionario_id,dia_semana,entrada,inicio_intervalo,fim_intervalo,saida,ativo)
 select emp,p_funcionario,d.dia_semana,d.entrada,d.inicio_intervalo,d.fim_intervalo,d.saida,true
 from public.modelos_jornada_dias d where d.modelo_id=p_modelo
 on conflict(funcionario_id,dia_semana) do update set
 entrada=excluded.entrada,inicio_intervalo=excluded.inicio_intervalo,
 fim_intervalo=excluded.fim_intervalo,saida=excluded.saida,ativo=true;
 get diagnostics n=row_count;
 if n<>7 then raise exception 'Jornada incompleta'; end if;
 insert into public.atribuicoes_modelo_jornada(empresa_id,funcionario_id,modelo_id,vigencia_inicio,criado_por)
 values(emp,p_funcionario,p_modelo,p_vigencia,auth.uid())
 on conflict(funcionario_id,vigencia_inicio) do update set modelo_id=excluded.modelo_id,aplicado_em=now(),criado_por=auth.uid();
end $$;
create or replace function public.rc66_listar_atribuicoes() returns jsonb language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('funcionario_id',a.funcionario_id,'modelo_id',a.modelo_id,'vigencia_inicio',a.vigencia_inicio,'aplicado_em',a.aplicado_em) order by a.aplicado_em desc),'[]'::jsonb)
 from public.atribuicoes_modelo_jornada a where a.empresa_id=public.rc66_empresa_admin();
$$;
revoke all on function public.rc66_empresa_admin(),public.rc66_listar_modelos(),public.rc66_salvar_modelo(uuid,text,text,jsonb),public.rc66_atribuir_modelo(uuid,uuid,date),public.rc66_listar_atribuicoes() from public;
grant execute on function public.rc66_listar_modelos(),public.rc66_salvar_modelo(uuid,text,text,jsonb),public.rc66_atribuir_modelo(uuid,uuid,date),public.rc66_listar_atribuicoes() to authenticated;
commit;
notify pgrst,'reload schema';
