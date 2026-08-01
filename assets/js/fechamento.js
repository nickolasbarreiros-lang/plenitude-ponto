(async function(){
 'use strict';

 const context=await initCommon(['administrador']);
 if(!context)return;

 const state={
  rows:[],
  selected:null,
  audit:null,
  auditLoading:false
 };

 const monthInput=document.getElementById('fc-mes');
 const closeButton=document.getElementById('fc-fechar');
 const now=new Date();

 monthInput.value=
  `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}`;

 const fmtDate=value=>
  value
   ?new Intl.DateTimeFormat('pt-BR',{
      dateStyle:'short',
      timeStyle:'short'
    }).format(new Date(value))
   :'—';

 const competence=(year,month)=>
  new Intl.DateTimeFormat('pt-BR',{
   month:'long',
   year:'numeric'
  }).format(new Date(year,month-1,1));

 const key=(year,month)=>
  `${year}-${String(month).padStart(2,'0')}`;

 function selectedParts(){
  const [year,month]=(monthInput.value||'')
   .split('-')
   .map(Number);

  return {year,month};
 }

 function rowFor(year,month){
  return state.rows.find(row=>
   Number(row.ano)===year&&
   Number(row.mes)===month
  );
 }

 function auditCount(name){
  return Number(state.audit?.[name]||0);
 }

 function blockingCount(){
  return Number(state.audit?.total_bloqueios||0);
 }

 function auditItems(){
  return [
   {
    key:'jornadas_incompletas',
    label:'Jornadas incompletas',
    detail:'Dias anteriores com menos de quatro marcações',
    href:'admin.html'
   },
   {
    key:'ajustes_pendentes',
    label:'Solicitações aguardando análise',
    detail:'Correções enviadas pelos funcionários',
    href:'ajustes.html?status=pendente&fila=1'
   },
   {
    key:'contingencias_pendentes',
    label:'Contingências com análise pendente',
    detail:'Registros offline conflitantes ou ainda não concluídos',
    href:'contingencia.html'
   },
   {
    key:'movimentacoes_abertas',
    label:'Saídas temporárias abertas',
    detail:'Funcionários sem retorno temporário registrado',
    href:'movimentacoes.html?pendentes=1'
   }
  ];
 }

 function renderAudit(){
  const panel=document.getElementById('fc-audit-panel');
  const title=document.getElementById('fc-audit-title');
  const badge=document.getElementById('fc-audit-badge');
  const progress=document.getElementById('fc-audit-progress');
  const summary=document.getElementById('fc-audit-summary');
  const items=document.getElementById('fc-audit-items');
  const correction=document.getElementById('fc-correct-pendencies');

  panel.classList.remove(
   'is-loading',
   'is-ready',
   'is-blocked',
   'is-closed'
  );

  if(state.auditLoading){
   panel.classList.add('is-loading');
   title.textContent='Conferindo competência...';
   badge.textContent='AUDITANDO';
   progress.style.width='35%';
   summary.textContent=
    'Verificando jornadas, correções, contingências e movimentações.';
   items.innerHTML='';
   correction.hidden=true;
   closeButton.disabled=true;
   return;
  }

  const {year,month}=selectedParts();
  const row=rowFor(year,month);

  if(row?.status==='fechado'){
   panel.classList.add('is-closed');
   title.textContent='Competência protegida';
   badge.textContent='FECHADA';
   progress.style.width='100%';
   summary.textContent=
    'O mês está congelado. Para alterar dados, utilize a reabertura controlada.';
   items.innerHTML='';
   correction.hidden=true;
   closeButton.disabled=true;
   return;
  }

  if(!state.audit){
   title.textContent='Auditoria não executada';
   badge.textContent='AGUARDE';
   progress.style.width='0%';
   summary.textContent='Selecione uma competência para iniciar a conferência.';
   items.innerHTML='';
   correction.hidden=true;
   closeButton.disabled=true;
   return;
  }

  const blockers=blockingCount();
  const checks=auditItems();
  const clean=checks.filter(item=>auditCount(item.key)===0).length;
  const percentage=Math.round((clean/checks.length)*100);

  progress.style.width=`${percentage}%`;

  items.innerHTML=checks.map(item=>{
   const count=auditCount(item.key);
   const ok=count===0;

   return `
    <a class="closure-audit-item ${ok?'ok':'problem'}"
      href="${item.href}">
     <span class="closure-audit-icon">${ok?'✓':'!'}</span>
     <span>
      <strong>${item.label}</strong>
      <small>${ok?'Nenhuma ocorrência':`${count} ocorrência${count===1?'':'s'} — ${item.detail}`}</small>
     </span>
     <b>${ok?'OK':count}</b>
    </a>`;
  }).join('');

  if(blockers>0){
   panel.classList.add('is-blocked');
   title.textContent='Fechamento bloqueado';
   badge.textContent=`${blockers} PENDÊNCIA${blockers===1?'':'S'}`;
   summary.textContent=
    'Resolva todas as pendências antes de fechar a competência.';
   correction.hidden=false;
   closeButton.disabled=true;
   closeButton.textContent='Fechamento bloqueado';
  }else{
   panel.classList.add('is-ready');
   title.textContent='Competência pronta para fechamento';
   badge.textContent='PRONTA';
   summary.textContent=
    'Todas as verificações obrigatórias foram concluídas com sucesso.';
   correction.hidden=true;
   closeButton.disabled=false;
   closeButton.textContent='Fechar competência';
  }
 }

 function renderSelected(){
  const {year,month}=selectedParts();
  const row=rowFor(year,month);
  const box=document.getElementById('fc-selected-status');

  if(!year||!month){
   box.innerHTML='';
   closeButton.disabled=true;
   return;
  }

  if(row?.status==='fechado'){
   box.className='closure-current-status closed';
   box.innerHTML=`
    <strong>🔒 ${competence(year,month)} está fechada.</strong>
    <span>Para alterar dados, use “Reabrir” no histórico.</span>`;
  }else{
   box.className='closure-current-status open';
   box.innerHTML=`
    <strong>🔓 ${competence(year,month)} está aberta.</strong>
    <span>A auditoria determinará se o fechamento pode ser realizado.</span>`;
  }

  renderAudit();
 }

 function render(){
  const closed=state.rows.filter(row=>row.status==='fechado').length;
  const reopened=state.rows.filter(row=>row.status==='reaberto').length;
  const current=rowFor(now.getFullYear(),now.getMonth()+1);

  document.getElementById('fc-fechados').textContent=closed;
  document.getElementById('fc-reabertos').textContent=reopened;
  document.getElementById('fc-atual').textContent=
   key(now.getFullYear(),now.getMonth()+1);
  document.getElementById('fc-atual-status').textContent=
   current?.status==='fechado'
    ?'Fechada e protegida'
    :'Aberta para lançamentos';

  const latest=[...state.rows].sort((a,b)=>
   new Date(b.atualizado_em)-new Date(a.atualizado_em)
  )[0];

  document.getElementById('fc-ultima').textContent=
   latest?fmtDate(latest.atualizado_em):'—';

  const body=document.getElementById('fc-body');
  const empty=document.getElementById('fc-empty');

  body.innerHTML=state.rows.map(row=>`
   <tr>
    <td>
     <strong>${competence(row.ano,row.mes)}</strong>
     <small>${key(row.ano,row.mes)}</small>
    </td>
    <td>
     <span class="closure-tag ${row.status}">
      ${row.status==='fechado'?'🔒 Fechada':'🔓 Reaberta'}
     </span>
    </td>
    <td>${row.status==='fechado'
      ?fmtDate(row.fechado_em)
      :fmtDate(row.reaberto_em)}</td>
    <td>${row.status==='fechado'
      ?(row.fechado_por_nome||'Administrador')
      :(row.reaberto_por_nome||'Administrador')}</td>
    <td>${row.observacao||'—'}</td>
    <td>
     ${row.status==='fechado'
       ?`<button class="btn outline compact"
           data-reopen="${row.ano}-${row.mes}">Reabrir</button>`
       :`<button class="btn primary compact"
           data-close="${row.ano}-${row.mes}">Fechar novamente</button>`}
    </td>
   </tr>`
  ).join('');

  empty.style.display=state.rows.length?'none':'block';

  body.querySelectorAll('[data-reopen]').forEach(button=>{
   button.onclick=()=>openReopen(
    ...button.dataset.reopen.split('-').map(Number)
   );
  });

  body.querySelectorAll('[data-close]').forEach(button=>{
   button.onclick=()=>{
    const [year,month]=button.dataset.close.split('-').map(Number);
    monthInput.value=key(year,month);
    auditSelected();
    window.scrollTo({top:0,behavior:'smooth'});
   };
  });

  renderSelected();
 }

 async function auditSelected(){
  const {year,month}=selectedParts();

  if(!year||!month)return;

  state.auditLoading=true;
  state.audit=null;
  renderSelected();

  try{
   state.audit=await window.PlenitudeDB.monthClosureAudit(year,month);
  }catch(error){
   toast(errorText(error),'warn');
   console.error(error);
   state.audit={
    total_bloqueios:1,
    jornadas_incompletas:0,
    ajustes_pendentes:0,
    contingencias_pendentes:0,
    movimentacoes_abertas:0
   };
  }finally{
   state.auditLoading=false;
   renderSelected();
  }
 }

 async function load(){
  try{
   state.rows=await window.PlenitudeDB.monthClosures(
    now.getFullYear()-5,
    now.getFullYear()+1
   );
   render();
   await auditSelected();
  }catch(error){
   toast(errorText(error),'warn');
   console.error(error);
  }
 }

 async function closeMonth(){
  const {year,month}=selectedParts();

  if(!year||!month)return;

  await auditSelected();

  if(blockingCount()>0){
   toast(
    'O fechamento está bloqueado enquanto existirem pendências.',
    'warn'
   );
   return;
  }

  const observation=
   document.getElementById('fc-observacao').value.trim();

  const confirmed=confirm(
   `Confirmar o fechamento de ${competence(year,month)}?\n\n`+
   '• Marcações e correções serão bloqueadas\n'+
   '• A competência ficará protegida\n'+
   '• A ação será registrada na auditoria\n\n'+
   'Para alterar o mês depois, será necessário reabri-lo.'
  );

  if(!confirmed)return;

  const masterPin=
   prompt('Digite o PIN Mestre de 6 números para fechar a competência:')||'';

  if(!/^\d{6}$/.test(masterPin)){
   toast('PIN Mestre inválido.','warn');
   return;
  }

  closeButton.disabled=true;

  try{
   await window.PlenitudeDB.closeMonth(
    year,
    month,
    observation,
    masterPin
   );

   toast('Competência fechada e protegida.');
   document.getElementById('fc-observacao').value='';
   await load();
  }catch(error){
   toast(errorText(error),'warn');
   console.error(error);
  }finally{
   renderSelected();
  }
 }

 function openReopen(year,month){
  state.selected={year,month};
  document.getElementById('fc-dialog-title').textContent=
   `Reabrir ${competence(year,month)}`;
  document.getElementById('fc-motivo').value='';
  document.getElementById('fc-dialog').showModal();
 }

 document.getElementById('fc-dialog').addEventListener(
  'close',
  async event=>{
   if(event.target.returnValue!=='default'||!state.selected)return;

   const reason=document.getElementById('fc-motivo').value.trim();

   if(reason.length<5){
    toast('Informe um motivo com pelo menos 5 caracteres.','warn');
    return;
   }

   const masterPin=
    prompt('Digite o PIN Mestre de 6 números para reabrir a competência:')||'';

   if(!/^\d{6}$/.test(masterPin)){
    toast('PIN Mestre inválido.','warn');
    return;
   }

   try{
    await window.PlenitudeDB.reopenMonth(
     state.selected.year,
     state.selected.month,
     reason,
     masterPin
    );

    toast('Competência reaberta. A ação foi auditada.');
    state.selected=null;
    await load();
   }catch(error){
    toast(errorText(error),'warn');
    console.error(error);
   }
  }
 );

 closeButton.onclick=closeMonth;
 document.getElementById('fc-refresh').onclick=load;
 monthInput.onchange=auditSelected;

 await load();
})();