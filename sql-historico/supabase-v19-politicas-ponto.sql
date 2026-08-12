-- PLENITUDE PONTO V19 — POLÍTICAS DE PONTO E TOLERÂNCIAS
-- Execute integralmente no SQL Editor do Supabase.

alter table public.empresas
  add column if not exists tolerancia_entrada_minutos integer not null default 15,
  add column if not exists tolerancia_saida_minutos integer not null default 10,
  add column if not exists intervalo_minimo_minutos integer not null default 60,
  add column if not exists intervalo_maximo_minutos integer not null default 120,
  add column if not exists horas_extras_automaticas boolean not null default true,
  add column if not exists limite_banco_horas_minutos integer not null default 2400;

alter table public.empresas drop constraint if exists empresas_tolerancia_entrada_check;
alter table public.empresas add constraint empresas_tolerancia_entrada_check check (tolerancia_entrada_minutos between 0 and 120);
alter table public.empresas drop constraint if exists empresas_tolerancia_saida_check;
alter table public.empresas add constraint empresas_tolerancia_saida_check check (tolerancia_saida_minutos between 0 and 120);
alter table public.empresas drop constraint if exists empresas_intervalo_check;
alter table public.empresas add constraint empresas_intervalo_check check (intervalo_minimo_minutos between 0 and intervalo_maximo_minutos and intervalo_maximo_minutos <= 360);
alter table public.empresas drop constraint if exists empresas_limite_banco_check;
alter table public.empresas add constraint empresas_limite_banco_check check (limite_banco_horas_minutos between 0 and 60000);

create or replace function public.salvar_politicas_ponto(
  p_tolerancia_entrada integer,
  p_tolerancia_saida integer,
  p_intervalo_minimo integer,
  p_intervalo_maximo integer,
  p_horas_extras_automaticas boolean,
  p_limite_banco_horas integer
)
returns public.empresas
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
  v_result public.empresas%rowtype;
begin
  select empresa_id into v_empresa from public.perfis
  where id=auth.uid() and papel='administrador' and ativo=true;
  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  if p_tolerancia_entrada not between 0 and 120 or p_tolerancia_saida not between 0 and 120 then
    raise exception 'As tolerâncias devem ficar entre 0 e 120 minutos.';
  end if;
  if p_intervalo_minimo < 0 or p_intervalo_maximo < p_intervalo_minimo or p_intervalo_maximo > 360 then
    raise exception 'Configuração de intervalo inválida.';
  end if;
  update public.empresas set
    tolerancia_entrada_minutos=p_tolerancia_entrada,
    tolerancia_saida_minutos=p_tolerancia_saida,
    intervalo_minimo_minutos=p_intervalo_minimo,
    intervalo_maximo_minutos=p_intervalo_maximo,
    horas_extras_automaticas=p_horas_extras_automaticas,
    limite_banco_horas_minutos=p_limite_banco_horas,
    atualizada_em=clock_timestamp()
  where id=v_empresa returning * into v_result;
  insert into public.logs_auditoria(empresa_id,usuario_id,acao,tabela,registro_id,dados_novos)
  values(v_empresa,auth.uid(),'POLITICAS_PONTO_ATUALIZADAS','empresas',v_empresa,
    jsonb_build_object('tolerancia_entrada',p_tolerancia_entrada,'tolerancia_saida',p_tolerancia_saida,
    'intervalo_minimo',p_intervalo_minimo,'intervalo_maximo',p_intervalo_maximo,
    'horas_extras_automaticas',p_horas_extras_automaticas,'limite_banco_horas',p_limite_banco_horas));
  return v_result;
end; $$;

grant execute on function public.salvar_politicas_ponto(integer,integer,integer,integer,boolean,integer) to authenticated;

-- Substitui o cálculo da V17, preservando o horário real e usando a tolerância somente no cálculo.
create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
  inicio_int timestamptz; fim_int timestamptz; int_min int; alerta_int text; tolerancia_aplicada boolean;
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
    select o.tipo::text into ocorr from public.ocorrencias o where o.funcionario_id=f.id and o.aprovado=true and d.data between o.data_inicio and o.data_fim order by o.criado_em desc limit 1;
    if ocorr in ('folga','ferias','feriado','atestado') then previsto:=0; end if;
    select count(*)::int,array_agg(m.tipo order by m.registrado_em),array_agg(m.registrado_em order by m.registrado_em)
      into qtd,tipos,horarios from public.marcacoes m where m.funcionario_id=f.id and m.data_local=d.data;
    trabalhado:=0; saldo:=null; alerta_int:=null; tolerancia_aplicada:=false;
    if qtd>=1 then entrada_real:=horarios[1]; entrada_calc:=entrada_real; else entrada_real:=null; entrada_calc:=null; end if;
    if qtd>=2 then inicio_int:=horarios[2]; else inicio_int:=null; end if;
    if qtd>=3 then fim_int:=horarios[3]; else fim_int:=null; end if;
    if qtd>=4 then saida_real:=horarios[4]; saida_calc:=saida_real; else saida_real:=null; saida_calc:=null; end if;
    if j.id is not null and entrada_real is not null then
      if entrada_real > (d.data+j.entrada) at time zone e.timezone and entrada_real <= ((d.data+j.entrada) at time zone e.timezone)+make_interval(mins=>e.tolerancia_entrada_minutos) then
        entrada_calc:=(d.data+j.entrada) at time zone e.timezone; tolerancia_aplicada:=true;
      end if;
    end if;
    if j.id is not null and saida_real is not null then
      if saida_real < (d.data+j.saida) at time zone e.timezone and saida_real >= ((d.data+j.saida) at time zone e.timezone)-make_interval(mins=>e.tolerancia_saida_minutos) then
        saida_calc:=(d.data+j.saida) at time zone e.timezone; tolerancia_aplicada:=true;
      end if;
    end if;
    if qtd>=2 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (inicio_int-entrada_calc))/60)::int); end if;
    if qtd>=4 then trabalhado:=trabalhado+greatest(0,round(extract(epoch from (saida_calc-fim_int))/60)::int); end if;
    if qtd>=3 then
      int_min:=round(extract(epoch from (fim_int-inicio_int))/60)::int;
      if int_min<e.intervalo_minimo_minutos then alerta_int:='intervalo_curto'; elsif int_min>e.intervalo_maximo_minutos then alerta_int:='intervalo_excedido'; end if;
    else int_min:=null; end if;
    if ocorr in ('folga','ferias','feriado','atestado') then status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then status:='falta'; saldo:=-previsto; faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then status:='aguardando'; else status:='futuro'; end if;
    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0 and not e.horas_extras_automaticas then saldo:=0; end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',status,'ocorrencia',ocorr,
      'marcacoes',coalesce(to_jsonb(horarios),'[]'::jsonb),'tipos',coalesce(to_jsonb(tipos),'[]'::jsonb),
      'entrada_real',entrada_real,'entrada_considerada',entrada_calc,'saida_real',saida_real,'saida_considerada',saida_calc,
      'tolerancia_aplicada',tolerancia_aplicada,'intervalo_minutos',int_min,'alerta_intervalo',alerta_int));
  end loop;
  resumo:=jsonb_build_object('funcionario_id',f.id,'funcionario_nome',f.nome,'matricula',f.matricula,'inicio',p_inicio,'fim',p_fim,
    'previsto_minutos',tot_prev,'trabalhado_minutos',tot_trab,'saldo_minutos',tot_saldo,'credito_minutos',credito,'debito_minutos',debito,
    'dias_trabalhados',trabalhados,'faltas',faltas,'pendencias',pend,'limite_banco_horas_minutos',e.limite_banco_horas_minutos,
    'limite_banco_excedido',abs(tot_saldo)>e.limite_banco_horas_minutos);
  return jsonb_build_object('resumo',resumo,'dias',dias);
end; $$;

revoke all on function public._calcular_banco_horas_json(uuid,date,date) from public,anon,authenticated;
