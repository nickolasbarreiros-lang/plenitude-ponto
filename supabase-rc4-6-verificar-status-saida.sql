-- Verificação da instalação e do estado atual da matrícula 999.

select
  to_regprocedure('public.status_movimentacao_funcionario(text)') is not null
    as rpc_status_instalada,
  to_regprocedure(
    'public.registrar_movimentacao_dispositivo(text,text,text,text,text)'
  ) is not null as rpc_registro_instalada;

select
  f.nome,
  f.matricula,
  mj.id,
  mj.data_local,
  mj.inicio_em,
  mj.fim_em,
  mj.motivo_informado,
  mj.status
from public.funcionarios f
join public.movimentacoes_jornada mj
  on mj.funcionario_id=f.id
where f.matricula='999'
  and mj.status='aberta'
order by mj.data_local desc,mj.inicio_em desc;
