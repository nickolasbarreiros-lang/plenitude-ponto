(function(){'use strict';
 const client=window.PlenitudeAuth.client;
 function stored(){try{return JSON.parse(sessionStorage.getItem('plenitude-employee-session')||'null')}catch{return null}}
 const sess=stored();
 if(!sess){ window.PlenitudeAuth.getSession().then(s=>s?initPonto():location.replace('index.html')); return; }
 const token=sess.token;let employee=null;let punchInFlight=false;let punchCooldownUntil=0;let punchCooldownTimer=null;
 const dateKey=d=>{const y=d.getFullYear(),m=String(d.getMonth()+1).padStart(2,'0'),day=String(d.getDate()).padStart(2,'0');return `${y}-${m}-${day}`};
 const label=t=>({entrada:'Entrada',inicio_intervalo:'Início do almoço',fim_intervalo:'Retorno do almoço',saida:'Saída'})[t]||'Marcação';
 const fmt=v=>new Date(v).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
 async function rpc(name,args={}){const {data,error}=await client.rpc(name,args);if(error)throw error;return data}
 function clock(){const d=new Date();document.getElementById('clock-date').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(d);document.getElementById('clock-time').textContent=d.toLocaleTimeString('pt-BR')}
 function successSound(){try{const C=window.AudioContext||window.webkitAudioContext,ctx=new C();[523.25,659.25,783.99].forEach((f,i)=>{const o=ctx.createOscillator(),g=ctx.createGain();o.frequency.value=f;o.type='sine';g.gain.setValueAtTime(.0001,ctx.currentTime+i*.11);g.gain.exponentialRampToValueAtTime(.16,ctx.currentTime+i*.11+.02);g.gain.exponentialRampToValueAtTime(.0001,ctx.currentTime+i*.11+.18);o.connect(g);g.connect(ctx.destination);o.start(ctx.currentTime+i*.11);o.stop(ctx.currentTime+i*.11+.2)});setTimeout(()=>ctx.close(),800)}catch{}}
 function showSuccess(message){const b=document.getElementById('success-banner');b.querySelector('strong').textContent=message;b.hidden=false;b.classList.remove('show');void b.offsetWidth;b.classList.add('show');successSound();setTimeout(()=>{b.classList.remove('show');setTimeout(()=>b.hidden=true,250)},3200)}
 async function load(){
  const now=new Date(),today=dateKey(now),monday=new Date(now);monday.setDate(now.getDate()-((now.getDay()+6)%7));const firstMonth=new Date(now.getFullYear(),now.getMonth(),1);
  const isHomologation=String(employee?.matricula||'').replace(/^0+/,'')==='999';
  const weekStart=isHomologation?today:dateKey(monday);
  const monthStart=isHomologation?today:dateKey(firstMonth);
  const [data,todayBank,weekBank,monthBank]=await Promise.all([
    rpc('marcacoes_funcionario_token',{p_token:token,p_inicio:today,p_fim:today}),
    rpc('banco_horas_funcionario_token',{p_token:token,p_inicio:today,p_fim:today}),
    rpc('banco_horas_funcionario_token',{p_token:token,p_inicio:weekStart,p_fim:today}),
    rpc('banco_horas_funcionario_token',{p_token:token,p_inicio:monthStart,p_fim:today})
  ]),marks=data||[];
  document.getElementById('lista-pontos').innerHTML=marks.length?marks.map(m=>`<div class="punch-item"><span>${label(m.tipo)}</span><strong>${fmt(m.registrado_em)}</strong></div>`).join(''):'<div class="mini-empty">Nenhuma marcação feita hoje.</div>';
  const labels=['Entrada','Almoço','Retorno','Saída'];
  const actionLabels=['Registrar entrada','Registrar saída para almoço','Registrar retorno do almoço','Registrar saída final'];
  const nextLabel=marks.length<4?labels[marks.length]:null;
  document.getElementById('proxima').textContent=nextLabel?`Próxima marcação: ${nextLabel}`:'Jornada de hoje concluída';
  const punchButton=document.getElementById('registrar');
  punchButton.innerHTML=marks.length<4?`<span>◷</span> ${actionLabels[marks.length]}`:'<span>✓</span> Jornada concluída';
  punchButton.setAttribute('aria-label',marks.length<4?actionLabels[marks.length]:'Jornada concluída');
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
  punchButton.disabled=marks.length>=4 || punchInFlight || Date.now()<punchCooldownUntil;
  if(Date.now()>=punchCooldownUntil)punchButton.classList.remove('cooldown');
  document.body.classList.toggle('homologation-employee',isHomologation);
  const note=document.getElementById('homologation-note');if(note)note.hidden=!isHomologation;
 }
 async function init(){document.body.classList.add('employee-mode','kiosk-point-mode');document.getElementById('ponto-funcionario-select').hidden=true;clock();setInterval(clock,1000);
  try{const d=await rpc('dados_funcionario_token',{p_token:token});employee=Array.isArray(d)?d[0]:d;if(!employee)throw new Error('Sessão inválida.');
   document.getElementById('clock-employee').textContent=employee.nome;document.getElementById('clock-status').textContent='Pronto para registrar';document.getElementById('clock-avatar').innerHTML=`<span>${employee.nome.split(/\s+/).slice(0,2).map(x=>x[0]).join('').toUpperCase()}</span>`;
   const self=document.getElementById('employee-self-service');self.hidden=false;document.getElementById('self-profile-name').textContent=employee.nome;document.getElementById('self-profile-role').textContent=employee.cargo||'Funcionário';document.getElementById('self-profile-code').textContent=employee.matricula;
   document.getElementById('change-pin-panel').hidden=!employee.exigir_troca_pin;
   const results=await Promise.allSettled([load(),loadAdjustments(),loadMovements()]);
   results.forEach((result,index)=>{if(result.status==='rejected'){console.warn(['Resumo de ponto indisponível','Ajustes indisponíveis','Movimentações indisponíveis'][index],result.reason)}});
  }catch(e){
   console.error('Falha ao iniciar área do funcionário',e);
   toast(e.message||'Não foi possível abrir a área do funcionário.','warn');
   if(/sessão|token|inválid/i.test(String(e.message||''))){sessionStorage.removeItem('plenitude-employee-session');setTimeout(()=>location.replace('index.html'),1200)}
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
    toast(e.message,'warn');
    b.disabled=false;
    b.innerHTML=previous;
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
  const today=dateKey(new Date()),rows=await rpc('listar_minhas_movimentacoes',{p_token:token,p_inicio:today,p_fim:today});
  const open=(rows||[]).find(r=>r.status==='aberta');
  document.getElementById('movement-state').textContent=open?'Fora da loja':'Dentro da loja';
  document.getElementById('movement-state').className=`badge ${open?'warn':''}`;
  const exitTrigger=document.getElementById('temporary-exit');
  const exitForm=document.getElementById('movement-exit-form');
  const exitReason=document.getElementById('movement-reason');
  const returnButton=document.getElementById('temporary-return');

  exitTrigger.hidden=!!open;
  returnButton.hidden=!open;

  if(open){
   exitForm.hidden=true;
   exitReason.disabled=true;
   exitReason.value='';
   exitTrigger.setAttribute('aria-expanded','false');
  }else if(exitForm.hidden){
   exitReason.disabled=true;
  }
  const box=document.getElementById('my-movements');
  box.innerHTML=(rows||[]).length?(rows||[]).map(r=>`<div class="movement-item"><div><strong>${r.status==='aberta'?'Saída temporária em andamento':'Saída temporária'}</strong><small>${fmt(r.inicio_em)}${r.fim_em?` → ${fmt(r.fim_em)}`:' → aguardando retorno'}${r.motivo_informado?` · ${r.motivo_informado}`:''}</small></div><span class="request-status ${r.aprovado?'aprovada':'pendente'}">${r.aprovado?(r.classificacao||'analisada'):'aguardando análise'}</span></div>`).join(''):'<div class="mini-empty">Nenhuma saída temporária hoje.</div>';
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

 adjustmentToggle.onclick=()=>setAdjustmentEditing(adjustmentForm.hidden);
 adjustmentForm.onsubmit=async e=>{
  e.preventDefault();
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
   await loadAdjustments();
  }catch(err){
   toast(err.message,'warn');
  }finally{
   b.disabled=false;
   b.textContent='Enviar solicitação';
  }
 };

 document.getElementById('alterar-meu-pin').onclick=async()=>{const a=document.getElementById('pin-atual').value,n=document.getElementById('pin-novo').value,c=document.getElementById('pin-confirmar').value;if(!/^\d{4}$/.test(n)||n!==c)return toast('O novo PIN deve ter 4 números e coincidir com a confirmação.','warn');try{await rpc('alterar_proprio_pin',{p_token:token,p_pin_atual:a,p_novo_pin:n});toast('PIN alterado com sucesso.');document.getElementById('change-pin-panel').hidden=true}catch(e){toast(e.message,'warn')}};
 init();
})();
