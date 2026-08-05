(function(){
'use strict';

if(!('serviceWorker' in navigator))return;

let reloading=false;
const reloadKey='plenitude-version-reload';

function showUpdateNotice(){
 if(document.getElementById('system-update-notice'))return;

 const notice=document.createElement('div');
 notice.id='system-update-notice';
 notice.setAttribute('role','status');
 notice.innerHTML=`
  <strong>Nova versão disponível</strong>
  <span>Atualizando o sistema com segurança...</span>
 `;
 document.body.appendChild(notice);
}

navigator.serviceWorker.addEventListener('controllerchange',()=>{
 if(reloading)return;
 reloading=true;
 showUpdateNotice();

 const previous=sessionStorage.getItem(reloadKey);
 const now=Date.now();

 if(previous&&now-Number(previous)<15000)return;

 sessionStorage.setItem(reloadKey,String(now));
 setTimeout(()=>location.reload(),900);
});

window.addEventListener('load',async()=>{
 try{
  const registration=await navigator.serviceWorker.getRegistration();
  if(!registration)return;

  await registration.update();

  if(registration.waiting){
   showUpdateNotice();
   registration.waiting.postMessage({type:'SKIP_WAITING'});
  }

  setInterval(()=>registration.update().catch(()=>{}),5*60*1000);
 }catch(error){
  console.info('Verificação de atualização indisponível.',error);
 }
});
})();