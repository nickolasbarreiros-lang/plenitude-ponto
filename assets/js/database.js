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

  async function employeePhotoUrl(path){
    if(!path) return null;
    if(/^https?:\/\//i.test(path)||path.startsWith('data:')) return path;
    const {data,error}=await client.storage.from('funcionarios').createSignedUrl(path,3600);
    if(error) return null;
    return data?.signedUrl||null;
  }

  async function attachPhoto(employee){
    if(!employee) return employee;
    return {...employee,foto_resolvida:await employeePhotoUrl(employee.foto_url)};
  }


  async function ownEmployee(){
    const {data:{user},error:userError}=await client.auth.getUser();
    if(userError) throw userError;
    if(!user) throw new Error('Sessão não encontrada.');
    const {data,error}=await client.from('funcionarios').select('*').eq('auth_user_id',user.id).maybeSingle();
    if(error) throw error;
    return attachPhoto(data);
  }

  async function employees(){
    const {data,error}=await client.from('funcionarios').select('*').order('nome');
    if(error) throw error;
    return Promise.all((data||[]).map(attachPhoto));
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
      ativo:values.status!=='inativo',
      status:values.status||'ativo',
      foto_url:values.foto_url||null,
      codigo_qr:values.codigo_qr||null
    };
    let query=id?client.from('funcionarios').update(payload).eq('id',id):client.from('funcionarios').insert(payload);
    const {data,error}=await query.select().single();
    if(error) throw error;
    return attachPhoto(data);
  }

  async function uploadEmployeePhoto(employeeId,dataUrl){
    if(!employeeId||!dataUrl) throw new Error('Funcionário ou imagem inválida.');
    const p=await profile();
    const blob=await (await fetch(dataUrl)).blob();
    const path=`${p.empresa_id}/${employeeId}/perfil.jpg`;
    const {error:uploadError}=await client.storage.from('funcionarios').upload(path,blob,{contentType:'image/jpeg',upsert:true,cacheControl:'3600'});
    if(uploadError) throw uploadError;
    const {data,error}=await client.from('funcionarios').update({foto_url:path}).eq('id',employeeId).select().single();
    if(error) throw error;
    return attachPhoto(data);
  }

  async function removeEmployeePhoto(employee){
    if(!employee?.id) return employee;
    if(employee.foto_url&&!/^https?:|^data:/i.test(employee.foto_url)){
      const {error:storageError}=await client.storage.from('funcionarios').remove([employee.foto_url]);
      if(storageError&&!String(storageError.message||'').includes('not found')) throw storageError;
    }
    const {data,error}=await client.from('funcionarios').update({foto_url:null}).eq('id',employee.id).select().single();
    if(error) throw error;
    return attachPhoto(data);
  }

  async function linkEmployeeAccess(employeeId,email){
    if(!employeeId||!email) throw new Error('Informe o funcionário e o e-mail da conta.');
    const {data,error}=await client.rpc('vincular_funcionario_usuario',{p_funcionario_id:employeeId,p_email:email.trim().toLowerCase()});
    if(error) throw error;
    return attachPhoto(Array.isArray(data)?data[0]:data);
  }

  async function updateSettings(values){
    const p=await profile();
    const companyPayload={
      razao_social:values.empresaNome?.trim()||'Livraria Plenitude',
      nome_fantasia:values.empresaNome?.trim()||'Livraria Plenitude',
      endereco:values.endereco?.trim()||null
    };
    const {error:companyError}=await client.from('empresas').update(companyPayload).eq('id',p.empresa_id);
    if(companyError) throw companyError;
    const {error:profileError}=await client.from('perfis').update({nome:values.adminNome?.trim()||p.nome}).eq('id',p.id);
    if(profileError) throw profileError;
    return profile();
  }

  async function occurrencesForRange(employeeId,start,end){
    let query=client.from('ocorrencias').select('*').gte('data_inicio',start).lte('data_inicio',end).order('data_inicio');
    if(employeeId) query=query.eq('funcionario_id',employeeId);
    const {data,error}=await query;
    if(error) throw error;
    return data||[];
  }

  async function saveOccurrence(employeeId,values){
    if(!employeeId) throw new Error('Cadastre ou selecione um funcionário.');
    const p=await profile();
    const payload={
      empresa_id:p.empresa_id,
      funcionario_id:employeeId,
      tipo:values.tipo,
      data_inicio:values.dataInicio,
      data_fim:values.dataFim||values.dataInicio,
      descricao:values.descricao||null,
      aprovado:true,
      criado_por:p.id
    };
    const {data:existing,error:findError}=await client.from('ocorrencias').select('id').eq('funcionario_id',employeeId).eq('data_inicio',payload.data_inicio).limit(1);
    if(findError) throw findError;
    let query=existing?.length?client.from('ocorrencias').update(payload).eq('id',existing[0].id):client.from('ocorrencias').insert(payload);
    const {data,error}=await query.select().single();
    if(error) throw error;
    return data;
  }

  async function backupData(){
    const p=await profile();
    const [employeesResult,schedulesResult,marksResult,occurrencesResult,logsResult]=await Promise.all([
      client.from('funcionarios').select('*').order('nome'),
      client.from('jornadas').select('*').order('funcionario_id,dia_semana'),
      client.from('marcacoes').select('*').order('registrado_em'),
      client.from('ocorrencias').select('*').order('data_inicio'),
      client.from('logs_auditoria').select('*').order('criado_em')
    ]);
    for(const result of [employeesResult,schedulesResult,marksResult,occurrencesResult,logsResult]) if(result.error) throw result.error;
    return {
      empresa:p.empresas||null,
      perfil:{id:p.id,nome:p.nome,papel:p.papel,email:p.email},
      funcionarios:employeesResult.data||[],
      jornadas:schedulesResult.data||[],
      marcacoes:marksResult.data||[],
      ocorrencias:occurrencesResult.data||[],
      auditoria:logsResult.data||[],
      exportado_em:new Date().toISOString()
    };
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

  async function registerPoint(employeeId=null){
    const p=await profile();
    const functionName=p.papel==='administrador'?'registrar_ponto_funcionario':'registrar_ponto';
    const args=functionName==='registrar_ponto_funcionario'?{p_funcionario_id:employeeId}:{};
    if(functionName==='registrar_ponto_funcionario'&&!employeeId) throw new Error('Selecione um funcionário para registrar o ponto.');
    const {data,error}=await client.rpc(functionName,args);
    if(error) throw error;
    return Array.isArray(data)?data[0]:data;
  }

  function subscribeMarks(callback){
    return client.channel('plenitude-marcacoes')
      .on('postgres_changes',{event:'*',schema:'public',table:'marcacoes'},payload=>callback(payload))
      .subscribe();
  }


  async function defineEmployeePin(employeeId,pin,requireChange=false,active=true){
    const {data,error}=await client.rpc('admin_definir_pin',{p_funcionario_id:employeeId,p_pin:pin,p_exigir_troca:requireChange,p_acesso_ativo:active});
    if(error) throw error;
    return Array.isArray(data)?data[0]:data;
  }

  async function setEmployeePinAccess(employeeId,active){
    const {error}=await client.rpc('admin_alterar_acesso_pin',{p_funcionario_id:employeeId,p_ativo:active});
    if(error) throw error;
  }

  window.PlenitudeDB=Object.freeze({profile,ownEmployee,employees,saveEmployee,uploadEmployeePhoto,removeEmployeePhoto,employeePhotoUrl,linkEmployeeAccess,defineEmployeePin,setEmployeePinAccess,updateSettings,occurrencesForRange,saveOccurrence,backupData,schedules,saveSchedules,marksForRange,registerPoint,subscribeMarks});
})();
