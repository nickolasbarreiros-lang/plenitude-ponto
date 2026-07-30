(function(){'use strict';
 const form=document.getElementById('employee-login-form');
 if(!form)return;
 const choice=document.getElementById('access-choice');
 const empPanel=document.getElementById('employee-access-panel');
 const adminPanel=document.getElementById('admin-access-panel');
 const security=document.querySelector('.access-security');
 const pin=document.getElementById('login-pin');
 const matricula=document.getElementById('login-matricula');
 function openPanel(type){
   choice.hidden=true;security.hidden=true;
   empPanel.hidden=type!=='employee';adminPanel.hidden=type!=='admin';
   setTimeout(()=>type==='employee'?matricula.focus():document.getElementById('email')?.focus(),50);
 }
 function home(){choice.hidden=false;security.hidden=false;empPanel.hidden=true;adminPanel.hidden=true}
 document.getElementById('choose-employee').onclick=()=>openPanel('employee');
 document.getElementById('choose-admin').onclick=()=>openPanel('admin');
 document.querySelectorAll('.access-back').forEach(b=>b.onclick=home);
 const mostrarPin=document.getElementById('mostrar-pin');
 if(mostrarPin&&pin){
   mostrarPin.addEventListener('click',()=>{
     const mostrar=pin.type==='password';
     pin.type=mostrar?'text':'password';
     mostrarPin.textContent=mostrar?'Ocultar':'Mostrar';
     mostrarPin.setAttribute('aria-label',mostrar?'Ocultar PIN':'Mostrar PIN');
     mostrarPin.setAttribute('aria-pressed',String(mostrar));
     pin.focus({preventScroll:true});
   });
 }
 document.getElementById('pin-keypad').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;if(b.dataset.key&&pin.value.length<4)pin.value+=b.dataset.key;if(b.dataset.action==='clear')pin.value='';if(b.dataset.action==='backspace')pin.value=pin.value.slice(0,-1);pin.dispatchEvent(new Event('input'));});
 pin.addEventListener('input',()=>{pin.value=pin.value.replace(/\D/g,'').slice(0,4)});
 matricula.addEventListener('input',()=>{matricula.value=matricula.value.replace(/\D/g,'').slice(0,10)});
 form.onsubmit=async e=>{e.preventDefault();const feedback=document.getElementById('employee-login-feedback'),button=form.querySelector('button[type=submit]');button.disabled=true;feedback.textContent='Verificando acesso...';feedback.className='login-feedback loading';try{
   if(!matricula.value.trim())throw new Error('Digite a matrícula.');
   if(!/^\d{4}$/.test(pin.value))throw new Error('Digite um PIN com exatamente 4 números.');
   const deviceToken=localStorage.getItem('plenitude-device-token')||'';
   if(!deviceToken)throw new Error('Este computador não está autorizado. Solicite ao administrador.');
   const {data,error}=await window.PlenitudeAuth.client.rpc('login_funcionario_pin_dispositivo',{p_matricula:matricula.value.trim(),p_pin:pin.value,p_dispositivo_token:deviceToken,p_user_agent:navigator.userAgent});if(error)throw error;
   const row=Array.isArray(data)?data[0]:data;if(!row?.token)throw new Error('Não foi possível iniciar a sessão.');
   sessionStorage.setItem('plenitude-employee-session',JSON.stringify(row));location.replace('ponto.html');
 }catch(err){feedback.textContent=err.message||'Matrícula ou PIN incorretos.';feedback.className='login-feedback error';pin.value=''}finally{button.disabled=false}}
})();
