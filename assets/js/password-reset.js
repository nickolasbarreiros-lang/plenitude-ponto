(function(){
  'use strict';
  const form=document.getElementById('password-reset-form');
  const password=document.getElementById('new-password');
  const confirm=document.getElementById('confirm-password');
  const feedback=document.getElementById('password-reset-feedback');
  const submit=form.querySelector('button[type="submit"]');
  const show=document.getElementById('show-new-password');
  const strength=document.getElementById('password-strength');
  function setFeedback(message='',type=''){feedback.textContent=message;feedback.className=`login-feedback${type?` ${type}`:''}`}
  function score(value){let n=0;if(value.length>=8)n++;if(/[A-Z]/.test(value)&&/[a-z]/.test(value))n++;if(/\d/.test(value))n++;if(/[^A-Za-z0-9]/.test(value))n++;return n}
  password.addEventListener('input',()=>{const n=score(password.value);strength.dataset.score=String(n);strength.querySelector('span').textContent=['Senha muito fraca.','Senha fraca.','Senha razoável.','Senha boa.','Senha forte.'][n]});
  show.addEventListener('click',()=>{const visible=password.type==='password';password.type=visible?'text':'password';confirm.type=visible?'text':'password';show.textContent=visible?'Ocultar':'Mostrar'});
  form.addEventListener('submit',async event=>{event.preventDefault();setFeedback();if(password.value.length<8){setFeedback('A senha precisa ter pelo menos 8 caracteres.','error');return}if(password.value!==confirm.value){setFeedback('As senhas não coincidem.','error');confirm.focus();return}submit.disabled=true;submit.textContent='Salvando...';try{await window.PlenitudeAuth.updatePassword(password.value);setFeedback('Senha atualizada com sucesso. Você será direcionado ao painel.','success');setTimeout(()=>location.replace('admin.html'),1200)}catch(error){setFeedback(window.PlenitudeAuth.friendlyAuthError(error),'error')}finally{submit.disabled=false;submit.textContent='Salvar nova senha'}});
})();
