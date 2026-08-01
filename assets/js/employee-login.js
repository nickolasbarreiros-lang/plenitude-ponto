(function(){
'use strict';

const form=document.getElementById('employee-login-form');
if(!form)return;

const choice=document.getElementById('access-choice');
const empPanel=document.getElementById('employee-access-panel');
const adminPanel=document.getElementById('admin-access-panel');
const security=document.querySelector('.access-security');
const pin=document.getElementById('login-pin');
const matricula=document.getElementById('login-matricula');
const feedback=document.getElementById('employee-login-feedback');

const OFFLINE_LOGIN_KEY='plenitude-offline-login-v1';

function openPanel(type){
 choice.hidden=true;
 security.hidden=true;
 empPanel.hidden=type!=='employee';
 adminPanel.hidden=type!=='admin';
 setTimeout(
  ()=>type==='employee'
   ?matricula.focus()
   :document.getElementById('email')?.focus(),
  50
 );
}

function home(){
 choice.hidden=false;
 security.hidden=false;
 empPanel.hidden=true;
 adminPanel.hidden=true;
}

function isNetworkFailure(error){
 const message=String(error?.message||error||'');
 return !navigator.onLine||
  /Failed to fetch|NetworkError|Load failed|fetch|timeout|connection|ERR_INTERNET|ERR_NETWORK/i.test(message);
}

function getOfflineLogins(){
 try{
  const parsed=JSON.parse(localStorage.getItem(OFFLINE_LOGIN_KEY)||'{}');
  return parsed&&typeof parsed==='object'?parsed:{};
 }catch{
  return {};
 }
}

function saveOfflineLogins(value){
 localStorage.setItem(OFFLINE_LOGIN_KEY,JSON.stringify(value));
}

async function sha256(text){
 if(!crypto.subtle){
  throw new Error('Este navegador não oferece criptografia necessária para o login offline.');
 }

 const encoded=new TextEncoder().encode(text);
 const digest=await crypto.subtle.digest('SHA-256',encoded);

 return Array.from(
  new Uint8Array(digest),
  value=>value.toString(16).padStart(2,'0')
 ).join('');
}

function randomSalt(){
 const bytes=new Uint8Array(16);
 crypto.getRandomValues(bytes);
 return Array.from(
  bytes,
  value=>value.toString(16).padStart(2,'0')
 ).join('');
}

async function buildVerifier({registration,pinValue,deviceToken,salt}){
 return sha256(
  [
   'PLENITUDE_OFFLINE_LOGIN_V1',
   registration,
   pinValue,
   deviceToken,
   salt
  ].join('|')
 );
}

async function cacheSuccessfulLogin(registration,pinValue,deviceToken,sessionRow){
 const salt=randomSalt();
 const verifier=await buildVerifier({
  registration,
  pinValue,
  deviceToken,
  salt
 });

 const logins=getOfflineLogins();

 logins[registration]={
  registration,
  salt,
  verifier,
  session:sessionRow,
  employeeId:sessionRow.funcionario_id||sessionRow.id||null,
  employeeName:sessionRow.nome||sessionRow.funcionario_nome||null,
  cachedAt:new Date().toISOString(),
  deviceTokenSuffix:deviceToken.slice(-12)
 };

 saveOfflineLogins(logins);
}

async function offlineLogin(registration,pinValue,deviceToken){
 const logins=getOfflineLogins();
 const cached=logins[registration];

 if(!cached){
  throw new Error(
   'Este funcionário ainda não está preparado para acesso offline neste computador. Faça um login com internet primeiro.'
  );
 }

 if(cached.deviceTokenSuffix!==deviceToken.slice(-12)){
  throw new Error(
   'A autorização deste computador mudou. Faça novamente um login com internet para preparar o acesso offline.'
  );
 }

 const verifier=await buildVerifier({
  registration,
  pinValue,
  deviceToken,
  salt:cached.salt
 });

 if(verifier!==cached.verifier){
  throw new Error('Matrícula ou PIN incorretos.');
 }

 if(!cached.session?.token){
  throw new Error('A sessão offline armazenada está incompleta. Faça um login com internet novamente.');
 }

 sessionStorage.setItem(
  'plenitude-employee-session',
  JSON.stringify({...cached.session,offline_login:true})
 );

 localStorage.setItem(
  'plenitude-offline-employee-session',
  JSON.stringify({...cached.session,offline_login:true})
 );

 return cached.session;
}

function setContingencyLoginMessage(){
 const warning=document.getElementById('employee-device-warning');

 if(!navigator.onLine){
  warning.classList.add('offline-login-warning');
  warning.innerHTML=
   '<strong>⚠ Contingência offline ativa</strong><span>O acesso será validado com os dados protegidos armazenados neste computador.</span>';
 }else{
  warning.classList.remove('offline-login-warning');
  warning.textContent='O registro de ponto exige um computador autorizado pelo administrador.';
 }
}

document.getElementById('choose-employee').onclick=()=>openPanel('employee');
document.getElementById('choose-admin').onclick=()=>openPanel('admin');
document.querySelectorAll('.access-back').forEach(button=>button.onclick=home);

document.getElementById('mostrar-pin').onclick=()=>{
 const show=pin.type==='password';
 pin.type=show?'text':'password';
 document.getElementById('mostrar-pin').textContent=show?'Ocultar':'Mostrar';
};

document.getElementById('pin-keypad').addEventListener('click',event=>{
 const button=event.target.closest('button');
 if(!button)return;

 if(button.dataset.key&&pin.value.length<4)pin.value+=button.dataset.key;
 if(button.dataset.action==='clear')pin.value='';
 if(button.dataset.action==='backspace')pin.value=pin.value.slice(0,-1);

 pin.dispatchEvent(new Event('input'));
});

pin.addEventListener('input',()=>{
 pin.value=pin.value.replace(/\D/g,'').slice(0,4);
});

matricula.addEventListener('input',()=>{
 matricula.value=matricula.value.replace(/\D/g,'').slice(0,10);
});

window.addEventListener('online',setContingencyLoginMessage);
window.addEventListener('offline',setContingencyLoginMessage);
setContingencyLoginMessage();

(function resumeOnlineReauthentication(){
 const raw=localStorage.getItem('plenitude-online-reauth-required');
 if(!raw)return;

 let state={};

 try{
  state=JSON.parse(raw)||{};
 }catch{}

 openPanel('employee');

 if(state.registration){
  matricula.value=String(state.registration);
  pin.focus();
 }else{
  matricula.focus();
 }

 const pending=Number(state.pendingCount||0);

 feedback.textContent=pending>0
  ?`Conexão restabelecida. Digite o PIN para sincronizar ${pending} registro(s) offline.`
  :'Sua sessão expirou. Entre novamente para continuar.';

 feedback.className='login-feedback warning';
})();

form.onsubmit=async event=>{
 event.preventDefault();

 const button=form.querySelector('button[type=submit]');
 const registration=matricula.value.trim();
 const pinValue=pin.value;
 const deviceToken=localStorage.getItem('plenitude-device-token')||'';

 button.disabled=true;
 feedback.textContent=navigator.onLine
  ?'Verificando acesso...'
  :'Validando acesso de contingência...';
 feedback.className='login-feedback loading';

 try{
  if(!registration)throw new Error('Digite a matrícula.');
  if(!/^\d{4}$/.test(pinValue)){
   throw new Error('Digite um PIN com exatamente 4 números.');
  }
  if(!deviceToken){
   throw new Error('Este computador não está autorizado. Solicite ao administrador.');
  }

  let row;

  try{
   const {data,error}=await window.PlenitudeAuth.client.rpc(
    'login_funcionario_pin_dispositivo',
    {
     p_matricula:registration,
     p_pin:pinValue,
     p_dispositivo_token:deviceToken,
     p_user_agent:navigator.userAgent
    }
   );

   if(error)throw error;

   row=Array.isArray(data)?data[0]:data;

   if(!row?.token){
    throw new Error('Não foi possível iniciar a sessão.');
   }

   await cacheSuccessfulLogin(registration,pinValue,deviceToken,row);

   sessionStorage.setItem(
    'plenitude-employee-session',
    JSON.stringify(row)
   );

   localStorage.setItem(
    'plenitude-offline-employee-session',
    JSON.stringify(row)
   );

   localStorage.removeItem('plenitude-online-reauth-required');
  }catch(error){
   if(!isNetworkFailure(error))throw error;

   row=await offlineLogin(
    registration,
    pinValue,
    deviceToken
   );

   feedback.textContent=
    'Acesso validado em contingência. Abrindo o ponto offline...';
   feedback.className='login-feedback warning';
  }

  location.replace('ponto.html');
 }catch(error){
  feedback.textContent=error.message||'Matrícula ou PIN incorretos.';
  feedback.className='login-feedback error';
  pin.value='';
 }finally{
  button.disabled=false;
 }
};
})();