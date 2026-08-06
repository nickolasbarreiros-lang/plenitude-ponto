(function(){
'use strict';

const EXPECTED_BUILD='RC6.0';
const reloadKey='plenitude-version-reload';
let reloading=false;

function buildFromPage(){
 return document.querySelector('meta[name="plenitude-build"]')?.content||'desconhecida';
}

function showUpdateNotice(message='Atualizando o sistema com segurança...'){
 let notice=document.getElementById('system-update-notice');
 if(!notice){
  notice=document.createElement('div');
  notice.id='system-update-notice';
  notice.setAttribute('role','status');
  notice.innerHTML='<strong>Nova versão disponível</strong><span></span>';
  document.body.appendChild(notice);
 }
 const span=notice.querySelector('span');
 if(span)span.textContent=message;
}

async function clearLegacyCaches(){
 if(!('caches' in window))return;
 const keys=await caches.keys();
 await Promise.all(
  keys
   .filter(key=>key.startsWith('plenitude-ponto-')&&key!=='plenitude-ponto-rc6-0')
   .map(key=>caches.delete(key))
 );
}

async function forceLatestWorker(registration){
 await clearLegacyCaches();
 await registration?.update();
 if(registration?.waiting){
  showUpdateNotice();
  registration.waiting.postMessage({type:'SKIP_WAITING'});
 }
}

if('serviceWorker' in navigator){
 navigator.serviceWorker.addEventListener('controllerchange',()=>{
  if(reloading)return;
  reloading=true;
  showUpdateNotice();
  const previous=Number(sessionStorage.getItem(reloadKey)||0);
  const now=Date.now();
  if(now-previous<15000)return;
  sessionStorage.setItem(reloadKey,String(now));
  setTimeout(()=>location.reload(),900);
 });

 window.addEventListener('load',async()=>{
  console.info(`[Plenitude Ponto ${EXPECTED_BUILD}] Página ${buildFromPage()}`);
  try{
   const registration=await navigator.serviceWorker.getRegistration();
   await forceLatestWorker(registration);
   if(registration)setInterval(()=>registration.update().catch(()=>{}),5*60*1000);
  }catch(error){
   console.info('Verificação de atualização indisponível.',error);
  }
 });
}
})();
