(function(){'use strict';
 const client=window.PlenitudeAuth.client;
 function stored(){try{return JSON.parse(sessionStorage.getItem('plenitude-employee-session')||localStorage.getItem('plenitude-offline-employee-session')||'null')}catch{return null}}
 const sess=stored();
 if(!sess){ window.PlenitudeAuth.getSession().then(s=>s?initPonto():location.replace('index.html')); return; }
 const token=sess.token;let employee=null;let onlineMarks=[];let currentJourneyMarks=[];let offlineDayStateReady=false;let contingencyMode=false;let syncInProgress=false;let pointReady=false;let serverReachable=null;let punchInFlight=false;let punchCooldownUntil=0;let punchCooldownTimer=null;let lunchMinimumTimer=null;
 const dateKey=d=>{const y=d.getFullYear(),m=String(d.getMonth()+1).padStart(2,'0'),day=String(d.getDate()).padStart(2,'0');return `${y}-${m}-${day}`};
 const label=t=>({entrada:'Entrada',inicio_intervalo:'Início do almoço',fim_intervalo:'Retorno do almoço',saida:'Saída'})[t]||'Marcação';
 const fmt=v=>new Date(v).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
 function toast(message,type='success'){
  const text=String(message||'').trim();
  if(!text)return;

  let region=document.getElementById('point-toast-region');
  if(!region){
   region=document.createElement('div');
   region.id='point-toast-region';
   region.className='point-toast-region';
   region.setAttribute('aria-live','polite');
   document.body.appendChild(region);
  }

  const item=document.createElement('div');
  item.className=`point-toast ${type==='warn'?'warn':'success'}`;
  item.textContent=text;
  region.appendChild(item);

  requestAnimationFrame(()=>item.classList.add('visible'));
  setTimeout(()=>{
   item.classList.remove('visible');
   setTimeout(()=>item.remove(),220);
  },4200);
 }

 function employeeInitials(name){
  return String(name||'P')
   .trim()
   .split(/\s+/)
   .slice(0,2)
   .map(part=>part[0]||'')
   .join('')
   .toUpperCase();
 }

 function employeePhotoUrl(path){
  if(!path)return null;
  if(/^https?:\/\//i.test(path)||path.startsWith('data:'))return path;

  const {data}=client.storage.from('funcionarios').getPublicUrl(path);
  return data?.publicUrl||null;
 }

 function renderEmployeeAvatar(employee){
  const avatar=document.getElementById('clock-avatar');
  const initials=employeeInitials(employee?.nome);
  const photo=employeePhotoUrl(employee?.foto_url);

  avatar.innerHTML='';

  if(!photo){
   avatar.innerHTML=`<span>${initials}</span>`;
   return;
  }

  const image=document.createElement('img');
  image.alt=`Foto de ${employee.nome}`;
  image.loading='eager';
  image.referrerPolicy='no-referrer';

  image.onload=()=>{
   avatar.classList.add('has-photo');
  };

  image.onerror=()=>{
   avatar.classList.remove('has-photo');
   avatar.innerHTML=`<span>${initials}</span>`;
   console.warn('Não foi possível carregar a foto do funcionário.');
  };

  image.src=photo;
  avatar.appendChild(image);
 }

 function cacheEmployeeProfile(){
  if(!employee)return;

  localStorage.setItem(
   'plenitude-offline-employee-session',
   JSON.stringify(sess)
  );

  localStorage.setItem(
   'plenitude-offline-employee-profile',
   JSON.stringify(employee)
  );

  let profiles={};

  try{
   profiles=JSON.parse(
    localStorage.getItem('plenitude-offline-employee-profiles')||'{}'
   );
  }catch{
   profiles={};
  }

  profiles[String(employee.matricula||'')]=employee;

  localStorage.setItem(
   'plenitude-offline-employee-profiles',
   JSON.stringify(profiles)
  );
 }

 function restoreEmployeeProfile(){
  let profiles={};

  try{
   profiles=JSON.parse(
    localStorage.getItem('plenitude-offline-employee-profiles')||'{}'
   );
  }catch{
   profiles={};
  }

  const registration=String(
   sess.matricula||
   sess.funcionario_matricula||
   ''
  );

  if(registration&&profiles[registration]){
   return profiles[registration];
  }

  try{
   return JSON.parse(
    localStorage.getItem('plenitude-offline-employee-profile')||'null'
   );
  }catch{
   return null;
  }
 }

 async function rpc(name,args={}){
  if(serverReachable===false){
   const error=new Error('Servidor indisponível.');
   error.code='OFFLINE_FAST_FAIL';
   throw error;
  }

  const timeoutMs=8000;
  let timer;

  try{
   const result=await Promise.race([
    client.rpc(name,args),
    new Promise((_,reject)=>{
     timer=setTimeout(()=>{
      const error=new Error('Tempo de comunicação com o servidor excedido.');
      error.code='SERVER_TIMEOUT';
      reject(error);
     },timeoutMs);
    })
   ]);

   const {data,error}=result;

   if(error){
    if(isExpiredEmployeeSession(error)){
     const sessionError=new Error('Sessão expirada. Entre novamente.');
     sessionError.code='EMPLOYEE_SESSION_EXPIRED';
     sessionError.original=error;
     throw sessionError;
    }

    const normalized=new Error(normalizedErrorMessage(error));
    normalized.code=error.code||'RPC_ERROR';
    normalized.original=error;
    throw normalized;
   }

   return data;
  }finally{
   clearTimeout(timer);
  }
 }


 function normalizedErrorMessage(error){
  if(!error)return 'Erro desconhecido.';

  if(typeof error==='string')return error;

  return String(
   error.message||
   error.details||
   error.hint||
   error.error_description||
   error.code||
   'Erro desconhecido.'
  );
 }

 function isExpiredEmployeeSession(error){
  const message=[
   error?.message,
   error?.details,
   error?.hint,
   error?.code,
   error?.status,
   error
  ].filter(Boolean).join(' ').toLowerCase();

  return (
   /sess[aã]o expirada|token expirad|sess[aã]o inv[aá]lida|token inv[aá]lido|entre novamente/.test(message)||
   error?.code==='INVALID_EMPLOYEE_SESSION'
  );
 }

 async function redirectToOnlineLogin(){
  const pendingCount=window.PlenitudeOffline
   ?(await window.PlenitudeOffline.counts()).local
   :0;

  localStorage.setItem(
   'plenitude-online-reauth-required',
   JSON.stringify({
    registration:String(
     employee?.matricula||
     sess?.matricula||
     sess?.funcionario_matricula||
     ''
    ),
    pendingCount,
    createdAt:new Date().toISOString()
   })
  );

  sessionStorage.removeItem('plenitude-employee-session');

  blockPoint(
   pendingCount>0
    ?`Sessão expirada. Entre novamente para sincronizar ${pendingCount} registro(s) offline.`
    :'Sessão expirada. Entre novamente.'
  );

  setTimeout(()=>{
   location.replace('index.html');
  },1200);
 }

 async function fetchEmployeeOnline(timeoutMs=5000){
  if(!navigator.onLine){
   const error=new Error('Sem conexão com a internet.');
   error.code='OFFLINE_FAST_FAIL';
   throw error;
  }

  let timer;

  try{
   const result=await Promise.race([
    client.rpc('dados_funcionario_token',{p_token:token}),
    new Promise((_,reject)=>{
     timer=setTimeout(()=>{
      const error=new Error('Tempo de comunicação com o servidor excedido.');
      error.code='SERVER_TIMEOUT';
      reject(error);
     },timeoutMs);
    })
   ]);

   const {data,error}=result;

   if(error){
    if(isExpiredEmployeeSession(error)){
     const sessionError=new Error('Sessão expirada. Entre novamente.');
     sessionError.code='EMPLOYEE_SESSION_EXPIRED';
     sessionError.original=error;
     throw sessionError;
    }

    const normalized=new Error(normalizedErrorMessage(error));
    normalized.code=error.code||'RPC_ERROR';
    normalized.original=error;
    throw normalized;
   }

   const row=Array.isArray(data)?data[0]:data;

   if(!row){
    const error=new Error('Sessão do funcionário não encontrada.');
    error.code='INVALID_EMPLOYEE_SESSION';
    throw error;
   }

   serverReachable=true;
   return row;
  }finally{
   clearTimeout(timer);
  }
 }

 function setPointLoading(message,percent=0){
  const overlay=document.getElementById('point-loading-overlay');
  const text=document.getElementById('point-loading-message');
  const page=document.getElementById('point-page');
  const button=document.getElementById('registrar');
  const card=overlay?.querySelector('.point-loading-card');
  const fill=document.getElementById('point-loading-progress-fill');
  const label=document.getElementById('point-loading-progress-label');
  const safePercent=Math.max(0,Math.min(100,Number(percent)||0));

  card?.classList.remove('error');
  if(text&&message)text.textContent=message;
  if(fill)fill.style.width=`${safePercent}%`;
  if(label)label.textContent=`${safePercent}%`;
  overlay?.removeAttribute('hidden');
  page?.classList.add('point-booting');
  pointReady=false;

  if(button){
   button.hidden=true;
   button.disabled=true;
  }
 }

 function revealPoint(){
  const overlay=document.getElementById('point-loading-overlay');
  const page=document.getElementById('point-page');
  const button=document.getElementById('registrar');

  pointReady=true;
  overlay?.setAttribute('hidden','');
  page?.classList.remove('point-booting');

  if(button)button.hidden=false;

  refreshPunchAvailability();
  unlockOnlinePunchButton();

  requestAnimationFrame(()=>{
   refreshPunchAvailability();
   unlockOnlinePunchButton();
  });

  setTimeout(()=>{
   refreshPunchAvailability();
   unlockOnlinePunchButton();
  },100);
 }

 function blockPoint(message){
  const overlay=document.getElementById('point-loading-overlay');
  const text=document.getElementById('point-loading-message');
  const card=overlay?.querySelector('.point-loading-card');
  const button=document.getElementById('registrar');

  pointReady=false;
  card?.classList.add('error');
  if(text)text.textContent=message||'Não foi possível carregar a jornada.';
  overlay?.removeAttribute('hidden');

  if(button){
   button.hidden=true;
   button.disabled=true;
  }
 }

 function isNetworkFailure(error){
  const message=String(error?.message||error||'');
  return !navigator.onLine||/Failed to fetch|NetworkError|Load failed|fetch|timeout|connection|ERR_INTERNET/i.test(message);
 }

 function nextType(count){
  return ['entrada','inicio_intervalo','fim_intervalo','saida'][count]||null;
 }

 async function localTodayMarks(){
  if(!employee||!window.PlenitudeOffline)return [];

  const today=dateKey(new Date());

  return (await window.PlenitudeOffline.pending())
   .filter(record=>
    record.funcionario_id===employee.id&&
    record.data_local===today
   )
   .sort((a,b)=>
    new Date(a.ocorrido_em_dispositivo)-
    new Date(b.ocorrido_em_dispositivo)
   )
   .map(record=>({
    id:record.evento_offline_id,
    tipo:record.tipo,
    registrado_em:record.ocorrido_em_dispositivo,
    offline:true,
    status_offline:record.status
   }));
 }

 function dayStateKey(day=dateKey(new Date())){
  return `day-state:${employee?.id||'unknown'}:${day}`;
 }

 async function saveOfficialDayState(day,marks){
  if(!window.PlenitudeOffline||!employee)return;

  await window.PlenitudeOffline.setMeta(
   dayStateKey(day),
   {
    employeeId:employee.id,
    day,
    cachedAt:new Date().toISOString(),
    marks:(marks||[]).map(mark=>({
     id:mark.id,
     tipo:mark.tipo,
     registrado_em:mark.registrado_em,
     offline:false
    }))
   }
  );
 }

 async function loadOfficialDayState(day){
  if(!window.PlenitudeOffline||!employee)return null;

  const snapshot=await window.PlenitudeOffline.getMeta(dayStateKey(day));

  if(
   !snapshot||
   snapshot.employeeId!==employee.id||
   snapshot.day!==day||
   !Array.isArray(snapshot.marks)
  ){
   return null;
  }

  return snapshot;
 }

 function setOfflineDayStateWarning(show,message=''){
  const existing=document.getElementById('offline-day-state-warning');
  const card=document.querySelector('.clock-action-card');

  if(!show){
   existing?.remove();
   return;
  }

  const warning=existing||document.createElement('div');
  warning.id='offline-day-state-warning';
  warning.className='offline-day-state-warning';
  warning.innerHTML=`<strong>Não foi possível confirmar as marcações de hoje</strong><span>${message}</span>`;

  if(!existing){
   const status=document.getElementById('offline-point-status');
   status?.insertAdjacentElement('afterend',warning);
  }
 }




 function unlockOnlinePunchButton(){
  const button=document.getElementById('registrar');
  if(!button)return;

  const marks=currentJourneyMarks||[];
  const hasNextMark=marks.length<4;

  if(
   serverReachable===true&&
   pointReady&&
   hasNextMark&&
   !punchInFlight&&
   !syncInProgress
  ){
   button.disabled=false;
   button.removeAttribute('disabled');
   button.classList.remove(
    'sync-lock',
    'loading',
    'cooldown',
    'lunch-wait'
   );
  }
 }

 function refreshPunchAvailability(){
  const button=document.getElementById('registrar');
  if(!button)return;

  const marks=currentJourneyMarks||[];
  const journeyComplete=marks.length>=4;
  const cooldownActive=Date.now()<punchCooldownUntil;
  const offlineAllowed=
   contingencyMode&&
   offlineDayStateReady;

  const canRegister=
   pointReady&&
   !journeyComplete&&
   !punchInFlight&&
   !syncInProgress&&
   !cooldownActive&&
   (
    serverReachable===true||
    offlineAllowed
   );

  button.disabled=!canRegister;
  button.dataset.pointReady=String(pointReady);
  button.dataset.serverReachable=String(serverReachable);
  button.dataset.syncInProgress=String(syncInProgress);
  button.dataset.punchInFlight=String(punchInFlight);
  button.dataset.marks=String(marks.length);

  if(canRegister){
   button.removeAttribute('disabled');
   button.classList.remove(
    'sync-lock',
    'loading',
    'cooldown',
    'lunch-wait'
   );
  }
 }

 function forceOnlineVisualState(){
  contingencyMode=false;
  syncInProgress=false;

  document.body.classList.remove('offline-contingency');
  document.getElementById('clock-time')?.classList.remove('offline-clock');

  const status=document.getElementById('offline-point-status');
  if(status)status.hidden=true;

  const banner=document.getElementById('sync-restored-banner');
  if(banner)banner.hidden=true;

  const punchButton=document.getElementById('registrar');
  punchButton?.classList.remove(
   'sync-lock','loading','cooldown','lunch-wait'
  );

  const movementPanel=document.querySelector('.movement-employee-panel');
  movementPanel?.classList.remove('offline-disabled-panel');
  movementPanel?.removeAttribute('aria-disabled');
  movementPanel?.querySelector('.offline-feature-notice')?.remove();
  movementPanel?.querySelectorAll('button,input,textarea,select').forEach(el=>{
   el.disabled=false;
  });

  const adjustmentPanel=document.getElementById('adjustment-panel');
  adjustmentPanel?.classList.remove('offline-disabled-panel');
  adjustmentPanel?.removeAttribute('aria-disabled');
  adjustmentPanel?.querySelector('.offline-feature-notice')?.remove();
  adjustmentPanel?.querySelectorAll('button,input,textarea,select').forEach(el=>{
   el.disabled=false;
  });

  const selfPinButton=document.getElementById('abrir-troca-pin');
  if(selfPinButton)selfPinButton.disabled=false;

  refreshPunchAvailability();
  unlockOnlinePunchButton();
 }

 async function setContingencyUI(active){
  if(!active)forceOnlineVisualState();
  contingencyMode=active;

  const foot=document.getElementById('clock-footnote');
  const status=document.getElementById('offline-point-status');
  const clock=document.getElementById('clock-time');
  const movementPanel=document.querySelector('.movement-employee-panel');
  const adjustmentPanel=document.getElementById('adjustment-panel');
  const changePinPanel=document.getElementById('change-pin-panel');
  const selfPinButton=document.getElementById('abrir-troca-pin');

  document.body.classList.toggle('offline-contingency',active);
  clock?.classList.toggle('offline-clock',active);

  foot.textContent=active
   ?'Horário registrado localmente neste computador. A marcação será validada após a sincronização.'
   :'O horário oficial é gerado e gravado pelo servidor do Supabase.';

  const counts=await window.PlenitudeOffline.counts();

  if(status){
   status.hidden=!active||serverReachable===true;
   status.querySelector('strong').textContent=
    `${counts.local} aguardando sincronização`;
  }

  if(movementPanel){
   movementPanel.classList.toggle('offline-disabled-panel',active);
   movementPanel.setAttribute('aria-disabled',String(active));

   movementPanel.querySelectorAll('button,input,textarea,select').forEach(element=>{
    element.disabled=active;
   });

   let notice=movementPanel.querySelector('.offline-feature-notice');

   if(active&&!notice){
    notice=document.createElement('div');
    notice.className='offline-feature-notice';
    notice.textContent='Indisponível sem internet. No modo offline, utilize apenas a marcação do ponto.';
    movementPanel.prepend(notice);
   }

   if(!active&&notice)notice.remove();
  }

  if(adjustmentPanel){
   adjustmentPanel.classList.toggle('offline-disabled-panel',active);
   adjustmentPanel.setAttribute('aria-disabled',String(active));

   adjustmentPanel.querySelectorAll('button,input,textarea,select').forEach(element=>{
    element.disabled=active;
   });

   let notice=adjustmentPanel.querySelector('.offline-feature-notice');

   if(active&&!notice){
    notice=document.createElement('div');
    notice.className='offline-feature-notice';
    notice.textContent='Solicitações ficam indisponíveis durante a contingência e poderão ser enviadas quando a conexão retornar.';
    adjustmentPanel.prepend(notice);
   }

   if(!active&&notice)notice.remove();

   if(active){
    adjustmentForm.hidden=true;
    adjustmentHelp.hidden=false;
   }
  }

  if(selfPinButton)selfPinButton.disabled=active;
  if(active&&changePinPanel)changePinPanel.hidden=true;

  if(!active){
   syncInProgress=false;

   const punchButton=document.getElementById('registrar');
   const syncBanner=document.getElementById('sync-restored-banner');

   punchButton?.classList.remove(
    'sync-lock',
    'loading',
    'cooldown',
    'lunch-wait'
   );

   if(syncBanner)syncBanner.hidden=true;
  }
 }

 async function syncOfflineQueue(){
  if(!navigator.onLine||serverReachable===false||!window.PlenitudeOffline)return false;

  const deviceToken=localStorage.getItem('plenitude-device-token')||'';
  if(!deviceToken)return false;

  const before=await window.PlenitudeOffline.counts();
  if(!before.local)return true;

  const banner=document.getElementById('sync-restored-banner');
  const text=document.getElementById('sync-restored-text');
  const punchButton=document.getElementById('registrar');

  syncInProgress=true;
  banner.hidden=false;
  text.textContent=`Importando ${before.local} registro(s) offline...`;

  if(punchButton){
   punchButton.disabled=true;
   punchButton.classList.add('sync-lock');
   punchButton.innerHTML='<span>⏳</span> Sincronizando registros...';
   punchButton.setAttribute(
    'aria-label',
    'Aguarde a sincronização completa antes de registrar um novo ponto.'
   );
  }

  try{
   const synced=await window.PlenitudeOffline.syncAll(client,deviceToken);
   const after=await window.PlenitudeOffline.counts();

   if(after.local>0){
    const failure=synced.failures?.[0];
    const detail=failure?.message
     ?` Motivo: ${failure.message}`
     :'';

    text.textContent=
     `${synced.length} enviado(s); ${after.local} ainda aguardam sincronização.${detail}`;

    console.error(
     'Falha ao sincronizar contingência',
     synced.failures||[]
    );

    return false;
   }

   text.textContent=
    `${synced.length} registro(s) importado(s). Atualizando a jornada oficial...`;
   return true;
  }finally{
   syncInProgress=false;
  }
 }

 async function registerOfflinePunch(){
  const deviceToken=localStorage.getItem('plenitude-device-token')||'';
  if(!deviceToken)throw new Error('Computador não autorizado para contingência.');

  if(!offlineDayStateReady){
   throw new Error(
    'O estado das marcações de hoje não foi preparado antes da queda de internet. Reconecte o sistema para atualizar a jornada.'
   );
  }

  const localMarks=await localTodayMarks();
  const combined=[...onlineMarks,...localMarks].sort(
   (a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em)
  );
  const tipo=nextType(combined.length);
  if(!tipo)throw new Error('As quatro marcações do dia já foram realizadas.');

  if(tipo==='fim_intervalo'){
   const lunch=combined.find(m=>m.tipo==='inicio_intervalo');
   const elapsed=Date.now()-new Date(lunch.registrado_em).getTime();
   if(elapsed<30*60*1000){
    const remaining=Math.ceil((30*60*1000-elapsed)/60000);
    throw new Error(`O retorno do almoço só pode ser registrado após 30 minutos. Aguarde mais ${remaining} minuto(s).`);
   }
  }

  const record=await window.PlenitudeOffline.createRecord({
   employee,tipo,deviceToken,existing:combined
  });

  await setContingencyUI(true);
  return {tipo:record.tipo,registrado_em:record.ocorrido_em_dispositivo,offline:true};
 }

 let connectionTransition=null;

 async function enterOfflineMode(message){
  serverReachable=false;
  syncInProgress=false;

  const banner=document.getElementById('sync-restored-banner');
  if(banner)banner.hidden=true;

  await setContingencyUI(true);
  setPointLoading(message||'Carregando jornada local...',55);
  await load();

  document.getElementById('clock-status').textContent='Pronto para registrar';
  setPointLoading('Jornada local carregada.',100);
  setTimeout(revealPoint,120);
 }

 async function enterOnlineMode(){
  if(connectionTransition)return connectionTransition;

  connectionTransition=(async()=>{
   const banner=document.getElementById('sync-restored-banner');
   const text=document.getElementById('sync-restored-text');

   setPointLoading('Confirmando conexão com o servidor...',15);

   try{
    employee=await fetchEmployeeOnline(5000);
    cacheEmployeeProfile();

    const pendingCount=(await window.PlenitudeOffline.counts()).local;

    if(pendingCount>0){
     if(banner)banner.hidden=false;
     if(text)text.textContent=
      `Importando ${pendingCount} registro(s) offline...`;

     setPointLoading('Sincronizando registros offline...',40);

     const completed=await syncOfflineQueue();

     if(!completed){
      throw new Error(
       'A fila offline ainda possui registros não sincronizados.'
      );
     }
    }else if(banner){
     banner.hidden=true;
     if(text)text.textContent='';
    }

    syncInProgress=false;
    serverReachable=true;

    setPointLoading('Carregando jornada oficial...',70);
    await load();

    await setContingencyUI(false);

    setPointLoading('Carregando recursos complementares...',88);
    await Promise.allSettled([
     loadAdjustments(),
     loadMovements()
    ]);

    document.getElementById('clock-status').textContent=
     'Pronto para registrar';

    setPointLoading('Finalizando...',100);
    setTimeout(revealPoint,120);
   }catch(error){
    syncInProgress=false;

    if(
     error?.code==='EMPLOYEE_SESSION_EXPIRED'||
     isExpiredEmployeeSession(error)
    ){
     await redirectToOnlineLogin();
    }else if(isNetworkFailure(error)){
     await enterOfflineMode(
      'Servidor indisponível. Recuperando a jornada local...'
     );
    }else{
     console.error('Falha ao restaurar o modo online',error);
     blockPoint(
      normalizedErrorMessage(error)||
      'Não foi possível carregar a jornada online.'
     );
    }
   }finally{
    connectionTransition=null;
   }
  })();

  return connectionTransition;
 }

 window.addEventListener('online',()=>{
  enterOnlineMode().catch(error=>
   console.warn('Transição online não concluída.',error)
  );
 });

 window.addEventListener('offline',()=>{
  if(connectionTransition)return;

  enterOfflineMode(
   'Conexão interrompida. Recuperando a jornada local...'
  ).catch(error=>{
   blockPoint(
    error.message||
    'Não foi possível recuperar a jornada offline.'
   );
  });
 });

 function clock(){const d=new Date();document.getElementById('clock-date').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(d);document.getElementById('clock-time').textContent=d.toLocaleTimeString('pt-BR')}
 function successSound(){try{const C=window.AudioContext||window.webkitAudioContext,ctx=new C();[523.25,659.25,783.99].forEach((f,i)=>{const o=ctx.createOscillator(),g=ctx.createGain();o.frequency.value=f;o.type='sine';g.gain.setValueAtTime(.0001,ctx.currentTime+i*.11);g.gain.exponentialRampToValueAtTime(.16,ctx.currentTime+i*.11+.02);g.gain.exponentialRampToValueAtTime(.0001,ctx.currentTime+i*.11+.18);o.connect(g);g.connect(ctx.destination);o.start(ctx.currentTime+i*.11);o.stop(ctx.currentTime+i*.11+.2)});setTimeout(()=>ctx.close(),800)}catch{}}
 function showSuccess(message){const b=document.getElementById('success-banner');b.querySelector('strong').textContent=message;b.hidden=false;b.classList.remove('show');void b.offsetWidth;b.classList.add('show');successSound();setTimeout(()=>{b.classList.remove('show');setTimeout(()=>b.hidden=true,250)},3200)}
 function applyLunchMinimumRule(marks,button,actionLabels){
  clearInterval(lunchMinimumTimer);
  lunchMinimumTimer=null;

  if(marks.length!==2){
   return false;
  }

  const lunchStart=new Date(marks[1].registrado_em).getTime();
  const unlockAt=lunchStart+(30*60*1000);

  const update=()=>{
   const remainingMs=unlockAt-Date.now();

   if(remainingMs<=0){
    clearInterval(lunchMinimumTimer);
    lunchMinimumTimer=null;
    button.disabled=punchInFlight||Date.now()<punchCooldownUntil;
    button.classList.remove('lunch-wait');
    button.innerHTML=`<span>◷</span> ${actionLabels[2]}`;
    button.setAttribute('aria-label',actionLabels[2]);
    document.getElementById('proxima').textContent='Próxima marcação: Retorno';
    return;
   }

   const remainingMinutes=Math.ceil(remainingMs/60000);
   const totalSeconds=Math.ceil(remainingMs/1000);
   const minutes=Math.floor(totalSeconds/60);
   const seconds=String(totalSeconds%60).padStart(2,'0');

   button.disabled=true;
   button.classList.add('lunch-wait');
   button.innerHTML=`<span>⏳</span> Retorno em ${minutes}:${seconds}`;
   button.setAttribute(
    'aria-label',
    `Retorno do almoço disponível em ${remainingMinutes} minuto(s)`
   );

   document.getElementById('proxima').textContent=
    `Intervalo mínimo: aguarde ${remainingMinutes} minuto(s) para registrar o retorno`;
  };

  update();
  lunchMinimumTimer=setInterval(update,1000);
  return true;
 }


 async function loadJourneyPendencies(){
  if(serverReachable!==true)return [];

  const [pendencyResult,adjustmentResult]=await Promise.allSettled([
   rpc('listar_minhas_pendencias_jornada',{p_token:token}),
   rpc('listar_meus_ajustes',{p_token:token})
  ]);

  if(pendencyResult.status==='rejected'){
   throw pendencyResult.reason;
  }

  const todayKey=new Intl.DateTimeFormat('en-CA',{
   timeZone:'America/Sao_Paulo',
   year:'numeric',
   month:'2-digit',
   day:'2-digit'
  }).format(new Date());

  /*
   * Defesa visual: pendências só podem aparecer para dias já encerrados.
   * Isso também impede que uma pendência antiga criada incorretamente seja
   * mostrada enquanto o banco ainda está sendo corrigido.
   */
  const rows=(pendencyResult.value||[])
   .filter(row=>String(row.data_local||'')<todayKey);

  const adjustments=
   adjustmentResult.status==='fulfilled'
    ?adjustmentResult.value||[]
    :[];

  const enriched=rows.map(row=>{
   const related=adjustments
    .filter(item=>
     item.data_marcacao===row.data_local&&
     item.tipo_marcacao===row.marcacao_faltante
    )
    .sort((a,b)=>
     new Date(b.criado_em||0)-new Date(a.criado_em||0)
    )[0]||null;

   return {
    ...row,
    solicitacao:related
   };
  });

  renderJourneyPendencies(enriched);
  return enriched;
 }

 function renderJourneyPendencies(rows){
  let box=document.getElementById('employee-journey-pendencies');
  const host=document.querySelector('.clock-action-card');

  if(!host)return;

  if(!box){
   box=document.createElement('section');
   box.id='employee-journey-pendencies';
   box.className='employee-journey-pendencies';
   host.insertAdjacentElement('afterend',box);
  }

  if(!rows?.length){
   box.hidden=true;
   box.innerHTML='';
   return;
  }

  box.hidden=false;
  box.innerHTML=rows.map(row=>{
   const date=new Date(`${row.data_local}T12:00:00`)
    .toLocaleDateString('pt-BR');
   const missing=row.marcacao_faltante_label||'marcação';
   const request=row.solicitacao||null;
   const status=String(request?.status||'').toLowerCase();

   if(status==='pendente'){
    return `
     <article class="journey-review-alert">
      <div class="journey-review-icon" aria-hidden="true">⏳</div>
      <div class="journey-alert-content">
       <div class="journey-alert-heading">
        <strong>CORREÇÃO ENVIADA</strong>
        <span class="journey-review-badge">EM ANÁLISE</span>
       </div>
       <p>A correção da jornada de <b>${date}</b> foi enviada.</p>
       <div class="journey-review-missing">${missing}</div>
       <small>
        Aguardando análise do administrador. Você pode continuar
        registrando o ponto normalmente.
       </small>
      </div>
      <button type="button" class="journey-review-action"
       data-view-adjustment="${request.id||''}">
       📄 Solicitação enviada
      </button>
     </article>`;
   }

   if(status==='rejeitada'){
    const response=request.resposta_administrador
     ?`<small class="journey-rejection-reason"><b>Resposta:</b> ${request.resposta_administrador}</small>`
     :'';

    return `
     <article class="journey-critical-alert journey-rejected-alert">
      <div class="journey-alert-icon" aria-hidden="true">!</div>
      <div class="journey-alert-content">
       <div class="journey-alert-heading">
        <strong>CORREÇÃO REJEITADA</strong>
        <span class="journey-alert-badge">AÇÃO NECESSÁRIA</span>
       </div>
       <p>A jornada de <b>${date}</b> continua incompleta.</p>
       <div class="journey-alert-missing">❌ ${missing.toUpperCase()}</div>
       ${response}
       <small>Revise os dados e envie uma nova solicitação.</small>
      </div>
      <button type="button" class="journey-alert-action"
       data-open-adjustment="${row.data_local}"
       data-mark-type="${row.marcacao_faltante}">
       📝 Enviar nova correção
      </button>
     </article>`;
   }

   return `
    <article class="journey-critical-alert">
     <div class="journey-alert-icon" aria-hidden="true">⚠</div>
     <div class="journey-alert-content">
      <div class="journey-alert-heading">
       <strong>ATENÇÃO! JORNADA INCOMPLETA</strong>
       <span class="journey-alert-badge">PENDÊNCIA</span>
      </div>
      <p>O dia <b>${date}</b> terminou sem o registro de:</p>
      <div class="journey-alert-missing">❌ ${missing.toUpperCase()}</div>
      <small>
       Envie uma solicitação de correção. O ponto atual continuará
       funcionando normalmente.
      </small>
     </div>
     <button type="button" class="journey-alert-action"
      data-open-adjustment="${row.data_local}"
      data-mark-type="${row.marcacao_faltante}">
      📝 Solicitar correção agora
     </button>
    </article>`;
  }).join('');

  box.querySelectorAll('[data-open-adjustment]').forEach(button=>{
   button.onclick=()=>{
    if(contingencyMode||serverReachable!==true){
     toast('A solicitação de correção exige conexão com o servidor.','warn');
     return;
    }

    setAdjustmentEditing(true);

    const dateInput=document.getElementById('ajuste-data');
    const typeInput=document.getElementById('ajuste-tipo');

    if(dateInput)dateInput.value=button.dataset.openAdjustment;
    if(typeInput)typeInput.value=button.dataset.markType||'saida';

    document.getElementById('adjustment-panel')
     ?.scrollIntoView({behavior:'smooth',block:'center'});
   };
  });

  box.querySelectorAll('[data-view-adjustment]').forEach(button=>{
   button.onclick=()=>{
    document.getElementById('my-adjustments')
     ?.scrollIntoView({behavior:'smooth',block:'center'});
   };
  });
 }

 async function load(){
  const now=new Date();
  const today=dateKey(now);
  const monday=new Date(now);
  monday.setDate(now.getDate()-((now.getDay()+6)%7));
  const firstMonth=new Date(now.getFullYear(),now.getMonth(),1);
  const isHomologation=
   String(employee?.matricula||'').replace(/^0+/,'')==='999';
  const weekStart=isHomologation?today:dateKey(monday);
  const monthStart=isHomologation?today:dateKey(firstMonth);

  let data=[];
  let todayBank=null;
  let weekBank=null;
  let monthBank=null;

  if(serverReachable===true){
   try{
    data=await rpc(
     'marcacoes_funcionario_token',
     {p_token:token,p_inicio:today,p_fim:today}
    );

    onlineMarks=data||[];
    offlineDayStateReady=true;
    contingencyMode=false;
    syncInProgress=false;

    await saveOfficialDayState(today,onlineMarks);
    setOfflineDayStateWarning(false);
    await setContingencyUI(false);
    forceOnlineVisualState();

    const balances=await Promise.allSettled([
     rpc(
      'banco_horas_funcionario_token',
      {p_token:token,p_inicio:today,p_fim:today}
     ),
     rpc(
      'banco_horas_funcionario_token',
      {p_token:token,p_inicio:weekStart,p_fim:today}
     ),
     rpc(
      'banco_horas_funcionario_token',
      {p_token:token,p_inicio:monthStart,p_fim:today}
     )
    ]);

    todayBank=
     balances[0].status==='fulfilled'
      ?balances[0].value
      :null;

    weekBank=
     balances[1].status==='fulfilled'
      ?balances[1].value
      :null;

    monthBank=
     balances[2].status==='fulfilled'
      ?balances[2].value
      :null;
   }catch(error){
    if(!isNetworkFailure(error))throw error;
    serverReachable=false;
   }
  }

  if(serverReachable!==true){
   await setContingencyUI(true);

   const snapshot=await loadOfficialDayState(today);

   if(snapshot){
    onlineMarks=snapshot.marks||[];
    data=onlineMarks;
    offlineDayStateReady=true;
    setOfflineDayStateWarning(false);
   }else{
    onlineMarks=[];
    data=[];
    offlineDayStateReady=false;

    setOfflineDayStateWarning(
     true,
     'Por segurança, o registro local foi bloqueado. Abra o ponto com internet ao menos uma vez no mesmo dia antes de usar a contingência.'
    );
   }
  }

  const localMarks=await localTodayMarks();
  const marks=[...(data||[]),...localMarks].sort(
   (a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em)
  );

  currentJourneyMarks=marks;
  document.getElementById('lista-pontos').innerHTML=marks.length?marks.map(m=>`<div class="punch-item ${m.offline?'offline-mark':''}"><span>${label(m.tipo)}${m.offline?' <em>OFFLINE</em>':''}</span><strong>${fmt(m.registrado_em)}</strong></div>`).join(''):'<div class="mini-empty">Nenhuma marcação feita hoje.</div>';
  const labels=['Entrada','Almoço','Retorno','Saída'];
  const actionLabels=['Registrar entrada','Registrar saída para almoço','Registrar retorno do almoço','Registrar saída final'];
  const nextLabel=marks.length<4?labels[marks.length]:null;
  document.getElementById('proxima').textContent=nextLabel?`Próxima marcação: ${nextLabel}`:'Jornada de hoje concluída';
  const punchButton=document.getElementById('registrar');
  const actionText=marks.length<4
   ?`${actionLabels[marks.length]}${contingencyMode?' — gravação local':''}`
   :'Jornada concluída';

  punchButton.innerHTML=marks.length<4
   ?`<span>◷</span> ${actionText}`
   :'<span>✓</span> Jornada concluída';

  punchButton.setAttribute('aria-label',actionText);
  document.getElementById('punch-progress').innerHTML=labels.map((_,i)=>`<span class="progress-step ${i<marks.length?'done':''}"></span>`).join('');
  document.getElementById('punch-steps').innerHTML=labels.map((n,i)=>`<div class="punch-step ${i<marks.length?'done':''} ${i===marks.length?'current':''}"><span class="step-icon">${i<marks.length?'✓':i+1}</span><strong>${n}</strong><small>${marks[i]?fmt(marks[i].registrado_em):'Aguardando'}</small></div>`).join('');
  const progressPercent=Math.min(100,marks.length*25);
  document.getElementById('journey-progress-label').textContent=`${progressPercent}% da jornada`;
  document.getElementById('journey-progress-stage').textContent=marks.length<4?`Etapa atual: ${labels[marks.length]}`:'Jornada concluída';
  document.getElementById('journey-progress-fill').style.width=`${progressPercent}%`;
  const completedCard=document.getElementById('journey-complete-card');
  const movementPanel=document.querySelector('.movement-employee-panel');
  if(marks.length>=4){
    completedCard.hidden=false;
    document.getElementById('journey-complete-summary').textContent=marks.map(m=>`${label(m.tipo)} ${fmt(m.registrado_em)}`).join(' · ');
    movementPanel.hidden=true;
  }else{completedCard.hidden=true;movementPanel.hidden=false;}
  const signed=n=>`${n>=0?'+':'−'}${String(Math.floor(Math.abs(n||0)/60)).padStart(2,'0')}:${String(Math.abs(n||0)%60).padStart(2,'0')}`;
  const todaySummary=todayBank?.resumo||{},todayDay=todayBank?.dias?.[0];
  document.getElementById('self-today-balance').textContent=todayDay?.saldo_minutos==null?(marks.length?'Em andamento':'Aguardando'):signed(todayDay.saldo_minutos);
  document.getElementById('self-week-balance').textContent=signed(weekBank?.resumo?.saldo_minutos||0);
  document.getElementById('self-month-balance').textContent=signed(monthBank?.resumo?.saldo_minutos||0);
  const lunchLocked=applyLunchMinimumRule(marks,punchButton,actionLabels);

  if(!lunchLocked){
   punchButton.disabled=
    marks.length>=4||
    punchInFlight||
    syncInProgress||
    Date.now()<punchCooldownUntil||
    (contingencyMode&&!offlineDayStateReady);
  }

  if(syncInProgress){
   punchButton.disabled=true;
   punchButton.classList.add('sync-lock');
   punchButton.innerHTML='<span>⏳</span> Sincronizando registros...';
   punchButton.setAttribute(
    'aria-label',
    'Aguarde a sincronização completa antes de registrar um novo ponto.'
   );
   document.getElementById('proxima').textContent=
    'Aguarde a conclusão da sincronização';
  }else{
   punchButton.classList.remove('sync-lock');
  }

  if(contingencyMode&&!offlineDayStateReady&&!syncInProgress){
   punchButton.innerHTML='<span>⚠</span> Jornada não preparada para uso offline';
   punchButton.setAttribute(
    'aria-label',
    'Registro offline indisponível porque as marcações de hoje não foram preparadas.'
   );
   document.getElementById('proxima').textContent=
    'Reconecte o sistema para atualizar as marcações de hoje';
  }
  if(serverReachable===true){
   forceOnlineVisualState();
  }

  refreshPunchAvailability();
  unlockOnlinePunchButton();

  if(Date.now()>=punchCooldownUntil){
   punchButton.classList.remove('cooldown');
  }
  document.body.classList.toggle('homologation-employee',isHomologation);
  const note=document.getElementById('homologation-note');if(note)note.hidden=!isHomologation;
 }
 async function init(){
  clearTimeout(window.__plenitudePointBootTimeout);

  document.body.classList.add(
   'employee-mode',
   'kiosk-point-mode'
  );

  document.getElementById('ponto-funcionario-select').hidden=true;

  clock();
  setInterval(clock,1000);
  setPointLoading('Abrindo ponto...',10);

  try{
   try{
    employee=await fetchEmployeeOnline(5000);
    cacheEmployeeProfile();
   }catch(error){
    if(!isNetworkFailure(error))throw error;

    serverReachable=false;
    employee=restoreEmployeeProfile();

    if(!employee){
     throw new Error(
      'Sem conexão e sem perfil de contingência preparado para este funcionário.'
     );
    }
   }

   document.getElementById('clock-employee').textContent=employee.nome;
   document.getElementById('clock-status').textContent=
    'Carregando jornada';

   renderEmployeeAvatar(employee);

   const self=document.getElementById('employee-self-service');
   self.hidden=false;

   document.getElementById('self-profile-name').textContent=
    employee.nome;

   document.getElementById('self-profile-role').textContent=
    employee.cargo||'Funcionário';

   document.getElementById('self-profile-code').textContent=
    employee.matricula;

   document.getElementById('change-pin-panel').hidden=
    !employee.exigir_troca_pin;

   if(serverReachable===true){
    const pendingCount=
     (await window.PlenitudeOffline.counts()).local;

    if(pendingCount>0){
     setPointLoading(
      `Sincronizando ${pendingCount} registro(s) offline...`,
      40
     );

     const completed=await syncOfflineQueue();

     if(!completed){
      throw new Error(
       'A fila offline ainda possui registros não sincronizados.'
      );
     }
    }
   }

   setPointLoading(
    serverReachable===true
     ?'Carregando jornada oficial...'
     :'Carregando jornada local...',
    70
   );

   await load();

   if(serverReachable===true){
    await setContingencyUI(false);
    forceOnlineVisualState();
   }else{
    await setContingencyUI(true);
   }

   document.getElementById('clock-status').textContent=
    'Pronto para registrar';

   setPointLoading('Finalizando...',100);

   if(serverReachable===true){
    Promise.allSettled([
     loadAdjustments(),
     loadMovements(),
     loadJourneyPendencies()
    ]).then(results=>{
     results.forEach((result,index)=>{
      if(result.status==='rejected'){
       console.warn(
        ['Ajustes indisponíveis','Movimentações indisponíveis','Pendências de jornada indisponíveis'][index],
        result.reason
       );
      }
     });
    });
   }

   if('serviceWorker' in navigator&&serverReachable===true){
    navigator.serviceWorker
     .register('./sw.js?v=1.0.0-rc5.28')
     .catch(error=>
      console.warn('Service Worker indisponível',error)
     );
   }

   setTimeout(revealPoint,120);
  }catch(error){
   console.error(
    'Falha ao iniciar área do funcionário',
    error
   );

   if(
    error?.code==='EMPLOYEE_SESSION_EXPIRED'||
    isExpiredEmployeeSession(error)
   ){
    await redirectToOnlineLogin();
    return;
   }

   const message=normalizedErrorMessage(error);

   toast(
    message||
    'Não foi possível abrir a área do funcionário.',
    'warn'
   );

   blockPoint(
    message||
    'Não foi possível carregar completamente a jornada.'
   );

   if(/sessão|token|inválid|expirada/i.test(message)){
    sessionStorage.removeItem(
     'plenitude-employee-session'
    );

    setTimeout(
     ()=>location.replace('index.html'),
     1400
    );
   }
  }
 }
 function startPunchCooldown(button, seconds=5){
  punchCooldownUntil=Date.now()+(seconds*1000);
  clearInterval(punchCooldownTimer);

  const update=()=>{
    const remaining=Math.ceil((punchCooldownUntil-Date.now())/1000);
    if(remaining<=0){
      clearInterval(punchCooldownTimer);
      punchCooldownTimer=null;
      punchCooldownUntil=0;
      if(!punchInFlight){
        load().catch(error=>console.warn('Não foi possível atualizar o botão após a trava.',error));
      }
      return;
    }
    button.disabled=true;
    button.classList.add('cooldown');
    button.innerHTML=`<span>⏳</span> Aguarde ${remaining}s`;
    button.setAttribute('aria-label',`Aguarde ${remaining} segundos antes da próxima marcação`);
  };

  update();
  punchCooldownTimer=setInterval(update,250);
}

document.getElementById('registrar').onclick=async()=>{
  const b=document.getElementById('registrar');

  if(!pointReady){
    toast('Aguarde o carregamento completo da jornada.','warn');
    return;
  }

  if(syncInProgress){
    toast(
      'Aguarde a sincronização completa antes de registrar um novo ponto.',
      'warn'
    );
    return;
  }

  if(punchInFlight){
    toast('A marcação já está sendo processada. Aguarde.','warn');
    return;
  }

  const remaining=Math.ceil((punchCooldownUntil-Date.now())/1000);
  if(remaining>0){
    toast(`Aguarde ${remaining} segundo(s) antes de registrar novamente.`,'warn');
    return;
  }

  punchInFlight=true;
  const previous=b.innerHTML;
  b.disabled=true;
  b.classList.add('loading');
  b.innerHTML='<span>⏳</span> Registrando...';
  b.setAttribute('aria-busy','true');

  try{
    const deviceToken=localStorage.getItem('plenitude-device-token')||'';
    if(!deviceToken)throw new Error('Registro bloqueado: computador não autorizado.');

    const data=await rpc('registrar_ponto_dispositivo',{
      p_token:token,
      p_dispositivo_token:deviceToken,
      p_user_agent:navigator.userAgent
    });

    const m=Array.isArray(data)?data[0]:data;
    showSuccess(`${label(m.tipo)} registrada às ${fmt(m.registrado_em)}`);
    toast(`${label(m.tipo)} registrada às ${fmt(m.registrado_em)}.`);
    await load();

    // Mantém a interface protegida mesmo depois da resposta do servidor.
    startPunchCooldown(b,5);
  }catch(e){
    if(isNetworkFailure(e)){
     try{
      const m=await registerOfflinePunch();
      showSuccess(
       `${label(m.tipo)} gravada em contingência às ${fmt(m.registrado_em)}`
      );

      await load();

      toast(
       `${label(m.tipo)} salva localmente e aguardando sincronização.`,
       'warn'
      );

      startPunchCooldown(b,5);
     }catch(offlineError){
      console.error('Falha após tentativa de registro offline',offlineError);

      try{
       await load();
      }catch(loadError){
       console.warn(
        'Não foi possível atualizar imediatamente a jornada local.',
        loadError
       );
      }

      toast(normalizedErrorMessage(offlineError),'warn');
      b.innerHTML=previous;
      refreshPunchAvailability();
     }
    }else{
     toast(normalizedErrorMessage(e),'warn');
     b.innerHTML=previous;
     refreshPunchAvailability();
    }
  }finally{
    punchInFlight=false;
    b.classList.remove('loading');
    b.removeAttribute('aria-busy');
  }
};
 document.getElementById('fullscreen-toggle').onclick=async()=>{try{if(!document.fullscreenElement){await document.documentElement.requestFullscreen();document.getElementById('fullscreen-toggle').textContent='✕ Sair da tela cheia'}else{await document.exitFullscreen();document.getElementById('fullscreen-toggle').textContent='⛶ Tela cheia'}}catch(e){toast('O navegador não permitiu ativar a tela cheia.','warn')}};
 document.addEventListener('fullscreenchange',()=>{document.getElementById('fullscreen-toggle').textContent=document.fullscreenElement?'✕ Sair da tela cheia':'⛶ Tela cheia'});
 document.getElementById('sair').onclick=async()=>{try{await rpc('encerrar_sessao_funcionario',{p_token:token})}catch{}sessionStorage.removeItem('plenitude-employee-session');location.replace('index.html')};
 document.getElementById('abrir-troca-pin').onclick=()=>document.getElementById('change-pin-panel').hidden=false;


 async function loadMovements(){
  const today=dateKey(new Date());

  let rows=[];
  let status=null;

  const results=await Promise.allSettled([
   rpc('status_movimentacao_funcionario',{p_token:token}),
   rpc('listar_minhas_movimentacoes',{p_token:token,p_inicio:today,p_fim:today})
  ]);

  if(results[0].status==='fulfilled'){
   const raw=results[0].value;
   status=Array.isArray(raw)?raw[0]:raw;
  }else{
   console.error('Falha ao consultar o estado da movimentação:',results[0].reason);
  }

  if(results[1].status==='fulfilled'){
   rows=results[1].value||[];
  }else{
   console.warn('Histórico de movimentações indisponível:',results[1].reason);
  }

  // Fonte principal: RPC específica. Fallback: listagem do próprio dia.
  const fallbackOpen=(rows||[]).find(item=>item.status==='aberta');
  const open=status?.fora_da_loja
   ?status.movimentacao_aberta
   :fallbackOpen||null;

  const pendingAlert=document.getElementById('movement-pending-alert');
  const pendingCount=Number(status?.pendencias_antigas||0);

  if(pendingAlert){
   if(pendingCount>0){
    const oldest=status?.pendencia_mais_antiga
     ?new Date(status.pendencia_mais_antiga+'T12:00:00').toLocaleDateString('pt-BR')
     :'data anterior';

    pendingAlert.hidden=false;
    pendingAlert.innerHTML=`
     <strong>⚠ ${pendingCount} retorno${pendingCount===1?'':'s'} não registrado${pendingCount===1?'':'s'}</strong>
     <span>A pendência mais antiga é de ${oldest}. Ela não bloqueia uma nova saída hoje, mas deve ser regularizada pelo administrador.</span>`;
   }else{
    pendingAlert.hidden=true;
    pendingAlert.innerHTML='';
   }
  }

  const state=document.getElementById('movement-state');
  const exitTrigger=document.getElementById('temporary-exit');
  const exitForm=document.getElementById('movement-exit-form');
  const exitReason=document.getElementById('movement-reason');
  const returnButton=document.getElementById('temporary-return');
  const box=document.getElementById('my-movements');

  if(state){
   state.textContent=open?'Fora da loja':'Dentro da loja';
   state.className=`badge ${open?'warn':''}`;
  }

  if(exitTrigger)exitTrigger.hidden=!!open;
  if(returnButton)returnButton.hidden=!open;

  if(open){
   if(exitForm){
    exitForm.hidden=true;
    exitForm.setAttribute('hidden','');
   }
   if(exitReason){
    exitReason.disabled=true;
    exitReason.value='';
   }
   if(exitTrigger){
    exitTrigger.hidden=true;
    exitTrigger.setAttribute('hidden','');
    exitTrigger.setAttribute('aria-expanded','false');
   }
   if(returnButton){
    returnButton.hidden=false;
    returnButton.removeAttribute('hidden');
   }
  }else{
   if(exitTrigger){
    exitTrigger.hidden=false;
    exitTrigger.removeAttribute('hidden');
   }
   if(returnButton){
    returnButton.hidden=true;
    returnButton.setAttribute('hidden','');
   }
   if(exitForm?.hidden && exitReason){
    exitReason.disabled=true;
   }
  }

  const todayRows=Array.isArray(rows)?[...rows]:[];

  if(open && !todayRows.some(item=>item.id===open.id)){
   todayRows.unshift(open);
  }

  if(box){
   box.innerHTML=todayRows.length
    ?todayRows.map(r=>`
     <div class="movement-item">
      <div>
       <strong>${r.status==='aberta'?'Saída temporária em andamento':'Saída temporária'}</strong>
       <small>${fmt(r.inicio_em)}${r.fim_em?` → ${fmt(r.fim_em)}`:' → aguardando retorno'}${r.motivo_informado?` · ${r.motivo_informado}`:''}</small>
      </div>
      <span class="request-status ${r.status==='aberta'?'pendente':r.aprovado?'aprovada':'pendente'}">
       ${r.status==='aberta'?'fora da loja':r.aprovado?(r.classificacao||'analisada'):'aguardando análise'}
      </span>
     </div>`).join('')
    :'<div class="mini-empty">Nenhuma saída temporária hoje.</div>';
  }

  return {open,status,rows:todayRows};
 }
 function setTemporaryExitEditing(open){
  const trigger=document.getElementById('temporary-exit');
  const form=document.getElementById('movement-exit-form');
  const reason=document.getElementById('movement-reason');

  form.hidden=!open;
  reason.disabled=!open;
  trigger.hidden=open;
  trigger.setAttribute('aria-expanded',String(open));

  if(open){
   requestAnimationFrame(()=>reason.focus());
  }else{
   reason.value='';
  }
 }

 async function registerMovement(action){
  if(contingencyMode||!navigator.onLine){
   return toast('Movimentações temporárias ficam indisponíveis no modo offline.','warn');
  }

  const deviceToken=localStorage.getItem('plenitude-device-token')||'';
  if(!deviceToken)return toast('Registro bloqueado: computador não autorizado.','warn');

  const reason=document.getElementById('movement-reason').value.trim();
  if(action==='saida'&&reason.length<3){
   document.getElementById('movement-reason').focus();
   return toast('Informe resumidamente o motivo da saída.','warn');
  }

  const btn=action==='saida'
   ?document.getElementById('temporary-exit-send')
   :document.getElementById('temporary-return');

  const previous=btn.textContent;
  btn.disabled=true;
  btn.textContent=action==='saida'?'Enviando...':'Registrando retorno...';

  try{
   const r=await rpc('registrar_movimentacao_dispositivo',{
    p_token:token,
    p_dispositivo_token:deviceToken,
    p_acao:action,
    p_motivo:reason||null,
    p_user_agent:navigator.userAgent
   });

   showSuccess(
    action==='saida'
     ?`Saída temporária registrada às ${fmt(r.inicio_em)}`
     :`Retorno registrado às ${fmt(r.fim_em)}`
   );

   document.getElementById('movement-reason').value='';
   setTemporaryExitEditing(false);
   await Promise.all([loadMovements(),load()]);
  }catch(e){
   toast(e.message,'warn');

   if(action==='saida' && /já existe uma saída temporária/i.test(e.message||'')){
    const state=document.getElementById('movement-state');
    const exitForm=document.getElementById('movement-exit-form');
    const exitTrigger=document.getElementById('temporary-exit');
    const returnButton=document.getElementById('temporary-return');

    if(state){
     state.textContent='Fora da loja';
     state.className='badge warn';
    }
    if(exitForm)exitForm.hidden=true;
    if(exitTrigger)exitTrigger.hidden=true;
    if(returnButton)returnButton.hidden=false;
   }

   await loadMovements().catch(error=>console.warn('Não foi possível atualizar o estado da movimentação.',error));
  }finally{
   btn.disabled=false;
   btn.textContent=previous;
  }
 }

 document.getElementById('temporary-exit').onclick=()=>setTemporaryExitEditing(true);
 document.getElementById('temporary-exit-cancel').onclick=()=>setTemporaryExitEditing(false);
 document.getElementById('temporary-exit-send').onclick=()=>registerMovement('saida');
 document.getElementById('temporary-return').onclick=()=>registerMovement('retorno');

 async function loadAdjustments(){
  const data=await rpc('listar_meus_ajustes',{p_token:token}),box=document.getElementById('my-adjustments');
  const rows=data||[];box.innerHTML=rows.length?`<h4>Minhas solicitações</h4>${rows.slice(0,8).map(r=>`<div class="adjustment-item"><div><strong>${new Date(r.data_marcacao+'T12:00:00').toLocaleDateString('pt-BR')} · ${label(r.tipo_marcacao)}</strong><small>${String(r.horario_solicitado).slice(0,5)} — ${r.justificativa}</small>${r.resposta_administrador?`<em>Resposta: ${r.resposta_administrador}</em>`:''}</div><span class="request-status ${r.status}">${r.status}</span></div>`).join('')}`:'<div class="mini-empty">Nenhuma solicitação de ajuste.</div>';
 }
 const adjustmentToggle=document.getElementById('toggle-adjustment');
 const adjustmentForm=document.getElementById('adjustment-form');
 const adjustmentHelp=document.getElementById('adjustment-help');

 function setAdjustmentEditing(open){
  adjustmentForm.hidden=!open;
  adjustmentToggle.textContent=open?'Cancelar solicitação':'Abrir nova solicitação';
  adjustmentToggle.classList.toggle('danger-soft',open);
  adjustmentToggle.setAttribute('aria-expanded',String(open));
  adjustmentHelp.hidden=open;

  if(open){
   document.getElementById('ajuste-data').value=dateKey(new Date());
   requestAnimationFrame(()=>document.getElementById('ajuste-data').focus());
  }else{
   adjustmentForm.reset();
  }
 }

 adjustmentToggle.onclick=()=>{
  if(contingencyMode||!navigator.onLine){
   return toast('Solicitações de ajuste ficam indisponíveis no modo offline.','warn');
  }

  setAdjustmentEditing(adjustmentForm.hidden);
 };

 adjustmentForm.onsubmit=async e=>{
  e.preventDefault();

  if(contingencyMode||!navigator.onLine){
   return toast('A solicitação será liberada quando a conexão retornar.','warn');
  }

  const b=e.submitter;
  if(b.disabled)return;

  b.disabled=true;
  b.textContent='Enviando...';

  try{
   await rpc('solicitar_ajuste_ponto',{
    p_token:token,
    p_data:document.getElementById('ajuste-data').value,
    p_tipo:document.getElementById('ajuste-tipo').value,
    p_horario:document.getElementById('ajuste-horario').value,
    p_justificativa:document.getElementById('ajuste-justificativa').value
   });

   toast('Solicitação enviada para análise.');
   setAdjustmentEditing(false);

   await Promise.all([
    loadAdjustments(),
    loadJourneyPendencies()
   ]);
  }catch(err){
   toast(err.message,'warn');
  }finally{
   b.disabled=false;
   b.textContent='Enviar solicitação';
  }
 };

 document.getElementById('alterar-meu-pin').onclick=async()=>{
  if(contingencyMode||!navigator.onLine){
   return toast('A alteração de PIN exige conexão com o servidor.','warn');
  }

  const a=document.getElementById('pin-atual').value,n=document.getElementById('pin-novo').value,c=document.getElementById('pin-confirmar').value;if(!/^\d{4}$/.test(n)||n!==c)return toast('O novo PIN deve ter 4 números e coincidir com a confirmação.','warn');try{await rpc('alterar_proprio_pin',{p_token:token,p_pin_atual:a,p_novo_pin:n});toast('PIN alterado com sucesso.');document.getElementById('change-pin-panel').hidden=true}catch(e){toast(e.message,'warn')}};
 init();
})();
