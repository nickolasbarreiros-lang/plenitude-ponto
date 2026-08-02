(function(){
'use strict';

const client=window.PlenitudeAuth.client;
const label=t=>({
 entrada:'Entrada',
 inicio_intervalo:'Início do almoço',
 fim_intervalo:'Retorno do almoço',
 saida:'Saída'
})[t]||t;
const fmt=v=>new Date(v).toLocaleString('pt-BR');

async function rpc(name,args={}){
 const {data,error}=await client.rpc(name,args);
 if(error)throw error;
 return data||[];
}

function contingencyStatusMeta(row){
 const status=String(row.status||'').toLowerCase();

 if(status==='aprovado'){
  return {
   className:'approved',
   label:'IMPORTADO',
   icon:'✓',
   title:'Importado para a jornada oficial',
   message:row.observacao_admin||
    'A marcação offline foi importada automaticamente para o ponto oficial.'
  };
 }

 if(status==='duplicado'){
  return {
   className:'duplicate',
   label:'DUPLICADO',
   icon:'≋',
   title:'Registro duplicado',
   message:row.observacao_admin||
    'Já existia uma marcação oficial equivalente para este funcionário e data.'
  };
 }

 if(status==='rejeitado'){
  return {
   className:'rejected',
   label:'REJEITADO',
   icon:'×',
   title:'Registro rejeitado pelo administrador',
   message:row.observacao_admin||
    'O registro offline foi rejeitado durante a conferência administrativa.'
  };
 }

 if(status==='conflitante'){
  return {
   className:'conflict',
   label:'CONFLITO',
   icon:'!',
   title:'Registro com divergência',
   message:row.conflito||
    'O horário ou os dados do dispositivo precisam de conferência.'
  };
 }

 return {
  className:'pending',
  label:'PENDENTE',
  icon:'…',
  title:'Aguardando análise',
  message:row.conflito||
   'Este registro offline ainda precisa ser aprovado ou rejeitado.'
 };
}

function card(row){
 const status=String(row.status||'').toLowerCase();
 const actionable=['pendente','conflitante'].includes(status);
 const meta=contingencyStatusMeta(row);
 const occurredDate=new Date(row.ocorrido_em_dispositivo);
 const date=occurredDate.toLocaleDateString('pt-BR');
 const time=occurredDate.toLocaleTimeString('pt-BR',{
  hour:'2-digit',
  minute:'2-digit'
 });
 const synced=row.sincronizado_em?fmt(row.sincronizado_em):'—';
 const officialTime=row.horario_oficial||row.registrado_em_oficial||null;

 return `<article class="contingency-compact-card contingency-${meta.className}"
   data-status="${status}">
  <button type="button" class="contingency-card-summary" aria-expanded="false">
   <span class="contingency-card-accent"></span>
   <span class="contingency-summary-main">
    <small>${row.funcionario_nome} · ${row.matricula}</small>
    <strong>${label(row.tipo)}</strong>
    <span>${date} • ${time}</span>
    <em>${row.dispositivo_nome||'Dispositivo não informado'}</em>
   </span>
   <span class="contingency-status-badge ${meta.className}">
    <b>${meta.icon}</b>${meta.label}
   </span>
   <span class="contingency-expand-icon">⌄</span>
  </button>

  <div class="contingency-card-details" hidden>
   <div class="contingency-history-detail ${meta.className}">
    <span class="contingency-history-icon">${meta.icon}</span>
    <div>
     <strong>${meta.title}</strong>
     <p>${meta.message}</p>
     <small>Sincronizado em: ${synced}</small>
     ${officialTime?`<small>Horário oficial: ${fmt(officialTime)}</small>`:''}
    </div>
   </div>

   ${row.conflito&&actionable
    ?`<div class="notice compact danger"><b>Conflito:</b> ${row.conflito}</div>`
    :''}

   ${actionable
    ?`<div class="contingency-actions compact-actions">
      <label>
       Horário para aprovação
       <input data-time type="datetime-local"
        value="${new Date(
         occurredDate.getTime()-occurredDate.getTimezoneOffset()*60000
        ).toISOString().slice(0,16)}">
      </label>
      <label class="wide">
       Observação
       <textarea data-note
        placeholder="Conferência realizada, justificativa ou motivo da rejeição."></textarea>
      </label>
      <div class="compact-action-buttons">
       <button class="btn primary" data-approve="${row.id}">Aprovar</button>
       <button class="btn outline danger" data-reject="${row.id}">Rejeitar</button>
      </div>
     </div>`
    :''}
  </div>
 </article>`;
}

let activeTab='';
let currentView=true;
let loadedRows=[];

function dateKey(date){
 return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}

function monthBounds(monthValue){
 const [year,month]=monthValue.split('-').map(Number);
 return {
  start:`${year}-${String(month).padStart(2,'0')}-01`,
  end:dateKey(new Date(year,month,0))
 };
}

function currentMonthKey(){
 const now=new Date();
 return `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}`;
}

function isPending(row){
 return ['pendente','conflitante'].includes(
  String(row.status||'').toLowerCase()
 );
}

function deduplicate(rows){
 const map=new Map();
 rows.forEach(row=>map.set(String(row.id),row));
 return [...map.values()].sort(
  (a,b)=>new Date(b.ocorrido_em_dispositivo)-new Date(a.ocorrido_em_dispositivo)
 );
}

function updateTabCounts(rows){
 const counts={
  all:rows.length,
  pendente:rows.filter(isPending).length,
  aprovado:rows.filter(r=>r.status==='aprovado').length,
  rejeitado:rows.filter(r=>r.status==='rejeitado').length,
  duplicado:rows.filter(r=>r.status==='duplicado').length
 };

 Object.entries(counts).forEach(([key,value])=>{
  const element=document.getElementById(`tab-count-${key}`);
  if(element)element.textContent=String(value);
 });
}

function filterRows(rows){
 const statusFilter=document.getElementById('cont-status').value;
 let result=rows;

 if(statusFilter==='pendente'){
  result=result.filter(isPending);
 }else if(statusFilter){
  result=result.filter(row=>row.status===statusFilter);
 }

 if(activeTab==='pendente'){
  result=result.filter(isPending);
 }else if(activeTab){
  result=result.filter(row=>row.status===activeTab);
 }

 return result;
}

function render(){
 const box=document.getElementById('cont-list');
 updateTabCounts(loadedRows);
 const filtered=filterRows(loadedRows);

 document.getElementById('cont-count').textContent=
  `${loadedRows.filter(isPending).length} pendente(s)`;

 box.innerHTML=filtered.length
  ?filtered.map(card).join('')
  :'<div class="panel mini-empty">Nenhum registro nesta categoria.</div>';

 bindCardInteractions(box);
}

function bindCardInteractions(box){
 box.querySelectorAll('.contingency-card-summary').forEach(summary=>{
  summary.onclick=()=>{
   const cardElement=summary.closest('.contingency-compact-card');
   const details=cardElement.querySelector('.contingency-card-details');
   const expanded=summary.getAttribute('aria-expanded')==='true';
   summary.setAttribute('aria-expanded',String(!expanded));
   details.hidden=expanded;
   cardElement.classList.toggle('is-expanded',!expanded);
  };
 });

 box.querySelectorAll('[data-approve]').forEach(button=>{
  button.onclick=()=>analyze(button,'aprovar');
 });

 box.querySelectorAll('[data-reject]').forEach(button=>{
  button.onclick=()=>analyze(button,'rejeitar');
 });
}

async function fetchRows(){
 const selectedMonth=document.getElementById('cont-month').value||currentMonthKey();
 const bounds=monthBounds(selectedMonth);

 if(!currentView){
  return rpc('listar_contingencias_admin',{
   p_status:null,
   p_inicio:bounds.start,
   p_fim:bounds.end
  });
 }

 const currentBounds=monthBounds(currentMonthKey());
 const [monthRows,historyRows]=await Promise.all([
  rpc('listar_contingencias_admin',{
   p_status:null,
   p_inicio:currentBounds.start,
   p_fim:currentBounds.end
  }),
  rpc('listar_contingencias_admin',{
   p_status:null,
   p_inicio:null,
   p_fim:currentBounds.end
  })
 ]);

 return deduplicate([
  ...monthRows,
  ...historyRows.filter(isPending)
 ]);
}

async function load(){
 const box=document.getElementById('cont-list');
 box.innerHTML='<div class="panel mini-empty">Carregando...</div>';

 try{
  loadedRows=deduplicate(await fetchRows());
  render();
 }catch(error){
  box.innerHTML='<div class="panel mini-empty">Não foi possível carregar os registros.</div>';
  toast(error.message,'warn');
  console.error(error);
 }
}

async function analyze(button,action){
 const cardElement=button.closest('.contingency-compact-card');
 const note=cardElement.querySelector('[data-note]').value.trim();
 const time=cardElement.querySelector('[data-time]').value;

 if(action==='rejeitar'&&note.length<5){
  return toast('Informe o motivo da rejeição.','warn');
 }

 if(!confirm(
  action==='aprovar'
   ?'Aprovar e criar a marcação oficial?'
   :'Rejeitar este registro offline?'
 ))return;

 cardElement.querySelectorAll('button,input,textarea')
  .forEach(element=>element.disabled=true);

 try{
  const recordId=action==='aprovar'
   ?button.dataset.approve
   :button.dataset.reject;

  if(!recordId){
   throw new Error('Identificador do registro de contingência não encontrado.');
  }

  const payload={
   p_id:recordId,
   p_acao:action,
   p_observacao:note||null
  };

  if(action==='aprovar'){
   payload.p_horario_corrigido=new Date(time).toISOString();
  }

  await rpc('analisar_contingencia_admin_v2',payload);
  toast(action==='aprovar'?'Registro aprovado.':'Registro rejeitado.');
  await load();
 }catch(error){
  console.error('Falha ao analisar contingência',error);
  toast(error.message||'Não foi possível analisar o registro.','warn');
  cardElement.querySelectorAll('button,input,textarea')
   .forEach(element=>element.disabled=false);
 }
}

function setCurrentView(enabled){
 currentView=enabled;
 const monthInput=document.getElementById('cont-month');
 const currentButton=document.getElementById('cont-current-view');
 const note=document.getElementById('cont-view-note');

 if(enabled){
  monthInput.value=currentMonthKey();
  currentButton.classList.add('active');
  note.innerHTML=
   '<b>Visão atual:</b> eventos do mês vigente e todas as pendências anteriores.';
 }else{
  currentButton.classList.remove('active');
  const [year,month]=monthInput.value.split('-').map(Number);
  const labelMonth=new Intl.DateTimeFormat('pt-BR',{
   month:'long',
   year:'numeric'
  }).format(new Date(year,month-1,1));
  note.innerHTML=
   `<b>Histórico mensal:</b> exibindo somente os eventos de ${labelMonth}.`;
 }
}

document.querySelectorAll('[data-tab-status]').forEach(button=>{
 button.onclick=()=>{
  activeTab=button.dataset.tabStatus||'';
  document.querySelectorAll('[data-tab-status]').forEach(tab=>{
   tab.classList.toggle('active',tab===button);
  });
  render();
 };
});

document.getElementById('cont-status').onchange=render;


document.getElementById('cont-month').onchange=()=>{
 setCurrentView(false);
 load();
};

document.getElementById('cont-current-view').onclick=()=>{
 setCurrentView(true);
 load();
};

(async()=>{
 await window.PlenitudeAuth.requireAccess({roles:['administrador']});
 document.getElementById('cont-month').value=currentMonthKey();
 setCurrentView(true);
 await load();
})().catch(error=>toast(error.message,'warn'));


const contMonthInput=document.getElementById('cont-month');
const contMonthOpen=document.getElementById('cont-month-open');

function openContingencyMonthPicker(){
 if(!contMonthInput)return;

 if(typeof contMonthInput.showPicker==='function'){
  contMonthInput.showPicker();
  return;
 }

 contMonthInput.focus();
 contMonthInput.click();
}

contMonthOpen?.addEventListener('click',event=>{
 event.preventDefault();
 event.stopPropagation();
 openContingencyMonthPicker();
});

document.querySelector('.month-picker-shell')?.addEventListener('click',event=>{
 if(event.target===contMonthInput)return;
 openContingencyMonthPicker();
});


const contingencyLogoutButton=document.getElementById('sair');
if(contingencyLogoutButton){
 contingencyLogoutButton.onclick=async()=>{
  contingencyLogoutButton.disabled=true;

  try{
   await window.PlenitudeAuth.signOut();
  }catch(error){
   console.warn('Falha ao encerrar a sessão pelo Supabase.',error);
  }finally{
   sessionStorage.clear();
   localStorage.removeItem('plenitude-employee-session');
   location.replace('index.html');
  }
 };
}

})();

