-- PLENITUDE PONTO V28 — MOVIMENTAÇÕES E JUSTIFICATIVAS DE JORNADA
-- Execute integralmente no SQL Editor do Supabase após a V27.

begin;

create table if not exists public.movimentacoes_jornada (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  data_local date not null,
  inicio_em timestamptz not null,
  fim_em timestamptz,
  origem text not null default 'funcionario',
  motivo_informado text,
  classificacao text,
  efeito_calculo text not null default 'pendente',
  status text not null default 'aberta',
  aprovado boolean not null default false,
  observacao_admin text,
  criado_por uuid,
  analisado_por uuid,
  analisado_em timestamptz,
  criado_em timestamptz not null default clock_timestamp(),
  atualizado_em timestamptz not null default clock_timestamp(),
  constraint movimentacoes_status_check check (status in ('aberta','encerrada','cancelada')),
  constraint movimentacoes_efeito_check check (efeito_calculo in ('pendente','descontar','abonar','trabalhado','credito')),
  constraint movimentacoes_classificacao_check check (classificacao is null or classificacao in (
    'consulta_medica','atestado','servico_externo','curso','banco','particular','saida_autorizada',
    'compensacao','hora_extra_autorizada','home_office','outro'
  )),
  constraint movimentacoes_periodo_check check (fim_em is null or fim_em >= inicio_em)
);

create index if not exists movimentacoes_func_data_idx on public.movimentacoes_jornada(funcionario_id,data_local,inicio_em);
create index if not exists movimentacoes_empresa_status_idx on public.movimentacoes_jornada(empresa_id,status,aprovado);

alter table public.movimentacoes_jornada enable row level security;
drop policy if exists movimentacoes_admin_select on public.movimentacoes_jornada;
create policy movimentacoes_admin_select on public.movimentacoes_jornada for select to authenticated
using (empresa_id=public.empresa_do_usuario() and public.usuario_e_admin());

create or replace function public.registrar_movimentacao_dispositivo(
  p_token text,p_dispositivo_token text,p_acao text,p_motivo text default null,p_user_agent text default null
)
returns public.movimentacoes_jornada
language plpgsql security definer set search_path=public,extensions as $$
declare d public.dispositivos_ponto%rowtype; f public.funcionarios%rowtype; v public.movimentacoes_jornada%rowtype;
  agora timestamptz:=clock_timestamp(); hoje date;
begin
  select * into d from public.dispositivos_ponto
  where token_hash=encode(digest(coalesce(p_dispositivo_token,''),'sha256'),'hex') and ativo=true;
  if d.id is null then raise exception 'Registro bloqueado: computador não autorizado.'; end if;
  f:=public.funcionario_por_token(p_token);
  if f.empresa_id<>d.empresa_id then raise exception 'Dispositivo não autorizado para esta empresa.'; end if;
  hoje:=(agora at time zone 'America/Sao_Paulo')::date;

  if p_acao='saida' then
    if exists(select 1 from public.movimentacoes_jornada where funcionario_id=f.id and status='aberta') then
      raise exception 'Já existe uma saída temporária aguardando retorno.';
    end if;
    insert into public.movimentacoes_jornada(empresa_id,funcionario_id,data_local,inicio_em,origem,motivo_informado,status)
    values(f.empresa_id,f.id,hoje,agora,'funcionario',nullif(trim(p_motivo),''),'aberta') returning * into v;
  elsif p_acao='retorno' then
    select * into v from public.movimentacoes_jornada
    where funcionario_id=f.id and status='aberta' order by inicio_em desc limit 1 for update;
    if v.id is null then raise exception 'Não existe saída temporária aberta.'; end if;
    update public.movimentacoes_jornada set fim_em=agora,status='encerrada',atualizado_em=agora where id=v.id returning * into v;
  else
    raise exception 'Ação inválida.';
  end if;

  update public.dispositivos_ponto set ultimo_uso_em=agora where id=d.id;
  insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados_novos,origem,descricao)
  values(f.empresa_id,null,'movimentacoes_jornada',v.id::text,upper('MOVIMENTACAO_'||p_acao),
    jsonb_build_object('funcionario_id',f.id,'inicio_em',v.inicio_em,'fim_em',v.fim_em,'motivo',v.motivo_informado,'user_agent',left(p_user_agent,500)),
    'web','Movimentação de jornada registrada pelo funcionário');
  return v;
end $$;

create or replace function public.listar_minhas_movimentacoes(p_token text,p_inicio date,p_fim date)
returns setof public.movimentacoes_jornada
language plpgsql security definer set search_path=public as $$
declare f public.funcionarios%rowtype;
begin
  f:=public.funcionario_por_token(p_token);
  return query select m.* from public.movimentacoes_jornada m
  where m.funcionario_id=f.id and m.data_local between p_inicio and p_fim order by m.inicio_em desc;
end $$;

create or replace function public.listar_movimentacoes_admin(p_inicio date,p_fim date,p_funcionario_id uuid default null,p_pendentes boolean default false)
returns table(
  id uuid,funcionario_id uuid,funcionario_nome text,matricula text,data_local date,inicio_em timestamptz,fim_em timestamptz,
  origem text,motivo_informado text,classificacao text,efeito_calculo text,status text,aprovado boolean,observacao_admin text
)
language plpgsql security definer set search_path=public as $$
declare emp uuid;
begin
  select empresa_id into emp from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
  if emp is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  return query select m.id,m.funcionario_id,f.nome,f.matricula,m.data_local,m.inicio_em,m.fim_em,m.origem,m.motivo_informado,
    m.classificacao,m.efeito_calculo,m.status,m.aprovado,m.observacao_admin
  from public.movimentacoes_jornada m join public.funcionarios f on f.id=m.funcionario_id
  where m.empresa_id=emp and m.data_local between p_inicio and p_fim
    and (p_funcionario_id is null or m.funcionario_id=p_funcionario_id)
    and (not p_pendentes or m.efeito_calculo='pendente' or m.status='aberta')
  order by m.inicio_em desc;
end $$;

create or replace function public.criar_movimentacao_admin(
  p_funcionario_id uuid,p_inicio timestamptz,p_fim timestamptz,p_classificacao text,p_efeito text,p_observacao text default null
)
returns public.movimentacoes_jornada
language plpgsql security definer set search_path=public as $$
declare emp uuid; v public.movimentacoes_jornada%rowtype;
begin
  select empresa_id into emp from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
  if emp is null or not exists(select 1 from public.funcionarios where id=p_funcionario_id and empresa_id=emp) then raise exception 'Funcionário inválido.'; end if;
  if p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  insert into public.movimentacoes_jornada(empresa_id,funcionario_id,data_local,inicio_em,fim_em,origem,classificacao,efeito_calculo,status,aprovado,observacao_admin,criado_por,analisado_por,analisado_em)
  values(emp,p_funcionario_id,(p_inicio at time zone 'America/Sao_Paulo')::date,p_inicio,p_fim,'administrador',p_classificacao,p_efeito,'encerrada',true,p_observacao,auth.uid(),auth.uid(),clock_timestamp()) returning * into v;
  insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados_novos,origem,descricao)
  values(emp,auth.uid(),'movimentacoes_jornada',v.id::text,'MOVIMENTACAO_CRIADA_ADMIN',to_jsonb(v),'web','Justificativa ou movimentação criada pelo administrador');
  return v;
end $$;

create or replace function public.analisar_movimentacao_admin(
  p_id uuid,p_classificacao text,p_efeito text,p_observacao text default null
)
returns public.movimentacoes_jornada
language plpgsql security definer set search_path=public as $$
declare emp uuid; v public.movimentacoes_jornada%rowtype;
begin
  select empresa_id into emp from public.perfis where id=auth.uid() and papel='administrador' and ativo=true;
  if emp is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  update public.movimentacoes_jornada set classificacao=p_classificacao,efeito_calculo=p_efeito,aprovado=true,
    observacao_admin=p_observacao,analisado_por=auth.uid(),analisado_em=clock_timestamp(),atualizado_em=clock_timestamp()
  where id=p_id and empresa_id=emp and status='encerrada' returning * into v;
  if v.id is null then raise exception 'Movimentação não encontrada ou ainda sem retorno.'; end if;
  insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados_novos,origem,descricao)
  values(emp,auth.uid(),'movimentacoes_jornada',v.id::text,'MOVIMENTACAO_ANALISADA',to_jsonb(v),'web','Movimentação classificada pelo administrador');
  return v;
end $$;

-- Atualiza o cálculo: saídas particulares descontam; períodos abonados recompõem a jornada;
-- serviço externo/home office contam como trabalho; hora extra autorizada libera saldo positivo.
create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
  desconto_mov int; abono_mov int; movimentos jsonb; extra_autorizada boolean;
  tot_prev int=0; tot_trab int=0; tot_saldo int=0; credito int=0; debito int=0; trabalhados int=0; faltas int=0; pend int=0;
begin
  if p_inicio is null or p_fim is null or p_fim<p_inicio then raise exception 'Período inválido.'; end if;
  if p_fim-p_inicio>370 then raise exception 'O período máximo permitido é de 370 dias.'; end if;
  select * into f from public.funcionarios where id=p_funcionario_id;
  if f.id is null then raise exception 'Funcionário não encontrado.'; end if;
  select * into e from public.empresas where id=f.empresa_id;
  for d in select gs::date data from generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') gs order by gs loop
    select * into j from public.jornadas where funcionario_id=f.id and dia_semana=extract(isodow from d.data)::smallint and ativo=true limit 1;
    previsto:=case when j.id is null or j.entrada is null then 0 else round(extract(epoch from ((j.inicio_intervalo-j.entrada)+(j.saida-j.fim_intervalo)))/60)::int end;
    ocorr:=null;
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    entrada_real:=case when qtd>=1 then horarios[1] end; entrada_calc:=entrada_real;
    inicio_int:=case when qtd>=2 then horarios[2] end; fim_int:=case when qtd>=3 then horarios[3] end;
    saida_real:=case when qtd>=4 then horarios[4] end; saida_calc:=saida_real;
    if j.id is not null and entrada_real is not null and entrada_real > (d.data+j.entrada) at time zone e.timezone
       and entrada_real <= ((d.data+j.entrada) at time zone e.timezone)+make_interval(mins=>e.tolerancia_entrada_minutos) then
      entrada_calc:=(d.data+j.entrada) at time zone e.timezone; tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null and saida_real < (d.data+j.saida) at time zone e.timezone
       and saida_real >= ((d.data+j.saida) at time zone e.timezone)-make_interval(mins=>e.tolerancia_saida_minutos) then
      saida_calc:=(d.data+j.saida) at time zone e.timezone; tolerancia_aplicada:=true;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;

    select coalesce(sum(case when aprovado and efeito_calculo='descontar' and fim_em is not null then round(extract(epoch from (fim_em-inicio_em))/60)::int else 0 end),0),
           coalesce(sum(case when aprovado and efeito_calculo='abonar' and fim_em is not null then round(extract(epoch from (fim_em-inicio_em))/60)::int else 0 end),0),
           coalesce(bool_or(aprovado and efeito_calculo='credito'),false),
           coalesce(jsonb_agg(jsonb_build_object('id',id,'inicio_em',inicio_em,'fim_em',fim_em,'classificacao',classificacao,'efeito',efeito_calculo,'status',status,'aprovado',aprovado) order by inicio_em),'[]'::jsonb)
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada where funcionario_id=f.id and data_local=d.data and status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then status:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then status:='aguardando'; else status:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0 and not e.horas_extras_automaticas and not extra_autorizada then saldo:=0; end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int,
      'movimentacoes',movimentos,'minutos_descontados',desconto_mov,'minutos_abonados',abono_mov,'hora_extra_autorizada',extra_autorizada));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end $$;

revoke all on table public.movimentacoes_jornada from anon,authenticated;
revoke all on function public.registrar_movimentacao_dispositivo(text,text,text,text,text) from public;
revoke all on function public.listar_minhas_movimentacoes(text,date,date) from public;
revoke all on function public.listar_movimentacoes_admin(date,date,uuid,boolean) from public,anon;
revoke all on function public.criar_movimentacao_admin(uuid,timestamptz,timestamptz,text,text,text) from public,anon;
revoke all on function public.analisar_movimentacao_admin(uuid,text,text,text) from public,anon;
grant execute on function public.registrar_movimentacao_dispositivo(text,text,text,text,text) to anon,authenticated;
grant execute on function public.listar_minhas_movimentacoes(text,date,date) to anon,authenticated;
grant execute on function public.listar_movimentacoes_admin(date,date,uuid,boolean) to authenticated;
grant execute on function public.criar_movimentacao_admin(uuid,timestamptz,timestamptz,text,text,text) to authenticated;
grant execute on function public.analisar_movimentacao_admin(uuid,text,text,text) to authenticated;

commit;
