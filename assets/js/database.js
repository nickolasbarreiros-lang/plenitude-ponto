(function(){
  'use strict';
  const client=window.PlenitudeAuth?.client;
  if(!client) throw new Error('Cliente Supabase não inicializado.');

  async function profile(){
    const {data:{user},error:userError}=await client.auth.getUser();
    if(userError) throw userError;
    if(!user) throw new Error('Sessão não encontrada.');
    const {data,error}=await client.from('perfis').select('id,nome,papel,empresa_id,empresas(nome_fantasia,razao_social,endereco,cidade,uf)').eq('id',user.id).single();
    if(error) throw error;
    return {...data,email:user.email};
  }

  async function employees(){
    const {data,error}=await client.from('funcionarios').select('*').order('nome');
    if(error) throw error;
    return data||[];
  }

  async function saveEmployee(values,id=null){
    const p=await profile();
    const payload={
      empresa_id:p.empresa_id,
      nome:values.nome,
      cpf:values.cpf||null,
      cargo:values.cargo||null,
      data_admissao:values.admissao||null,
      matricula:values.matricula||null,
      carga_semanal_minutos:2640,
      ativo:true
    };
    let query=id?client.from('funcionarios').update(payload).eq('id',id):client.from('funcionarios').insert(payload);
    const {data,error}=await query.select().single();
    if(error) throw error;
    return data;
  }

  async function schedules(employeeId){
    const {data,error}=await client.from('jornadas').select('*').eq('funcionario_id',employeeId).order('dia_semana');
    if(error) throw error;
    return data||[];
  }

  async function saveSchedules(employeeId,rows){
    const p=await profile();
    const payload=rows.map((r,i)=>({
      empresa_id:p.empresa_id,
      funcionario_id:employeeId,
      dia_semana:i+1,
      entrada:r.entrada,
      inicio_intervalo:r.almoco,
      fim_intervalo:r.retorno,
      saida:r.saida,
      ativo:true
    }));
    const {data,error}=await client.from('jornadas').upsert(payload,{onConflict:'funcionario_id,dia_semana'}).select();
    if(error) throw error;
    return data||[];
  }

  async function marksForRange(start,end){
    const {data,error}=await client.from('marcacoes').select('*').gte('data_local',start).lte('data_local',end).order('registrado_em');
    if(error) throw error;
    return data||[];
  }

  window.PlenitudeDB=Object.freeze({profile,employees,saveEmployee,schedules,saveSchedules,marksForRange});
})();
