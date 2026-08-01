(async function(){
 'use strict';

 const context=await initCommon(['administrador']);
 if(!context)return;

 const state={
  rows:[],
  selected:null,
  audit:null,
  auditLoading:false,
  mirrors:[],
  mirrorsLoading:false,
  mirrorKey:null
 };

 const monthSelect=document.getElementById('fc-mes-select');
 const yearSelect=document.getElementById('fc-ano-select');
 const closeButton=document.getElementById('fc-fechar');
 const now=new Date();

 for(let year=now.getFullYear()+1;year>=now.getFullYear()-6;year--){
  const option=document.createElement('option');
  option.value=String(year);
  option.textContent=String(year);
  yearSelect.appendChild(option);
 }

 const previousMonth=new Date(now.getFullYear(),now.getMonth()-1,1);
 monthSelect.value=String(previousMonth.getMonth()+1);
 yearSelect.value=String(previousMonth.getFullYear());

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

 function updateCompetenceHint(){
  const {year,month}=selectedParts();
  const hint=document.getElementById('fc-competence-hint');
  if(!hint||!year||!month)return;

  const currentKey=key(now.getFullYear(),now.getMonth()+1);
  const selectedKey=key(year,month);

  hint.textContent=
   selectedKey===currentKey
    ?'Atenção: esta é a competência atual e ainda está em andamento.'
    :`Competência selecionada: ${competence(year,month)}.`;
 }

 function selectedParts(){
  return {
   year:Number(yearSelect.value||0),
   month:Number(monthSelect.value||0)
  };
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


 function selectedCompetenceKey(){
  const {year,month}=selectedParts();
  return key(year,month);
 }

 function mirrorPrintUrl(employeeId=null){
  const {year,month}=selectedParts();
  const params=new URLSearchParams({
   mes:key(year,month)
  });

  if(employeeId){
   params.set('funcionario',employeeId);
  }else{
   params.set('todos','1');
  }

  return `espelhos-impressao.html?${params.toString()}`;
 }

 function renderMirrors(){
  const panel=document.getElementById('fc-mirror-panel');
  const list=document.getElementById('fc-mirror-list');
  const empty=document.getElementById('fc-mirror-empty');
  const {year,month}=selectedParts();
  const row=rowFor(year,month);

  if(!panel||!list||!empty)return;

  if(row?.status!=='fechado'){
   panel.hidden=true;
   return;
  }

  panel.hidden=false;
  document.getElementById('fc-mirror-title').textContent=
   `Espelhos de ${competence(year,month)}`;

  if(state.mirrorsLoading){
   list.innerHTML='<div class="mini-empty">Carregando controle de assinaturas...</div>';
   empty.style.display='none';
   return;
  }

  const total=state.mirrors.length;
  const signed=state.mirrors.filter(item=>item.status==='assinado').length;
  const pending=total-signed;

  document.getElementById('fc-mirror-total').textContent=String(total);
  document.getElementById('fc-mirror-pending').textContent=String(pending);
  document.getElementById('fc-mirror-signed').textContent=String(signed);

  list.innerHTML=state.mirrors.map(item=>{
   const isSigned=item.status==='assinado';
   const signedAt=item.assinado_em
    ?new Intl.DateTimeFormat('pt-BR').format(
      new Date(`${item.assinado_em}T12:00:00`)
     )
    :'';

   return `
    <article class="closure-mirror-card ${isSigned?'is-signed':'is-pending'}">
     <div class="closure-mirror-person">
      <span class="closure-mirror-avatar">${(item.funcionario_nome||'?').charAt(0)}</span>
      <div>
       <strong>${item.funcionario_nome}</strong>
       <small>Matrícula ${item.matricula||'—'} · ${item.cargo||'Funcionário'}</small>
      </div>
     </div>

     <span class="closure-mirror-status">
      ${isSigned?'✓ ASSINADO':'○ AGUARDANDO ASSINATURA'}
     </span>

     <div class="closure-mirror-info">
      ${isSigned
       ?`<b>Recebido em ${signedAt}</b>
          <small>${item.registrado_por_nome
            ?`Registrado por ${item.registrado_por_nome}`
            :'Devolução registrada'}</small>
          ${item.observacao?`<small>${item.observacao}</small>`:''}`
       :`<b>Espelho ainda não devolvido</b>
          <small>Imprima, recolha a assinatura e registre o recebimento.</small>`}
     </div>

     <div class="closure-mirror-actions">
      <a class="btn outline compact"
       href="${mirrorPrintUrl(item.funcionario_id)}"
       target="_blank" rel="noopener">
       Abrir espelho
      </a>

      <button class="btn ${isSigned?'outline':'primary'} compact"
       data-mirror-status="${isSigned?'pendente':'assinado'}"
       data-employee-id="${item.funcionario_id}">
       ${isSigned?'Marcar como pendente':'Marcar como assinado'}
      </button>
     </div>
    </article>`;
  }).join('');

  empty.style.display=total?'none':'block';

  list.querySelectorAll('[data-mirror-status]').forEach(button=>{
   button.onclick=()=>changeMirrorStatus(button);
  });
 }

 async function loadMirrors(force=false){
  const {year,month}=selectedParts();
  const row=rowFor(year,month);
  const selectedKey=selectedCompetenceKey();

  if(row?.status!=='fechado'){
   state.mirrors=[];
   state.mirrorKey=null;
   renderMirrors();
   return;
  }

  if(!force&&state.mirrorKey===selectedKey&&state.mirrors.length){
   renderMirrors();
   return;
  }

  state.mirrorsLoading=true;
  renderMirrors();

  try{
   state.mirrors=await window.PlenitudeDB.monthlyMirrorStatuses(year,month);
   state.mirrorKey=selectedKey;
  }catch(error){
   toast(errorText(error),'warn');
   console.error(error);
   state.mirrors=[];
  }finally{
   state.mirrorsLoading=false;
   renderMirrors();
  }
 }

 async function changeMirrorStatus(button){
  const {year,month}=selectedParts();
  const employeeId=button.dataset.employeeId;
  const nextStatus=button.dataset.mirrorStatus;

  button.disabled=true;

  try{
   if(nextStatus==='assinado'){
    const today=localDateKey(new Date());
    const signedDate=prompt(
     'Informe a data em que o funcionário assinou o espelho:',
     today
    );

    if(signedDate===null)return;

    if(!/^\d{4}-\d{2}-\d{2}$/.test(signedDate)){
     throw new Error('Informe a data no formato AAAA-MM-DD.');
    }

    const note=prompt(
     'Observação opcional sobre o recebimento do espelho:',
     ''
    );

    await window.PlenitudeDB.updateMonthlyMirrorStatus(
     employeeId,
     year,
     month,
     'assinado',
     signedDate,
     note||''
    );

    toast('Espelho marcado como assinado.');
   }else{
    const confirmed=confirm(
     'Deseja voltar este espelho para pendente de assinatura?'
    );

    if(!confirmed)return;

    await window.PlenitudeDB.updateMonthlyMirrorStatus(
     employeeId,
     year,
     month,
     'pendente',
     null,
     ''
    );

    toast('Espelho voltou para pendente.');
   }

   await loadMirrors(true);
  }catch(error){
   toast(errorText(error),'warn');
   console.error(error);
  }finally{
   button.disabled=false;
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

  updateCompetenceHint();
  renderAudit();
  renderMirrors();

  if(row?.status==='fechado'){
   loadMirrors().catch(error=>console.error(error));
  }
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
    monthSelect.value=String(month);
    yearSelect.value=String(year);
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
 document.getElementById('fc-refresh-mirrors').onclick=()=>loadMirrors(true);
 document.getElementById('fc-print-all').onclick=()=>{
  window.open(mirrorPrintUrl(), '_blank', 'noopener');
 };
 monthSelect.onchange=()=>{
  state.mirrorKey=null;
  auditSelected();
 };
 yearSelect.onchange=()=>{
  state.mirrorKey=null;
  auditSelected();
 };

 await load();
})();