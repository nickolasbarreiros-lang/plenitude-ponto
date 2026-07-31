(async function(){'use strict';
 const C={
  consulta_medica:'Consulta médica',
  atestado:'Atestado/declaração',
  servico_externo:'Serviço externo',
  curso:'Curso/treinamento',
  banco:'Banco/atividade pessoal',
  particular:'Saída particular',
  saida_autorizada:'Saída autorizada',
  compensacao:'Compensação',
  hora_extra_autorizada:'Hora extra autorizada',
  home_office:'Home office',
  outro:'Outro'
 };
 const EXCEPTION_C={
  atestado:'Atestado ou declaração',
  curso:'Curso ou treinamento',
  home_office:'Home office autorizado',
  compensacao:'Compensação de jornada',
  hora_extra_autorizada:'Hora extra autorizada',
  outro:'Outra ocorrência administrativa'
 };
 const E={pendente:'Pendente',descontar:'Descontar',abonar:'Abonar',trabalhado:'Conta como trabalho',credito:'Crédito autorizado'};
 const fmt=v=>v?new Date(v).toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'}):'Aguardando retorno';
 const context=await initCommon(['administrador']);if(!context)return;
 const employees=await PlenitudeDB.employees();
 const opts=employees.map(f=>`<option value="${f.id}">${f.nome} — ${f.matricula||'sem matrícula'}</option>`).join('');
 document.getElementById('mov-funcionario').innerHTML=opts;document.getElementById('mov-filter-employee').insertAdjacentHTML('beforeend',opts);
 document.getElementById('mov-classificacao').innerHTML=Object.entries(EXCEPTION_C).map(([v,l])=>`<option value="${v}">${l}</option>`).join('');
 const now=new Date(),start=new Date(now.getFullYear(),now.getMonth(),1);const key=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
 document.getElementById('mov-filter-start').value=key(start);document.getElementById('mov-filter-end').value=key(now);
 const dt=d=>{const z=new Date(d.getTime()-d.getTimezoneOffset()*60000);return z.toISOString().slice(0,16)};document.getElementById('mov-inicio').value=dt(now);document.getElementById('mov-fim').value=dt(new Date(now.getTime()+60*60000));
 const exceptionForm=document.getElementById('movement-create-form');
 const toggleException=document.getElementById('toggle-exception-form');
 const cancelException=document.getElementById('cancel-exception-form');

 function setExceptionFormOpen(open){
  exceptionForm.hidden=!open;
  toggleException.setAttribute('aria-expanded',String(open));
  toggleException.textContent=open?'Fechar lançamento':'Abrir lançamento excepcional';

  if(open){
   requestAnimationFrame(()=>document.getElementById('mov-funcionario').focus());
  }else{
   exceptionForm.reset();
   document.getElementById('mov-inicio').value=dt(new Date());
   document.getElementById('mov-fim').value=dt(new Date(Date.now()+60*60000));
  }
 }

 toggleException.onclick=()=>setExceptionFormOpen(exceptionForm.hidden);
 cancelException.onclick=()=>setExceptionFormOpen(false);
 function localInputValue(value){
  const d=new Date(value);
  const local=new Date(d.getTime()-d.getTimezoneOffset()*60000);
  return local.toISOString().slice(0,16);
 }

 function suggestedReturn(r){
  const start=new Date(r.inicio_em);
  const suggested=new Date(start.getTime()+60*60000);
  const now=new Date();
  return localInputValue(suggested>now?now:suggested);
 }

 function movementSummary(r){
  const start=new Date(r.inicio_em);
  const end=r.fim_em?new Date(r.fim_em):null;
  const date=start.toLocaleDateString('pt-BR');
  const period=end
   ?`${start.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}–${end.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}`
   :`${start.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}–aguardando retorno`;

  return {date,period};
 }

 function localInputValue(value){
  const d=new Date(value);
  const local=new Date(d.getTime()-d.getTimezoneOffset()*60000);
  return local.toISOString().slice(0,16);
 }

 function suggestedReturn(r){
  const start=new Date(r.inicio_em);
  const suggested=new Date(start.getTime()+60*60000);
  const now=new Date();
  return localInputValue(suggested>now?now:suggested);
 }

 function editor(r){
  const isOpen=r.status==='aberta';
  const isArchived=r.status==='cancelada';
  const isAnalyzed=!isOpen&&!isArchived&&r.aprovado;
  const summary=movementSummary(r);
  const classification=C[r.classificacao]||'Sem classificação';
  const effect=E[r.efeito_calculo]||'Sem efeito definido';

  if(isAnalyzed){
   return `<article class="movement-admin-card movement-card-collapsed" data-movement-id="${r.id}">
    <button class="movement-card-summary" type="button" data-expand-movement aria-expanded="false">
     <div class="movement-summary-main">
      <small>${r.funcionario_nome} · ${r.matricula||'sem matrícula'}</small>
      <strong>${summary.date}</strong>
      <span>${classification}</span>
     </div>
     <div class="movement-summary-meta">
      <span>${summary.period}</span>
      <span class="request-status aprovada">analisada</span>
      <i aria-hidden="true">⌄</i>
     </div>
    </button>

    <div class="movement-card-details" hidden>
     <div class="movement-card-head">
      <div>
       <small>${r.funcionario_nome} · ${r.matricula||'sem matrícula'}</small>
       <h3>${fmt(r.inicio_em)} → ${fmt(r.fim_em)}</h3>
       <p>${r.motivo_informado||'Sem motivo informado'}</p>
      </div>
      <span class="request-status aprovada">analisada</span>
     </div>

     <div class="movement-review-grid">
      <label>Classificação
       <select data-class>
        ${Object.entries(C).map(([v,l])=>`<option value="${v}" ${r.classificacao===v?'selected':''}>${l}</option>`).join('')}
       </select>
      </label>
      <label>Efeito
       <select data-effect>
        ${Object.entries(E).filter(([v])=>v!=='pendente').map(([v,l])=>`<option value="${v}" ${r.efeito_calculo===v?'selected':''}>${l}</option>`).join('')}
       </select>
      </label>
      <label class="wide">Observação
       <textarea data-note>${r.observacao_admin||''}</textarea>
      </label>
      <button class="btn primary" data-save="${r.id}">Salvar análise</button>
     </div>

     <div class="movement-details-footer">
      <span><b>Classificação:</b> ${classification}</span>
      <span><b>Efeito:</b> ${effect}</span>
     </div>
    </div>
   </article>`;
  }

  return `<article class="movement-admin-card" data-movement-id="${r.id}">
   <div class="movement-card-head">
    <div>
     <small>${r.funcionario_nome} · ${r.matricula||'sem matrícula'}</small>
     <h3>${fmt(r.inicio_em)} → ${fmt(r.fim_em)}</h3>
     <p>${r.motivo_informado||'Sem motivo informado'}</p>
    </div>
    <span class="request-status ${isOpen?'pendente':isArchived?'rejeitada':'pendente'}">
     ${isOpen?'aguardando retorno':isArchived?'arquivada':'aguardando análise'}
    </span>
   </div>

   ${isOpen?`
    <div class="movement-resolution">
     <div class="notice compact">
      O funcionário não registrou o retorno. Informe o horário correto ou arquive o lançamento se ele for indevido.
     </div>

     <div class="movement-resolution-grid">
      <label>
       Horário correto do retorno
       <input data-return-time type="datetime-local" value="${suggestedReturn(r)}" min="${localInputValue(r.inicio_em)}">
      </label>

      <label class="wide">
       Observação administrativa
       <textarea data-return-note maxlength="500" placeholder="Ex.: Funcionário confirmou retorno às 16:10."></textarea>
      </label>
     </div>

     <div class="movement-resolution-actions">
      <button class="btn primary" data-register-return="${r.id}">Registrar retorno manual</button>
      <button class="btn outline danger" data-archive="${r.id}">Arquivar ocorrência</button>
     </div>
    </div>`
    :isArchived
      ?`<div class="admin-response"><b>Arquivada:</b> ${r.observacao_admin||'Sem observação.'}</div>`
      :`<div class="movement-review-grid">
       <label>Classificação
        <select data-class>
         ${Object.entries(C).map(([v,l])=>`<option value="${v}" ${r.classificacao===v?'selected':''}>${l}</option>`).join('')}
        </select>
       </label>
       <label>Efeito
        <select data-effect>
         ${Object.entries(E).filter(([v])=>v!=='pendente').map(([v,l])=>`<option value="${v}" ${r.efeito_calculo===v?'selected':''}>${l}</option>`).join('')}
        </select>
       </label>
       <label class="wide">Observação
        <textarea data-note>${r.observacao_admin||''}</textarea>
       </label>
       <button class="btn primary" data-save="${r.id}">Salvar análise</button>
      </div>`}
  </article>`;
 }
 async function load(){
  const box=document.getElementById('movement-admin-list');
  box.innerHTML='<div class="mini-empty">Carregando...</div>';

  try{
   const rows=await PlenitudeDB.adminMovements(
    document.getElementById('mov-filter-start').value,
    document.getElementById('mov-filter-end').value,
    document.getElementById('mov-filter-employee').value||null,
    document.getElementById('mov-filter-pending').checked
   );

   document.getElementById('movement-pending-count').textContent=
    `${rows.filter(r=>r.status==='aberta'||r.efeito_calculo==='pendente').length} pendentes`;

   box.innerHTML=rows.map(editor).join('');
   document.getElementById('movement-admin-empty').hidden=rows.length>0;

   box.querySelectorAll('[data-expand-movement]').forEach(button=>{
    button.onclick=()=>{
     const card=button.closest('.movement-admin-card');
     const details=card.querySelector('.movement-card-details');
     const open=button.getAttribute('aria-expanded')==='true';

     button.setAttribute('aria-expanded',String(!open));
     details.hidden=open;
     card.classList.toggle('is-expanded',!open);
    };
   });

   box.querySelectorAll('[data-save]').forEach(button=>{
    button.onclick=async()=>{
     const card=button.closest('.movement-admin-card');
     button.disabled=true;
     try{
      await PlenitudeDB.analyzeMovement(
       button.dataset.save,
       card.querySelector('[data-class]').value,
       card.querySelector('[data-effect]').value,
       card.querySelector('[data-note]').value
      );
      toast('Movimentação analisada com sucesso.');
      await load();
     }catch(error){
      toast(errorText(error),'warn');
     }finally{
      button.disabled=false;
     }
    };
   });

   box.querySelectorAll('[data-register-return]').forEach(button=>{
    button.onclick=async()=>{
     const card=button.closest('.movement-admin-card');
     const timeInput=card.querySelector('[data-return-time]');
     const note=card.querySelector('[data-return-note]').value.trim();

     if(!timeInput.value){
      timeInput.focus();
      return toast('Informe o horário correto do retorno.','warn');
     }

     if(!confirm('Registrar manualmente este retorno? A ação ficará gravada na auditoria.'))return;

     card.querySelectorAll('button,input,textarea').forEach(el=>el.disabled=true);
     button.textContent='Registrando...';

     try{
      await PlenitudeDB.regularizeMovementReturn(
       button.dataset.registerReturn,
       new Date(timeInput.value).toISOString(),
       note
      );
      toast('Retorno regularizado. Agora classifique o efeito da movimentação.');
      await load();
     }catch(error){
      toast(errorText(error),'warn');
      card.querySelectorAll('button,input,textarea').forEach(el=>el.disabled=false);
      button.textContent='Registrar retorno manual';
     }
    };
   });

   box.querySelectorAll('[data-archive]').forEach(button=>{
    button.onclick=async()=>{
     const reason=prompt(
      'Informe por que esta ocorrência deve ser arquivada:',
      'Registro de teste ou lançamento indevido.'
     );
     if(reason===null)return;
     if(reason.trim().length<5)return toast('Informe um motivo para arquivar.','warn');

     if(!confirm('Arquivar esta ocorrência? Ela deixará de aparecer como pendência.'))return;

     button.disabled=true;
     try{
      await PlenitudeDB.archiveMovement(button.dataset.archive,reason.trim());
      toast('Ocorrência arquivada e registrada na auditoria.');
      await load();
     }catch(error){
      toast(errorText(error),'warn');
     }finally{
      button.disabled=false;
     }
    };
   });
  }catch(error){
   box.innerHTML='';
   toast(errorText(error),'warn');
  }
 }
 document.getElementById('mov-refresh').onclick=load;
 document.getElementById('movement-create-form').onsubmit=async e=>{
  e.preventDefault();
  const b=e.submitter;
  const start=new Date(document.getElementById('mov-inicio').value);
  const end=new Date(document.getElementById('mov-fim').value);
  const classification=document.getElementById('mov-classificacao').value;
  const effect=document.getElementById('mov-efeito').value;
  const note=document.getElementById('mov-observacao').value.trim();

  if(!EXCEPTION_C[classification]){
   return toast('Selecione uma ocorrência administrativa válida.','warn');
  }
  if(Number.isNaN(start.getTime())||Number.isNaN(end.getTime())){
   return toast('Informe o início e o fim do período.','warn');
  }
  if(end<=start){
   return toast('O horário final deve ser posterior ao horário inicial.','warn');
  }
  if(note.length<5){
   document.getElementById('mov-observacao').focus();
   return toast('Informe a justificativa administrativa.','warn');
  }

  if(!confirm('Confirmar este lançamento excepcional? Use esta opção somente quando não existir marcação ou movimentação relacionada.'))return;

  b.disabled=true;
  try{
   await PlenitudeDB.createAdminMovement(
    document.getElementById('mov-funcionario').value,
    start.toISOString(),
    end.toISOString(),
    classification,
    effect,
    note
   );
   toast('Lançamento excepcional criado com sucesso.');
   setExceptionFormOpen(false);
   await load();
  }catch(err){
   toast(errorText(err),'warn');
  }finally{
   b.disabled=false;
  }
 };
 await load();
})();