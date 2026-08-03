(function(){
'use strict';

const $=id=>document.getElementById(id);

function formatDateTime(date){
 return new Intl.DateTimeFormat('pt-BR',{
  dateStyle:'short',
  timeStyle:'medium'
 }).format(date);
}

function formatTime(date){
 return new Intl.DateTimeFormat('pt-BR',{
  hour:'2-digit',
  minute:'2-digit',
  second:'2-digit',
  hour12:false
 }).format(date);
}

function formatDate(date){
 return new Intl.DateTimeFormat('pt-BR',{
  dateStyle:'full'
 }).format(date);
}

function versionFromUrl(url){
 const match=String(url||'').match(/[?&]v=([^&]+)/);
 return match?decodeURIComponent(match[1]):'sem versão';
}

function renderCheck(ok,title,detail){
 return `<article class="diagnostic-check ${ok?'ok':'fail'}">
  <span>${ok?'✓':'!'}</span>
  <div><strong>${title}</strong><small>${detail}</small></div>
 </article>`;
}


function formatDuration(ms){
 const absolute=Math.abs(Number(ms)||0);
 const totalSeconds=Math.round(absolute/1000);
 const minutes=Math.floor(totalSeconds/60);
 const seconds=totalSeconds%60;

 if(minutes>0){
  return `${minutes} minuto(s) e ${seconds} segundo(s)`;
 }

 return `${seconds} segundo(s)`;
}

function showSyncResult({
 ok,
 title,
 serverDate=null,
 localDate=null,
 offsetMs=null,
 latencyMs=null,
 source=null,
 message=''
}){
 const dialog=$('diag-sync-dialog');
 const body=$('diag-sync-body');

 $('diag-sync-title').textContent=title;
 dialog.classList.toggle('success',Boolean(ok));
 dialog.classList.toggle('error',!ok);

 if(ok){
  const direction=
   Number(offsetMs)>0
    ?'atrasado'
    :Number(offsetMs)<0
      ?'adiantado'
      :'sincronizado';

  body.innerHTML=`
   <article class="sync-result-status success">
    <span>✓</span>
    <div>
     <strong>Sincronização concluída</strong>
     <small>O sistema atualizou sua referência de tempo.</small>
    </div>
   </article>

   <div class="sync-result-grid">
    <div>
     <span>Horário do Supabase</span>
     <strong>${formatTime(serverDate)}</strong>
    </div>
    <div>
     <span>Horário do computador</span>
     <strong>${formatTime(localDate)}</strong>
    </div>
    <div>
     <span>Diferença encontrada</span>
     <strong>${formatDuration(offsetMs)}</strong>
     <small>
      ${direction==='sincronizado'
       ?'Relógios sincronizados'
       :`Computador ${direction} em relação ao servidor`}
     </small>
    </div>
    <div>
     <span>Fonte utilizada</span>
     <strong>${source==='server'?'Supabase':'Indisponível'}</strong>
    </div>
    <div>
     <span>Latência da consulta</span>
     <strong>${Math.round(latencyMs||0)} ms</strong>
    </div>
    <div>
     <span>Última sincronização</span>
     <strong>${formatDateTime(new Date())}</strong>
    </div>
   </div>
  `;
 }else{
  body.innerHTML=`
   <article class="sync-result-status error">
    <span>!</span>
    <div>
     <strong>Não foi possível sincronizar</strong>
     <small>${message||'O horário oficial não pôde ser consultado.'}</small>
    </div>
   </article>

   <div class="notice compact danger">
    O sistema não tratará o horário local como oficial enquanto estiver online
    sem resposta do Supabase. Verifique a conexão e tente novamente.
   </div>
  `;
 }

 dialog.showModal();
}

async function getServerTimeDirect(){
 const started=Date.now();
 const {data,error}=await window.PlenitudeAuth.client.rpc('horario_oficial_sistema');
 const finished=Date.now();

 if(error)throw error;

 const row=Array.isArray(data)?data[0]:data;
 if(!row?.agora)throw new Error('O Supabase não retornou o horário oficial.');

 const midpoint=started+((finished-started)/2);
 const serverDate=new Date(row.agora);

 return {
  serverDate,
  timezone:row.timezone||'America/Sao_Paulo',
  dataLocal:row.data_local,
  offsetMs:serverDate.getTime()-midpoint,
  latencyMs:finished-started
 };
}

async function getServiceWorkerInfo(){
 if(!('serviceWorker' in navigator)){
  return {supported:false};
 }

 const registration=await navigator.serviceWorker.getRegistration();
 const controller=navigator.serviceWorker.controller;

 return {
  supported:true,
  registration,
  controller,
  status:registration?.active?.state||registration?.waiting?.state||registration?.installing?.state||'não registrado',
  script:registration?.active?.scriptURL||registration?.waiting?.scriptURL||registration?.installing?.scriptURL||'—',
  scope:registration?.scope||'—',
  controlled:Boolean(controller)
 };
}

function loadedVersion(selector){
 const node=document.querySelector(selector);
 return versionFromUrl(node?.href||node?.src||'');
}

async function refresh(){
 const banner=$('diag-status-banner');
 banner.className='notice';
 banner.textContent='Atualizando diagnóstico...';

 const checks=[];
 const localDate=new Date();

 $('diag-local-time').textContent=formatTime(localDate);
 $('diag-local-date').textContent=formatDate(localDate);
 $('diag-online').textContent=navigator.onLine?'Online':'Offline';
 $('diag-browser').textContent=navigator.userAgent;

 let serverInfo=null;
 try{
  serverInfo=await getServerTimeDirect();
  $('diag-server-time').textContent=formatTime(serverInfo.serverDate);
  $('diag-server-date').textContent=
   `${formatDate(serverInfo.serverDate)} · ${serverInfo.timezone}`;
  $('diag-timezone').textContent=serverInfo.timezone;
  $('diag-offset-ms').textContent=`${Math.round(serverInfo.offsetMs)} ms`;
  $('diag-sync-at').textContent=formatDateTime(new Date());

  const minutes=Math.abs(serverInfo.offsetMs)/60000;
  const direction=serverInfo.offsetMs>0?'atrasado':'adiantado';
  $('diag-offset').textContent=
   minutes<1
    ?`${Math.round(Math.abs(serverInfo.offsetMs)/1000)} segundo(s)`
    :`${minutes.toFixed(1)} minuto(s)`;

  $('diag-offset-detail').textContent=
   Math.abs(serverInfo.offsetMs)<1000
    ?'Relógios praticamente idênticos'
    :`O computador está ${direction} em relação ao servidor`;

  checks.push(renderCheck(
   Math.abs(serverInfo.offsetMs)<60000,
   'Diferença do relógio',
   Math.abs(serverInfo.offsetMs)<60000
    ?'Dentro da margem aceitável de 1 minuto.'
    :`Diferença elevada: ${Math.abs(serverInfo.offsetMs/60000).toFixed(1)} minuto(s).`
  ));
 }catch(error){
  console.error(error);
  $('diag-server-time').textContent='Erro';
  $('diag-server-date').textContent=error.message;
  $('diag-offset').textContent='—';
  $('diag-offset-detail').textContent='Não foi possível comparar';
  checks.push(renderCheck(false,'Hora oficial',error.message));
 }

 try{
  await window.PlenitudeClock.sync();
  const info=window.PlenitudeClock.info();
  $('diag-source').textContent=
   info.source==='server'
    ?'Supabase'
    :info.source==='local'
      ?'Relógio local'
      :'Indisponível';
  $('diag-last-sync').textContent=
   info.lastSyncAt
    ?`Última sincronização: ${formatDateTime(new Date(info.lastSyncAt))}`
    :'Ainda não sincronizado';

  checks.push(renderCheck(
   info.source==='server',
   'Fonte usada pelo sistema',
   info.source==='server'
    ?'O sistema está usando o relógio oficial do Supabase.'
    :'O sistema não está usando o relógio oficial.'
  ));
 }catch(error){
  $('diag-source').textContent='Erro';
  $('diag-last-sync').textContent=error.message;
  checks.push(renderCheck(false,'Módulo de relógio',error.message));
 }

 try{
  const sw=await getServiceWorkerInfo();
  $('diag-sw-status').textContent=sw.supported?sw.status:'Não suportado';
  $('diag-sw-script').textContent=sw.script||'—';
  $('diag-sw-scope').textContent=sw.scope||'—';
  $('diag-sw-controller').textContent=sw.controlled?'Sim':'Não';

  checks.push(renderCheck(
   sw.supported&&sw.status==='activated'&&sw.controlled,
   'Service Worker',
   sw.supported
    ?`Status: ${sw.status}; controlando a página: ${sw.controlled?'sim':'não'}.`
    :'Navegador sem suporte a Service Worker.'
  ));
 }catch(error){
  console.error(error);
  checks.push(renderCheck(false,'Service Worker',error.message));
 }

 $('diag-css-version').textContent=loadedVersion('link[rel="stylesheet"]');
 $('diag-js-version').textContent=loadedVersion('script[src*="diagnostico.js"]');

 const versionsOk=
  $('diag-css-version').textContent.includes('rc5.64')&&
  $('diag-js-version').textContent.includes('rc5.64');

 checks.push(renderCheck(
  versionsOk,
  'Versão dos arquivos',
  versionsOk
   ?'CSS e JavaScript RC5.64 carregados.'
   :'Há arquivos de outra versão em cache.'
 ));

 $('diag-checks').innerHTML=checks.join('');

 const failed=checks.filter(item=>item.includes('diagnostic-check fail')).length;
 if(failed){
  banner.className='notice danger';
  banner.innerHTML=`<strong>Diagnóstico com ${failed} alerta(s).</strong> Verifique os itens em vermelho abaixo.`;
 }else{
  banner.className='notice success';
  banner.innerHTML='<strong>Diagnóstico concluído.</strong> Horário oficial, versão e Service Worker estão corretos.';
 }
}

$('diag-refresh').onclick=refresh;
$('diag-sync-clock').onclick=async()=>{
 const button=$('diag-sync-clock');
 button.disabled=true;
 button.setAttribute('aria-busy','true');
 button.textContent='Sincronizando...';

 try{
  const localDate=new Date();
  const direct=await getServerTimeDirect();
  await window.PlenitudeClock.sync();
  const info=window.PlenitudeClock.info();

  showSyncResult({
   ok:info.source==='server',
   title:info.source==='server'
    ?'Sincronização concluída'
    :'Sincronização incompleta',
   serverDate:direct.serverDate,
   localDate,
   offsetMs:direct.offsetMs,
   latencyMs:direct.latencyMs,
   source:info.source
  });

  await refresh();
 }catch(error){
  console.error(error);

  showSyncResult({
   ok:false,
   title:'Falha na sincronização',
   message:error.message||'Não foi possível consultar o horário oficial.'
  });

  await refresh();
 }finally{
  button.disabled=false;
  button.removeAttribute('aria-busy');
  button.textContent='Sincronizar agora';
 }
};

$('diag-update-sw').onclick=async()=>{
 try{
  const registration=await navigator.serviceWorker.getRegistration();
  if(!registration)throw new Error('Service Worker não registrado.');
  await registration.update();
  toast('Verificação de atualização concluída.');
  await refresh();
 }catch(error){
  toast(error.message,'warn');
 }
};

(async()=>{
 await window.PlenitudeAuth.requireAccess({roles:['administrador']});
 await refresh();
 setInterval(()=>{
  const now=new Date();
  $('diag-local-time').textContent=formatTime(now);
  $('diag-local-date').textContent=formatDate(now);
 },1000);
})().catch(error=>{
 console.error(error);
 toast(error.message,'warn');
});

})();