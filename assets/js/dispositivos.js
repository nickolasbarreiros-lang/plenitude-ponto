(function(){
 'use strict';

 const client=window.PlenitudeAuth.client;
 const KEY='plenitude-device-token';

 const token=()=>localStorage.getItem(KEY)||'';

 function randomToken(){
  const bytes=new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes,value=>value.toString(16).padStart(2,'0')).join('');
 }

 function fmt(value){
  return value?new Date(value).toLocaleString('pt-BR'):'—';
 }

 function typeLabel(type){
  return {
   terminal:'Terminal da loja',
   homologacao:'Homologação',
   contingencia:'Contingência'
  }[type]||'Dispositivo';
 }

 async function rpc(name,args={}){
  const {data,error}=await client.rpc(name,args);
  if(error)throw error;
  return data;
 }


 const OFFLINE_CORE=[
  './',
  './index.html',
  './ponto.html',
  './assets/css/estilos.css',
  './assets/js/supabase-config.js',
  './assets/js/auth.js',
  './assets/js/database.js',
  './assets/js/app.js',
  './assets/js/offline-contingencia.js',
  './assets/js/ponto-pin.js',
  './assets/js/employee-login.js',
  './assets/js/access-status.js',
  './assets/img/logo-plenitude.png',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'
 ];

 function offlineCheckRow(label,status,detail=''){
  const state=status===true?'approved':status===false?'failed':'pending';
  const icon=status===true?'✓':status===false?'✕':'…';

  return `<div class="offline-check ${state}">
   <span class="offline-check-icon">${icon}</span>
   <div><strong>${label}</strong>${detail?`<small>${detail}</small>`:''}</div>
  </div>`;
 }

 async function ensureServiceWorker(){
  if(!('serviceWorker' in navigator)){
   throw new Error('Este navegador não oferece suporte a Service Worker.');
  }

  const registration=await navigator.serviceWorker.register('./sw.js?v=1.0.0-rc5.1');
  await navigator.serviceWorker.ready;

  if(registration.waiting){
   registration.waiting.postMessage({type:'SKIP_WAITING'});
  }

  return registration;
 }

 function serviceWorkerMessage(type,timeout=30000){
  return new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>{
    navigator.serviceWorker.removeEventListener('message',handler);
    reject(new Error('O Service Worker não respondeu dentro do tempo esperado.'));
   },timeout);

   function handler(event){
    const expected=type==='CACHE_OFFLINE_CORE'
     ?'CACHE_OFFLINE_RESULT'
     :'OFFLINE_STATUS_RESULT';

    if(event.data?.type!==expected)return;

    clearTimeout(timer);
    navigator.serviceWorker.removeEventListener('message',handler);
    resolve(event.data);
   }

   navigator.serviceWorker.addEventListener('message',handler);

   const worker=navigator.serviceWorker.controller;
   if(!worker){
    clearTimeout(timer);
    navigator.serviceWorker.removeEventListener('message',handler);
    reject(new Error('Recarregue a página para ativar o modo offline e execute novamente.'));
    return;
   }

   worker.postMessage({type});
  });
 }

 async function checkIndexedDB(){
  if(!('indexedDB' in window))return false;

  return new Promise(resolve=>{
   const request=indexedDB.open('plenitude-contingencia',1);

   request.onupgradeneeded=()=>{
    const db=request.result;
    if(!db.objectStoreNames.contains('registros')){
     const store=db.createObjectStore('registros',{keyPath:'evento_offline_id'});
     store.createIndex('status','status');
     store.createIndex('data_local','data_local');
    }
    if(!db.objectStoreNames.contains('meta')){
     db.createObjectStore('meta',{keyPath:'key'});
    }
   };

   request.onsuccess=()=>{
    request.result.close();
    resolve(true);
   };

   request.onerror=()=>resolve(false);
  });
 }

 async function getOfflineDiagnostic(){
  const deviceResult=await currentStatus();
  const serviceWorkerSupported='serviceWorker' in navigator;
  const registration=serviceWorkerSupported
   ?await navigator.serviceWorker.getRegistration('./')
   :null;

  let cacheResults=[];
  let cacheError='';

  if(registration&&navigator.serviceWorker.controller){
   try{
    const status=await serviceWorkerMessage('OFFLINE_STATUS',12000);
    cacheResults=status.results||[];
   }catch(error){
    cacheError=error.message;
   }
  }

  const indexedDBReady=await checkIndexedDB();
  const deviceToken=Boolean(token());
  const employeeProfiles=JSON.parse(
   localStorage.getItem('plenitude-offline-employee-profiles')||'{}'
  );
  const offlineLogins=JSON.parse(
   localStorage.getItem('plenitude-offline-login-v1')||'{}'
  );
  const employeeProfile=Object.keys(employeeProfiles).length>0||
   Boolean(localStorage.getItem('plenitude-offline-employee-profile'));
  const employeeSession=Object.keys(offlineLogins).length>0||
   Boolean(localStorage.getItem('plenitude-offline-employee-session'));
  const preparedEmployees=Object.keys(offlineLogins).length;
  const allCached=cacheResults.length>=OFFLINE_CORE.length&&cacheResults.every(item=>item.ok);
  const secureContext=window.isSecureContext;
  const storageEstimate=navigator.storage?.estimate
   ?await navigator.storage.estimate()
   :null;

  return {
   authorized:Boolean(deviceResult?.autorizado),
   deviceToken,
   serviceWorkerSupported,
   serviceWorkerInstalled:Boolean(registration),
   serviceWorkerActive:Boolean(navigator.serviceWorker.controller),
   allCached,
   cacheCount:cacheResults.filter(item=>item.ok).length,
   cacheTotal:OFFLINE_CORE.length,
   cacheError,
   indexedDBReady,
   employeeProfile,
   employeeSession,
   preparedEmployees,
   secureContext,
   storageEstimate
  };
 }

 function renderOfflineDiagnostic(result){
  const box=document.getElementById('offline-preparation-status');
  const badge=document.getElementById('offline-ready-badge');

  const rows=[
   offlineCheckRow(
    'Navegador seguro',
    result.secureContext,
    result.secureContext?'HTTPS ativo.':'Service Worker exige HTTPS ou localhost.'
   ),
   offlineCheckRow(
    'Computador autorizado',
    result.authorized&&result.deviceToken,
    result.authorized?'Token deste navegador reconhecido.':'Autorize este computador primeiro.'
   ),
   offlineCheckRow(
    'Service Worker instalado',
    result.serviceWorkerInstalled&&result.serviceWorkerActive,
    result.serviceWorkerActive
     ?'Controle offline ativo.'
     :result.serviceWorkerInstalled
      ?'Instalado, mas precisa recarregar a página.'
      :'Ainda não instalado.'
   ),
   offlineCheckRow(
    'Arquivos essenciais armazenados',
    result.allCached,
    `${result.cacheCount} de ${result.cacheTotal} recursos disponíveis localmente.${result.cacheError?` ${result.cacheError}`:''}`
   ),
   offlineCheckRow(
    'Banco local disponível',
    result.indexedDBReady,
    result.indexedDBReady?'IndexedDB pronto para receber registros.':'IndexedDB indisponível.'
   ),
   offlineCheckRow(
    'Funcionário preparado',
    result.employeeProfile&&result.employeeSession,
    result.employeeProfile&&result.employeeSession
     ?`${result.preparedEmployees||1} funcionário(s) preparado(s) para login offline.`
     :'Abra o ponto e faça login com matrícula e PIN ao menos uma vez com internet.'
   )
  ];

  if(result.storageEstimate){
   const used=Math.round((result.storageEstimate.usage||0)/1024/1024);
   const quota=Math.round((result.storageEstimate.quota||0)/1024/1024);
   rows.push(
    offlineCheckRow(
     'Armazenamento do navegador',
     quota>0,
     `${used} MB utilizados de aproximadamente ${quota} MB disponíveis.`
    )
   );
  }

  box.innerHTML=rows.join('');

  const ready=
   result.secureContext&&
   result.authorized&&
   result.deviceToken&&
   result.serviceWorkerActive&&
   result.allCached&&
   result.indexedDBReady&&
   result.employeeProfile&&
   result.employeeSession;

  badge.textContent=ready?'Pronto para contingência':'Preparação incompleta';
  badge.className=`badge ${ready?'success':'warn'}`;

  localStorage.setItem(
   'plenitude-offline-preparation-status',
   JSON.stringify({
    ready,
    checkedAt:new Date().toISOString(),
    cacheCount:result.cacheCount,
    cacheTotal:result.cacheTotal
   })
  );

  return ready;
 }

 async function runOfflineDiagnostic(){
  const button=document.getElementById('verify-offline-device');
  button.disabled=true;

  try{
   const result=await getOfflineDiagnostic();
   const ready=renderOfflineDiagnostic(result);

   toast(
    ready
     ?'Este computador está preparado para contingência.'
     :'A preparação ainda possui itens pendentes.',
    ready?'success':'warn'
   );
  }catch(error){
   toast(error.message,'warn');
  }finally{
   button.disabled=false;
  }
 }

 async function prepareOfflineDevice(){
  const button=document.getElementById('prepare-offline-device');
  const box=document.getElementById('offline-preparation-status');

  button.disabled=true;
  box.innerHTML=offlineCheckRow(
   'Preparando computador',
   null,
   'Instalando o modo offline e armazenando os arquivos essenciais...'
  );

  try{
   const device=await currentStatus();

   if(!device?.autorizado){
    throw new Error('Autorize este computador antes de preparar a contingência.');
   }

   await ensureServiceWorker();

   if(!navigator.serviceWorker.controller){
    box.innerHTML=offlineCheckRow(
     'Service Worker instalado',
     null,
     'Instalação concluída. Recarregue a página e clique novamente em Preparar computador.'
    );

    toast('Modo offline instalado. Recarregue a página para concluir.','warn');
    return;
   }

   const cacheResult=await serviceWorkerMessage('CACHE_OFFLINE_CORE',45000);
   const failed=(cacheResult.results||[]).filter(item=>!item.ok);

   if(failed.length){
    throw new Error(
     `${failed.length} arquivo(s) não puderam ser armazenados. Verifique a conexão e tente novamente.`
    );
   }

   await checkIndexedDB();
   localStorage.setItem('plenitude-offline-prepared-at',new Date().toISOString());

   const result=await getOfflineDiagnostic();
   const ready=renderOfflineDiagnostic(result);

   if(ready){
    toast('Computador preparado para contingência.');
   }else if(!result.employeeProfile||!result.employeeSession){
    toast('Arquivos instalados. Abra o ponto e faça login uma vez para concluir.','warn');
   }else{
    toast('Preparação concluída com pendências. Consulte o diagnóstico.','warn');
   }
  }catch(error){
   box.innerHTML=offlineCheckRow('Falha na preparação',false,error.message);
   toast(error.message,'warn');
  }finally{
   button.disabled=false;
  }
 }

 async function currentStatus(){
  const box=document.getElementById('current-device-status');
  const badge=document.getElementById('device-badge');

  try{
   const data=await rpc('validar_dispositivo_ponto_detalhado',{p_token:token()});
   const result=Array.isArray(data)?data[0]:data;

   if(result?.autorizado){
    box.dataset.deviceId=result.id||'';
    box.className='device-status-box authorized';
    box.innerHTML=`
     <strong>✓ Este navegador está autorizado</strong>
     <span>${result.nome||'Computador autorizado'} · ${typeLabel(result.tipo)}</span>`;
    badge.textContent='Autorizado';
    badge.classList.add('success');
   }else{
    box.dataset.deviceId='';
    box.className='device-status-box blocked';
    box.innerHTML=`
     <strong>Este navegador não está autorizado</strong>
     <span>Você pode autorizá-lo sem revogar os demais equipamentos.</span>`;
    badge.textContent='Não autorizado';
    badge.classList.remove('success');
   }

   return result||null;
  }catch(error){
   box.dataset.deviceId='';
   box.textContent=error.message;
   badge.textContent='Erro';
   badge.classList.remove('success');
   return null;
  }
 }

 async function list(){
  const data=await rpc('listar_dispositivos_ponto_multi_admin');
  const box=document.getElementById('device-list');
  const rows=data||[];
  const currentId=document.getElementById('current-device-status').dataset.deviceId||'';

  const activeCount=rows.filter(row=>row.ativo).length;

  box.innerHTML=rows.length
   ?`<div class="device-list-summary">
      <strong>${activeCount} dispositivo${activeCount===1?'':'s'} ativo${activeCount===1?'':'s'}</strong>
      <span>Limite operacional: 10 ativos</span>
     </div>`+
     rows.map(device=>{
      const isCurrent=device.id===currentId;
      return `<div class="device-row ${device.ativo?'active':''} ${isCurrent?'current':''}">
       <div>
        <div class="device-title-line">
         <strong>${device.nome}</strong>
         <span class="device-type">${typeLabel(device.tipo)}</span>
         ${isCurrent?'<span class="device-current">Este navegador</span>':''}
        </div>
        <small>${device.ativo?'Ativo':'Revogado'} · autorizado em ${fmt(device.autorizado_em)}</small>
        <small>Último uso: ${fmt(device.ultimo_uso_em)}</small>
        ${device.observacao?`<small>Observação: ${device.observacao}</small>`:''}
       </div>
       ${device.ativo
        ?`<button class="btn outline danger revoke-device" data-id="${device.id}" data-current="${isCurrent}" type="button">Revogar</button>`
        :''}
      </div>`;
     }).join('')
   :'<div class="mini-empty">Nenhum computador autorizado.</div>';

  box.querySelectorAll('.revoke-device').forEach(button=>{
   button.onclick=async()=>{
    const isCurrent=button.dataset.current==='true';
    const warning=isCurrent
     ?'Revogar este navegador? Ele deixará de registrar ponto imediatamente.'
     :'Revogar este computador? Os demais continuarão funcionando normalmente.';

    if(!confirm(warning))return;

    const reason=prompt('Motivo da revogação (opcional):')||'';
    const masterPin=prompt('Digite o PIN Mestre de 6 números para confirmar:')||'';

    if(!/^\d{6}$/.test(masterPin)){
     toast('PIN Mestre inválido.','warn');
     return;
    }

    button.disabled=true;

    try{
     await rpc('revogar_dispositivo_ponto_master_admin',{
      p_id:button.dataset.id,
      p_motivo:reason,
      p_master_pin:masterPin
     });

     if(isCurrent){
      localStorage.removeItem(KEY);
     }

     toast(
      isCurrent
       ?'Este navegador foi revogado.'
       :'Dispositivo revogado. Os demais permanecem ativos.'
     );

     await currentStatus();
     await list();
    }catch(error){
     toast(error.message,'warn');
    }finally{
     button.disabled=false;
    }
   };
  });
 }

 document.getElementById('authorize-device-form').onsubmit=async event=>{
  event.preventDefault();

  const button=event.submitter;
  button.disabled=true;

  try{
   const current=await currentStatus();

   if(current?.autorizado){
    throw new Error('Este navegador já está autorizado. Revogue-o antes de gerar uma nova autorização.');
   }

   const masterPin=prompt('Digite o PIN Mestre de 6 números para autorizar este computador:')||'';

   if(!/^\d{6}$/.test(masterPin)){
    throw new Error('PIN Mestre inválido.');
   }

   const newToken=randomToken();

   await rpc('autorizar_dispositivo_ponto_multi_master_admin',{
    p_token:newToken,
    p_nome:document.getElementById('device-name').value,
    p_tipo:document.getElementById('device-type').value,
    p_user_agent:navigator.userAgent,
    p_master_pin:masterPin
   });

   localStorage.setItem(KEY,newToken);

   toast('Computador autorizado sem revogar os demais.');

   await currentStatus();
   await list();
  }catch(error){
   toast(error.message,'warn');
  }finally{
   button.disabled=false;
  }
 };

 document.getElementById('prepare-offline-device').onclick=prepareOfflineDevice;
 document.getElementById('verify-offline-device').onclick=runOfflineDiagnostic;

 (async()=>{
  try{
   await window.PlenitudeAuth.requireAccess({roles:['administrador']});
   await currentStatus();
   await list();
   await runOfflineDiagnostic();
  }catch(error){
   toast(error.message,'warn');
  }
 })();
})();