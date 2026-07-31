(function(){
  'use strict';
  const client=window.PlenitudeAuth?.client;
  if(!client) throw new Error('Cliente Supabase não inicializado.');

  async function profile(){
    const {data:{user},error:userError}=await client.auth.getUser();
    if(userError) throw userError;
    if(!user) throw new Error('Sessão não encontrada.');
    const {data,error}=await client.from('perfis').select('id,nome,papel,empresa_id,empresas(nome_fantasia,razao_social,endereco,cidade,uf,tolerancia_entrada_minutos,tolerancia_saida_minutos,intervalo_minimo_minutos,intervalo_maximo_minutos,horas_extras_automaticas,limite_banco_horas_minutos)').eq('id',user.id).single();
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

  async function savePointPolicies(values){
    const {data,error}=await client.rpc('salvar_politicas_ponto',{p_tolerancia_entrada:values.entrada,p_tolerancia_saida:values.saida,p_intervalo_minimo:values.intervaloMinimo,p_intervalo_maximo:values.intervaloMaximo,p_horas_extras_automaticas:values.extrasAutomaticas,p_limite_banco_horas:values.limiteBanco});
    if(error) throw error; return data;
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


  async function bankHours(employeeId,start,end){
    if(!employeeId) throw new Error('Selecione um funcionário.');
    const {data,error}=await client.rpc('banco_horas_admin',{p_funcionario_id:employeeId,p_inicio:start,p_fim:end});
    if(error) throw error;
    return data||{resumo:{},dias:[]};
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



  async function adminAdjustmentRequests(status=null){
    const {data,error}=await client.rpc('listar_ajustes_admin',{p_status:status||null});
    if(error) throw error; return data||[];
  }
  async function decideAdjustment(id,decision,response=''){
    const {data,error}=await client.rpc('analisar_ajuste_ponto',{p_solicitacao_id:id,p_decisao:decision,p_resposta:response||null});
    if(error) throw error; return Array.isArray(data)?data[0]:data;
  }


  async function auditLogs(filters={}){
    const {data,error}=await client.rpc('listar_auditoria_admin',{
      p_inicio:filters.start?`${filters.start}T00:00:00-03:00`:null,
      p_fim:filters.end?`${filters.end}T23:59:59-03:00`:null,
      p_acao:filters.action||null,p_tabela:filters.table||null,p_busca:filters.query||null,
      p_limite:filters.limit||100,p_offset:filters.offset||0
    });
    if(error) throw error; return data||[];
  }
  async function securitySummary(){
    const {data,error}=await client.rpc('resumo_seguranca_admin');
    if(error) throw error; return data||{};
  }
  async function recordAuditEvent(action,description='',details=null){
    const {error}=await client.rpc('registrar_evento_auditoria',{p_acao:action,p_tabela:'sistema',p_registro_id:null,p_descricao:description,p_dados_novos:details,p_origem:'web'});
    if(error) console.warn('Auditoria:',error.message);
  }



  async function monthClosures(startYear=null,endYear=null){
    const {data,error}=await client.rpc('listar_fechamentos_admin',{p_ano_inicio:startYear,p_ano_fim:endYear});
    if(error) throw error; return data||[];
  }
  async function closeMonth(year,month,note='',masterPin=''){
    const {data,error}=await client.rpc('fechar_competencia_master_admin',{p_ano:year,p_mes:month,p_observacao:note||null,p_master_pin:masterPin});
    if(error) throw error; return Array.isArray(data)?data[0]:data;
  }
  async function reopenMonth(year,month,reason,masterPin=''){
    const {data,error}=await client.rpc('reabrir_competencia_master_admin',{p_ano:year,p_mes:month,p_motivo:reason,p_master_pin:masterPin});
    if(error) throw error; return Array.isArray(data)?data[0]:data;
  }



  async function employeeMovements(token,start,end){
    const {data,error}=await client.rpc('listar_minhas_movimentacoes',{p_token:token,p_inicio:start,p_fim:end});
    if(error) throw error; return data||[];
  }
  async function registerEmployeeMovement(token,deviceToken,action,reason=''){
    const {data,error}=await client.rpc('registrar_movimentacao_dispositivo',{p_token:token,p_dispositivo_token:deviceToken,p_acao:action,p_motivo:reason||null,p_user_agent:navigator.userAgent});
    if(error) throw error; return Array.isArray(data)?data[0]:data;
  }
  async function adminMovements(start,end,employeeId=null,pendingOnly=false){
    const {data,error}=await client.rpc('listar_movimentacoes_admin',{p_inicio:start,p_fim:end,p_funcionario_id:employeeId||null,p_pendentes:pendingOnly});
    if(error) throw error; return data||[];
  }
  async function historicalReturnPendencies(){
    const {data,error}=await client.rpc('listar_pendencias_retorno_admin');
    if(error) throw error; return data||[];
  }
  async function createAdminMovement(employeeId,start,end,classification,effect,note=''){
    const {data,error}=await client.rpc('criar_movimentacao_admin',{p_funcionario_id:employeeId,p_inicio:start,p_fim:end,p_classificacao:classification,p_efeito:effect,p_observacao:note||null});
    if(error) throw error; return Array.isArray(data)?data[0]:data;
  }
  async function analyzeMovement(id,classification,effect,note=''){
    const {data,error}=await client.rpc('analisar_movimentacao_admin',{p_id:id,p_classificacao:classification,p_efeito:effect,p_observacao:note||null});
    if(error) throw error; return Array.isArray(data)?data[0]:data;
  }
  async function regularizeMovementReturn(id,endAt,note=''){
    const {data,error}=await client.rpc('regularizar_retorno_movimentacao_admin',{
      p_id:id,
      p_fim_em:endAt,
      p_observacao:note||null
    });
    if(error) throw error;
    return Array.isArray(data)?data[0]:data;
  }
  async function archiveMovement(id,reason){
    const {data,error}=await client.rpc('arquivar_movimentacao_admin',{
      p_id:id,
      p_motivo:reason
    });
    if(error) throw error;
    return Array.isArray(data)?data[0]:data;
  }

  async function masterPinStatus(){
    const {data,error}=await client.rpc('status_pin_mestre_admin');
    if(error) throw error; return Array.isArray(data)?data[0]:data;
  }
  async function setMasterPin(newPin,currentPin=''){
    const {error}=await client.rpc('definir_pin_mestre_admin',{p_novo_pin:newPin,p_pin_atual:currentPin||null});
    if(error) throw error;
  }

  async function defineEmployeePin(employeeId,pin,requireChange=false,active=true){
    const {data,error}=await client.rpc('admin_definir_pin',{
      p_funcionario_id:employeeId,
      p_pin:pin,
      p_exigir_troca:requireChange,
      p_acesso_ativo:active
    });
    if(error) throw error;
    const saved=Array.isArray(data)?data[0]:data;
    if(!saved?.pin_configurado) throw new Error('O Supabase não confirmou a gravação do PIN.');
    return saved;
  }

  async function setEmployeePinAccess(employeeId,active){
    const {error}=await client.rpc('admin_alterar_acesso_pin',{p_funcionario_id:employeeId,p_ativo:active});
    if(error) throw error;
  }

  window.PlenitudeDB=Object.freeze({employeeMovements,registerEmployeeMovement,adminMovements,historicalReturnPendencies,createAdminMovement,analyzeMovement,regularizeMovementReturn,archiveMovement,masterPinStatus,setMasterPin,monthClosures,closeMonth,reopenMonth,auditLogs,securitySummary,recordAuditEvent,profile,ownEmployee,employees,saveEmployee,uploadEmployeePhoto,removeEmployeePhoto,employeePhotoUrl,linkEmployeeAccess,defineEmployeePin,setEmployeePinAccess,updateSettings,savePointPolicies,occurrencesForRange,saveOccurrence,backupData,schedules,saveSchedules,marksForRange,bankHours,adminAdjustmentRequests,decideAdjustment,registerPoint,subscribeMarks});
})();
