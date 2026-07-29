(function(){'use strict';
 const client=window.PlenitudeAuth.client;
 function stored(){try{return JSON.parse(sessionStorage.getItem('plenitude-employee-session')||'null')}catch{return null}}
 const sess=stored();
 if(!sess){ window.PlenitudeAuth.getSession().then(s=>s?initPonto():location.replace('index.html')); return; }
 const token=sess.token;let employee=null;
 const dateKey=d=>{const y=d.getFullYear(),m=String(d.getMonth()+1).padStart(2,'0'),day=String(d.getDate()).padStart(2,'0');return `${y}-${m}-${day}`};
 const label=t=>({entrada:'Entrada',inicio_intervalo:'Início do almoço',fim_intervalo:'Retorno do almoço',saida:'Saída'})[t]||'Marcação';
 const fmt=v=>new Date(v).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
 async function rpc(name,args={}){const {data,error}=await client.rpc(name,args);if(error)throw error;return data}
 function clock(){const d=new Date();document.getElementById('clock-date').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(d);document.getElementById('clock-time').textContent=d.toLocaleTimeString('pt-BR')}
 async function load(){
  const today=dateKey(new Date()),data=await rpc('marcacoes_funcionario_token',{p_token:token,p_inicio:today,p_fim:today}),marks=data||[];
  document.getElementById('lista-pontos').innerHTML=marks.length?marks.map(m=>`<div class="punch-item"><span>${label(m.tipo)}</span><strong>${fmt(m.registrado_em)}</strong></div>`).join(''):'<div class="mini-empty">Nenhuma marcação feita hoje.</div>';
  const labels=['Entrada','Almoço','Retorno','Saída'];document.getElementById('proxima').textContent=marks.length<4?`Próxima marcação: ${labels[marks.length]}`:'Jornada de hoje concluída';
  document.getElementById('punch-progress').innerHTML=labels.map((_,i)=>`<span class="progress-step ${i<marks.length?'done':''}"></span>`).join('');
  document.getElementById('punch-steps').innerHTML=labels.map((n,i)=>`<div class="punch-step ${i<marks.length?'done':''} ${i===marks.length?'current':''}"><span class="step-icon">${i<marks.length?'✓':i+1}</span><strong>${n}</strong><small>${marks[i]?fmt(marks[i].registrado_em):'Aguardando'}</small></div>`).join('');
  document.getElementById('registrar').disabled=marks.length>=4;
 }
 async function init(){document.body.classList.add('employee-mode');document.querySelector('.back-link')?.remove();document.getElementById('ponto-funcionario-select').hidden=true;clock();setInterval(clock,1000);
  try{const d=await rpc('dados_funcionario_token',{p_token:token});employee=Array.isArray(d)?d[0]:d;if(!employee)throw new Error('Sessão inválida.');
   document.getElementById('clock-employee').textContent=employee.nome;document.getElementById('clock-status').textContent='Ativo';document.getElementById('clock-avatar').innerHTML=`<span>${employee.nome.split(/\s+/).slice(0,2).map(x=>x[0]).join('').toUpperCase()}</span>`;
   const self=document.getElementById('employee-self-service');self.hidden=false;document.getElementById('self-profile-name').textContent=employee.nome;document.getElementById('self-profile-role').textContent=employee.cargo||'Funcionário';document.getElementById('self-profile-code').textContent=employee.matricula;
   document.getElementById('change-pin-panel').hidden=!employee.exigir_troca_pin;await load();
  }catch(e){alert(e.message);sessionStorage.removeItem('plenitude-employee-session');location.replace('index.html')}
 }
 document.getElementById('registrar').onclick=async()=>{const b=document.getElementById('registrar');b.disabled=true;try{const data=await rpc('registrar_ponto_com_pin',{p_token:token});const m=Array.isArray(data)?data[0]:data;toast(`${label(m.tipo)} registrada às ${fmt(m.registrado_em)}.`);await load()}catch(e){toast(e.message,'warn');b.disabled=false}};
 document.getElementById('sair').onclick=async()=>{try{await rpc('encerrar_sessao_funcionario',{p_token:token})}catch{}sessionStorage.removeItem('plenitude-employee-session');location.replace('index.html')};
 document.getElementById('abrir-troca-pin').onclick=()=>document.getElementById('change-pin-panel').hidden=false;
 document.getElementById('alterar-meu-pin').onclick=async()=>{const a=document.getElementById('pin-atual').value,n=document.getElementById('pin-novo').value,c=document.getElementById('pin-confirmar').value;if(!/^\d{4}$/.test(n)||n!==c)return toast('O novo PIN deve ter 4 números e coincidir com a confirmação.','warn');try{await rpc('alterar_proprio_pin',{p_token:token,p_pin_atual:a,p_novo_pin:n});toast('PIN alterado com sucesso.');document.getElementById('change-pin-panel').hidden=true}catch(e){toast(e.message,'warn')}};
 init();
})();
