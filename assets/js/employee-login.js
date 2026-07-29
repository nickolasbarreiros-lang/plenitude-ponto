(function(){'use strict';
 const form=document.getElementById('employee-login-form'),adminForm=document.getElementById('login-form');
 const tabEmp=document.getElementById('tab-funcionario'),tabAdmin=document.getElementById('tab-admin');
 if(!form)return;
 function tab(employee){form.hidden=!employee;adminForm.hidden=employee;tabEmp.classList.toggle('active',employee);tabAdmin.classList.toggle('active',!employee)}
 tabEmp.onclick=()=>tab(true);tabAdmin.onclick=()=>tab(false);
 const pin=document.getElementById('login-pin');document.getElementById('mostrar-pin').onclick=()=>{const show=pin.type==='password';pin.type=show?'text':'password';document.getElementById('mostrar-pin').textContent=show?'Ocultar':'Mostrar'};
 form.onsubmit=async e=>{e.preventDefault();const feedback=document.getElementById('employee-login-feedback'),button=form.querySelector('button[type=submit]');button.disabled=true;feedback.textContent='Verificando...';feedback.className='login-feedback loading';try{
   const matricula=document.getElementById('login-matricula').value.trim();
   if(!/^\d{4}$/.test(pin.value))throw new Error('Digite um PIN com exatamente 4 números.');
   const {data,error}=await window.PlenitudeAuth.client.rpc('login_funcionario_pin',{p_matricula:matricula,p_pin:pin.value});if(error)throw error;
   const row=Array.isArray(data)?data[0]:data;if(!row?.token)throw new Error('Não foi possível iniciar a sessão.');
   sessionStorage.setItem('plenitude-employee-session',JSON.stringify(row));location.replace('ponto.html');
 }catch(err){feedback.textContent=err.message||'Matrícula ou PIN incorretos.';feedback.className='login-feedback error';pin.select()}finally{button.disabled=false}}
})();
