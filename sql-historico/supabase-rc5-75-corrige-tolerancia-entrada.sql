-- ============================================================
-- PLENITUDE PONTO RC5.75
-- CORREÇÃO DA TOLERÂNCIA DE ENTRADA NO BANCO DE HORAS
-- ============================================================
--
-- Regra:
-- - horário real continua registrado e visível;
-- - entrada dentro da tolerância é considerada como a hora prevista
--   somente para cálculo de horas/saldo;
-- - entrada depois do limite usa o horário real;
-- - não altera marcações gravadas.
--
-- Após executar, relatórios e espelhos são recalculados automaticamente
-- quando forem abertos novamente.

begin;

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
    /*
     * Tolerância de entrada:
     * - mantém o horário REAL registrado;
     * - para o cálculo, considera a entrada prevista quando a marcação ocorreu
     *   do primeiro segundo após a hora prevista até o final do minuto-limite.
     *
     * Exemplo com jornada 09:00 e tolerância 10:
     * 09:00:01 até 09:10:59 => entrada considerada 09:00.
     * 09:11:00 em diante     => utiliza o horário real.
     */
    if j.id is not null and entrada_real is not null
       and entrada_real > ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and entrada_real < (
         ((d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         + make_interval(mins=>coalesce(e.tolerancia_entrada_minutos,0)+1)
       ) then
      entrada_calc:=(d.data+j.entrada) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
    end if;
    if j.id is not null and saida_real is not null
       and saida_real < ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
       and saida_real >= (
         ((d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo'))
         - make_interval(mins=>coalesce(e.tolerancia_saida_minutos,0))
       ) then
      saida_calc:=(d.data+j.saida) at time zone coalesce(e.timezone,'America/Sao_Paulo');
      tolerancia_aplicada:=true;
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

revoke all on function public._calcular_banco_horas_json(uuid,date,date)
from public,anon,authenticated;

commit;

notify pgrst,'reload schema';
