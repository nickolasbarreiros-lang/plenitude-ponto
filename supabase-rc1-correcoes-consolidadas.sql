-- PLENITUDE PONTO 1.0.0 RC1
-- Correções consolidadas e idempotentes. Execute o arquivo inteiro no SQL Editor.

-- ============================================================
-- Fonte consolidada: supabase-v26-v27-correcao-ativo-ambiguo.sql
-- ============================================================
-- Correção V26/V27 — referência ambígua à coluna "ativo"
-- Execute após as versões V26 e V27.

begin;

create or replace function public.autorizar_dispositivo_ponto_admin(
  p_token text,
  p_nome text,
  p_user_agent text default null
)
returns table(id uuid,nome text,ativo boolean,autorizado_em timestamptz)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_empresa uuid;
  v_id uuid;
begin
  if not public.usuario_e_admin() then
    raise exception 'Apenas administradores podem autorizar dispositivos.';
  end if;

  if length(coalesce(p_token,'')) < 32 then
    raise exception 'Token de dispositivo inválido.';
  end if;

  v_empresa := public.empresa_do_usuario();
  if v_empresa is null then
    raise exception 'Empresa não identificada.';
  end if;

  -- Somente uma máquina ativa por empresa.
  update public.dispositivos_ponto as dp
     set ativo = false,
         revogado_em = clock_timestamp()
   where dp.empresa_id = v_empresa
     and dp.ativo = true;

  insert into public.dispositivos_ponto as dp (
    empresa_id,
    nome,
    token_hash,
    ativo,
    autorizado_por,
    user_agent_autorizacao
  ) values (
    v_empresa,
    coalesce(nullif(trim(p_nome),''),'Computador da loja'),
    encode(digest(p_token,'sha256'),'hex'),
    true,
    auth.uid(),
    left(p_user_agent,1000)
  )
  returning dp.id into v_id;

  perform public.registrar_evento_auditoria(
    'AUTORIZAR',
    'dispositivos_ponto',
    v_id::text,
    'Computador autorizado para registrar ponto',
    jsonb_build_object(
      'nome',coalesce(nullif(trim(p_nome),''),'Computador da loja')
    ),
    'web'
  );

  return query
  select dp.id, dp.nome, dp.ativo, dp.autorizado_em
    from public.dispositivos_ponto as dp
   where dp.id = v_id;
end;
$$;

-- Mantém a proteção da V27: a função-base não pode ser chamada diretamente.
revoke execute on function public.autorizar_dispositivo_ponto_admin(text,text,text)
  from authenticated, anon, public;

-- O wrapper com PIN Mestre continua sendo o ponto de entrada autorizado.
grant execute on function public.autorizar_dispositivo_ponto_master_admin(text,text,text,text)
  to authenticated;

commit;

-- ============================================================
-- Fonte consolidada: supabase-v29-correcao-tipo-retorno-pin.sql
-- ============================================================
begin;

-- Correção V29: a função já existia com outro tipo de retorno.
-- PostgreSQL exige DROP FUNCTION antes de recriá-la com novo RETURNS TABLE.

drop function if exists public.admin_definir_pin(uuid,text,boolean,boolean);

create or replace function public.admin_definir_pin(
  p_funcionario_id uuid,
  p_pin text,
  p_exigir_troca boolean default false,
  p_acesso_ativo boolean default true
)
returns table(
  id uuid,
  matricula text,
  acesso_ponto_ativo boolean,
  exigir_troca_pin boolean,
  pin_configurado boolean
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Sessão administrativa obrigatória.';
  end if;

  select p.empresa_id
    into v_empresa
  from public.perfis p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true;

  if v_empresa is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    raise exception 'O PIN deve conter exatamente 4 números.';
  end if;

  update public.funcionarios f
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
         acesso_ponto_ativo = coalesce(p_acesso_ativo, true),
         exigir_troca_pin = coalesce(p_exigir_troca, false),
         tentativas_pin = 0,
         bloqueado_ate = null
   where f.id = p_funcionario_id
     and f.empresa_id = v_empresa;

  if not found then
    raise exception 'Funcionário não encontrado ou não pertence à sua empresa.';
  end if;

  insert into public.logs_auditoria(
    empresa_id, usuario_id, acao, tabela, registro_id, dados_novos
  ) values (
    v_empresa,
    auth.uid(),
    'PIN_REDEFINIDO',
    'funcionarios',
    p_funcionario_id,
    jsonb_build_object(
      'exigir_troca', coalesce(p_exigir_troca, false),
      'acesso_ativo', coalesce(p_acesso_ativo, true),
      'pin_configurado', true
    )
  );

  return query
  select
    f.id,
    f.matricula,
    f.acesso_ponto_ativo,
    f.exigir_troca_pin,
    (f.pin_hash is not null)
  from public.funcionarios f
  where f.id = p_funcionario_id
    and f.empresa_id = v_empresa;
end;
$$;

revoke all on function public.admin_definir_pin(uuid,text,boolean,boolean)
from public, anon;

grant execute on function public.admin_definir_pin(uuid,text,boolean,boolean)
to authenticated;

commit;

-- ============================================================
-- Fonte consolidada: supabase-correcao-login-matricula-pin.sql
-- ============================================================
begin;

-- Corrige o login do funcionário para:
-- 1) aceitar matrícula com ou sem zeros à esquerda (001 = 0001);
-- 2) validar PIN usando apenas algarismos;
-- 3) acessar corretamente as funções do pgcrypto no schema extensions.
create or replace function public.login_funcionario_pin(p_matricula text,p_pin text)
returns table(
  token text,
  funcionario_id uuid,
  nome text,
  cargo text,
  matricula text,
  foto_url text,
  exigir_troca_pin boolean,
  expira_em timestamptz
)
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  f public.funcionarios%rowtype;
  v_token text;
  v_now timestamptz:=clock_timestamp();
  v_matricula_normalizada text;
begin
  if coalesce(p_pin,'') !~ '^[0-9]{4}$' then
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  -- Remove espaços e zeros à esquerda. Mantém "0" quando a matrícula for só zeros.
  v_matricula_normalizada := coalesce(nullif(ltrim(btrim(coalesce(p_matricula,'')),'0'),''),'0');

  select fun.*
    into f
    from public.funcionarios fun
   where fun.ativo=true
     and coalesce(nullif(ltrim(btrim(fun.matricula),'0'),''),'0')=v_matricula_normalizada
   order by fun.criado_em asc nulls last
   limit 1;

  if f.id is null or f.pin_hash is null then
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  if not f.acesso_ponto_ativo then
    raise exception 'Acesso ao ponto bloqueado. Procure o administrador.';
  end if;

  if f.bloqueado_ate is not null and f.bloqueado_ate>v_now then
    raise exception 'Acesso temporariamente bloqueado. Tente novamente mais tarde.';
  end if;

  if extensions.crypt(p_pin,f.pin_hash)<>f.pin_hash then
    update public.funcionarios fun
       set tentativas_pin=coalesce(fun.tentativas_pin,0)+1,
           bloqueado_ate=case
             when coalesce(fun.tentativas_pin,0)+1>=5 then v_now+interval '15 minutes'
             else null
           end
     where fun.id=f.id;
    raise exception 'Matrícula ou PIN incorretos.';
  end if;

  update public.funcionarios fun
     set tentativas_pin=0,
         bloqueado_ate=null,
         ultimo_acesso_em=v_now
   where fun.id=f.id;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');

  insert into public.sessoes_funcionario(funcionario_id,token_hash,expira_em)
  values(
    f.id,
    encode(extensions.digest(v_token,'sha256'),'hex'),
    v_now+interval '12 hours'
  );

  return query
  select v_token,f.id,f.nome,f.cargo,f.matricula,f.foto_url,
         f.exigir_troca_pin,v_now+interval '12 hours';
end $$;

revoke all on function public.login_funcionario_pin(text,text) from public,anon,authenticated;
-- A função direta permanece bloqueada para o navegador.
-- login_funcionario_pin_dispositivo() continua chamando-a internamente como SECURITY DEFINER.

commit;

-- ============================================================
-- Fonte consolidada: supabase-v30-2-correcao-status-banco-horas.sql
-- ============================================================
begin;

-- Correção V30.2
-- O erro "column reference status is ambiguous" vinha do cálculo do banco de horas.
-- A função possuía uma variável local chamada status e também consultava
-- movimentacoes_jornada.status sem alias. Agora todas as referências são explícitas.

create or replace function public._calcular_banco_horas_json(p_funcionario_id uuid,p_inicio date,p_fim date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  f public.funcionarios%rowtype; e public.empresas%rowtype; d record; j public.jornadas%rowtype;
  dias jsonb='[]'::jsonb; resumo jsonb; previsto int; trabalhado int; saldo int; qtd int; horarios timestamptz[]; tipos public.tipo_marcacao[];
  ocorr text; v_status text; entrada_real timestamptz; entrada_calc timestamptz; saida_real timestamptz; saida_calc timestamptz;
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

    select coalesce(sum(case when mj.aprovado and mj.efeito_calculo='descontar' and mj.fim_em is not null then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int else 0 end),0),
           coalesce(sum(case when mj.aprovado and mj.efeito_calculo='abonar' and mj.fim_em is not null then round(extract(epoch from (mj.fim_em-mj.inicio_em))/60)::int else 0 end),0),
           coalesce(bool_or(mj.aprovado and mj.efeito_calculo='credito'),false),
           coalesce(jsonb_agg(jsonb_build_object('id',mj.id,'inicio_em',mj.inicio_em,'fim_em',mj.fim_em,'classificacao',mj.classificacao,'efeito',mj.efeito_calculo,'status',mj.status,'aprovado',mj.aprovado) order by mj.inicio_em),'[]'::jsonb)
      into desconto_mov,abono_mov,extra_autorizada,movimentos
    from public.movimentacoes_jornada as mj where mj.funcionario_id=f.id and mj.data_local=d.data and mj.status<>'cancelada';

    trabalhado:=greatest(0,trabalhado-desconto_mov)+abono_mov;
    if previsto>0 then trabalhado:=least(trabalhado,previsto+greatest(0,trabalhado-previsto)); end if;

    if ocorr in ('folga','ferias','feriado','atestado') then v_status:=ocorr; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif previsto=0 then v_status:=case when qtd>0 then 'extra' else 'sem_jornada' end; saldo:=case when qtd=4 then trabalhado else 0 end;
    elsif qtd=4 then v_status:='completo'; saldo:=trabalhado-previsto; trabalhados:=trabalhados+1;
    elsif d.data<(clock_timestamp() at time zone e.timezone)::date and qtd=0 then v_status:='falta'; saldo:=-greatest(0,previsto-abono_mov); faltas:=faltas+1;
    elsif d.data<=(clock_timestamp() at time zone e.timezone)::date and qtd between 1 and 3 then v_status:='pendente'; pend:=pend+1;
    elsif d.data=(clock_timestamp() at time zone e.timezone)::date then v_status:='aguardando'; else v_status:='futuro'; end if;

    if d.data<=(clock_timestamp() at time zone e.timezone)::date then
      tot_prev:=tot_prev+previsto; tot_trab:=tot_trab+trabalhado;
      if saldo is not null then
        if saldo>0 and not e.horas_extras_automaticas and not extra_autorizada then saldo:=0; end if;
        tot_saldo:=tot_saldo+saldo; if saldo>0 then credito:=credito+saldo; elsif saldo<0 then debito:=debito+abs(saldo); end if;
      end if;
    end if;
    dias:=dias||jsonb_build_array(jsonb_build_object('data',d.data,'dia_semana',extract(isodow from d.data)::int,'previsto_minutos',previsto,
      'trabalhado_minutos',trabalhado,'saldo_minutos',saldo,'quantidade_marcacoes',qtd,'status',v_status,'ocorrencia',ocorr,
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
from public, anon, authenticated;

commit;

-- ============================================================
-- Fonte consolidada: supabase-v30-3-instalar-modulo-ajustes-completo.sql
-- ============================================================
begin;

-- V30.3 corrigida
-- Instala o módulo de solicitações de ajuste que está ausente no banco.
-- O erro anterior ocorreu porque a tabela public.solicitacoes_ajuste não existia.

create table if not exists public.solicitacoes_ajuste (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  data_marcacao date not null,
  tipo_marcacao public.tipo_marcacao not null,
  horario_solicitado time not null,
  justificativa text not null,
  status text not null default 'pendente' check (status in ('pendente','aprovada','rejeitada','cancelada')),
  resposta_administrador text,
  marcacao_gerada_id bigint references public.marcacoes(id) on delete set null,
  analisado_por uuid references auth.users(id) on delete set null,
  analisado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (char_length(btrim(justificativa)) between 10 and 1000)
);

create index if not exists idx_solicitacoes_ajuste_empresa_status
  on public.solicitacoes_ajuste(empresa_id,status,criado_em desc);
create index if not exists idx_solicitacoes_ajuste_funcionario
  on public.solicitacoes_ajuste(funcionario_id,data_marcacao desc);

alter table public.solicitacoes_ajuste enable row level security;
revoke all on public.solicitacoes_ajuste from anon, authenticated;

create or replace function public.atualizar_timestamp_ajuste()
returns trigger language plpgsql set search_path = public, extensions as $$
begin new.atualizado_em := clock_timestamp(); return new; end $$;

drop trigger if exists trg_atualizar_solicitacao_ajuste on public.solicitacoes_ajuste;
create trigger trg_atualizar_solicitacao_ajuste
before update on public.solicitacoes_ajuste
for each row execute function public.atualizar_timestamp_ajuste();

create or replace function public.solicitar_ajuste_ponto(
  p_token text,
  p_data date,
  p_tipo public.tipo_marcacao,
  p_horario time,
  p_justificativa text
)
returns public.solicitacoes_ajuste
language plpgsql security definer set search_path = public, extensions as $$
declare
  f public.funcionarios%rowtype;
  s public.solicitacoes_ajuste%rowtype;
begin
  f := public.funcionario_por_token(p_token);
  if p_data > (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Não é possível solicitar ajuste para uma data futura.';
  end if;
  if char_length(btrim(coalesce(p_justificativa,''))) < 10 then
    raise exception 'Informe uma justificativa com pelo menos 10 caracteres.';
  end if;
  if exists(select 1 from public.marcacoes as m where m.funcionario_id=f.id and m.data_local=p_data and m.tipo=p_tipo) then
    raise exception 'Essa marcação já existe. Para alterar um horário existente, procure o administrador.';
  end if;
  if exists(select 1 from public.solicitacoes_ajuste as s where s.funcionario_id=f.id and s.data_marcacao=p_data and s.tipo_marcacao=p_tipo and s.status='pendente') then
    raise exception 'Já existe uma solicitação pendente para essa marcação.';
  end if;
  insert into public.solicitacoes_ajuste(empresa_id,funcionario_id,data_marcacao,tipo_marcacao,horario_solicitado,justificativa)
  values(f.empresa_id,f.id,p_data,p_tipo,p_horario,btrim(p_justificativa)) returning * into s;
  return s;
end $$;

create or replace function public.listar_meus_ajustes(p_token text)
returns setof public.solicitacoes_ajuste
language plpgsql security definer set search_path = public, extensions as $$
declare f public.funcionarios%rowtype;
begin
  f := public.funcionario_por_token(p_token);
  return query select s.* from public.solicitacoes_ajuste as s where s.funcionario_id=f.id order by s.criado_em desc limit 50;
end $$;

create or replace function public.listar_ajustes_admin(p_status text default null)
returns table(
  id uuid, funcionario_id uuid, funcionario_nome text, matricula text,
  data_marcacao date, tipo_marcacao public.tipo_marcacao, horario_solicitado time,
  justificativa text, status text, resposta_administrador text,
  criado_em timestamptz, analisado_em timestamptz
)
language plpgsql security definer set search_path = public, extensions as $$
declare v_empresa uuid;
begin
  select empresa_id into v_empresa from public.perfis
  where id=auth.uid() and papel='administrador' and ativo=true;
  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  return query
  select s.id,s.funcionario_id,f.nome,f.matricula,s.data_marcacao,s.tipo_marcacao,
         s.horario_solicitado,s.justificativa,s.status,s.resposta_administrador,
         s.criado_em,s.analisado_em
  from public.solicitacoes_ajuste s join public.funcionarios f on f.id=s.funcionario_id
  where s.empresa_id=v_empresa and (p_status is null or p_status='' or s.status=p_status)
  order by case when s.status='pendente' then 0 else 1 end,s.criado_em desc;
end $$;

create or replace function public.analisar_ajuste_ponto(
  p_solicitacao_id uuid,
  p_decisao text,
  p_resposta text default null
)
returns public.solicitacoes_ajuste
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_empresa uuid;
  s public.solicitacoes_ajuste%rowtype;
  v_marcacao_id bigint;
  v_instante timestamptz;
begin
  select empresa_id into v_empresa from public.perfis
  where id=auth.uid() and papel='administrador' and ativo=true;
  if v_empresa is null then raise exception 'Acesso administrativo não autorizado.'; end if;
  if p_decisao not in ('aprovada','rejeitada') then raise exception 'Decisão inválida.'; end if;
  select * into s from public.solicitacoes_ajuste where id=p_solicitacao_id and empresa_id=v_empresa for update;
  if s.id is null then raise exception 'Solicitação não encontrada.'; end if;
  if s.status <> 'pendente' then raise exception 'Esta solicitação já foi analisada.'; end if;

  if p_decisao='aprovada' then
    if exists(select 1 from public.marcacoes as m where m.funcionario_id=s.funcionario_id and m.data_local=s.data_marcacao and m.tipo=s.tipo_marcacao) then
      raise exception 'A marcação solicitada já existe e a aprovação foi interrompida.';
    end if;
    v_instante := (s.data_marcacao + s.horario_solicitado) at time zone 'America/Sao_Paulo';
    insert into public.marcacoes(empresa_id,funcionario_id,tipo,registrado_em,data_local,origem,observacao,criado_por,ajustada)
    values(s.empresa_id,s.funcionario_id,s.tipo_marcacao,v_instante,s.data_marcacao,'ajuste_aprovado',
      'Incluída pela solicitação '||s.id::text||'. Justificativa: '||s.justificativa,auth.uid(),true)
    returning id into v_marcacao_id;
  end if;

  update public.solicitacoes_ajuste set status=p_decisao,resposta_administrador=nullif(btrim(coalesce(p_resposta,'')),''),
    marcacao_gerada_id=v_marcacao_id,analisado_por=auth.uid(),analisado_em=clock_timestamp()
  where id=s.id returning * into s;

  insert into public.logs_auditoria(empresa_id,usuario_id,tabela,registro_id,acao,dados)
  values(v_empresa,auth.uid(),'solicitacoes_ajuste',s.id::text,upper(p_decisao),
    jsonb_build_object('funcionario_id',s.funcionario_id,'data',s.data_marcacao,'tipo',s.tipo_marcacao,'horario',s.horario_solicitado,'marcacao_id',v_marcacao_id));
  return s;
end $$;

grant execute on function public.solicitar_ajuste_ponto(text,date,public.tipo_marcacao,time,text) to anon,authenticated;
grant execute on function public.listar_meus_ajustes(text) to anon,authenticated;
grant execute on function public.listar_ajustes_admin(text) to authenticated;
grant execute on function public.analisar_ajuste_ponto(uuid,text,text) to authenticated;


commit;

notify pgrst, 'reload schema';

-- ============================================================
-- Fonte consolidada: supabase-v31-1-corrigir-ajustes-pendentes-admin.sql
-- ============================================================
begin;

-- Correção V31.1
-- Corrige a função usada no painel administrativo para contar/listar
-- solicitações de ajuste pendentes. Todas as colunas recebem alias e
-- conversões explícitas para evitar erro 400 do PostgREST.

create or replace function public.listar_ajustes_admin(
  p_status text default null
)
returns table(
  id uuid,
  funcionario_id uuid,
  funcionario_nome text,
  matricula text,
  data_marcacao date,
  tipo_marcacao public.tipo_marcacao,
  horario_solicitado time,
  justificativa text,
  status text,
  resposta_administrador text,
  criado_em timestamptz,
  analisado_em timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_empresa_id uuid;
begin
  select p.empresa_id
    into v_empresa_id
  from public.perfis as p
  where p.id = auth.uid()
    and p.papel = 'administrador'
    and p.ativo = true
  limit 1;

  if v_empresa_id is null then
    raise exception 'Acesso administrativo não autorizado.';
  end if;

  return query
  select
    s.id::uuid,
    s.funcionario_id::uuid,
    f.nome::text,
    f.matricula::text,
    s.data_marcacao::date,
    s.tipo_marcacao::public.tipo_marcacao,
    s.horario_solicitado::time,
    s.justificativa::text,
    s.status::text,
    s.resposta_administrador::text,
    s.criado_em::timestamptz,
    s.analisado_em::timestamptz
  from public.solicitacoes_ajuste as s
  inner join public.funcionarios as f
    on f.id = s.funcionario_id
  where s.empresa_id = v_empresa_id
    and (
      p_status is null
      or btrim(p_status) = ''
      or s.status::text = p_status
    )
  order by
    case when s.status::text = 'pendente' then 0 else 1 end,
    s.criado_em desc;
end;
$$;

revoke all on function public.listar_ajustes_admin(text)
from public, anon;

grant execute on function public.listar_ajustes_admin(text)
to authenticated;

commit;

notify pgrst, 'reload schema';

notify pgrst, 'reload schema';
