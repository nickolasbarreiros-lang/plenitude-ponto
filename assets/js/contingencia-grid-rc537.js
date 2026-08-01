(function(){'use strict';
const client=window.PlenitudeAuth.client;
const label=t=>({entrada:'Entrada',inicio_intervalo:'Início do almoço',fim_intervalo:'Retorno do almoço',saida:'Saída'})[t]||t;
const fmt=v=>new Date(v).toLocaleString('pt-BR');
async function rpc(n,a={}){const {data,error}=await client.rpc(n,a);if(error)throw error;return data||[]}
function contingencyStatusMeta(row){
 const status=String(row.status||'').toLowerCase();

 if(status==='aprovado'){
  return {
   className:'approved',
   label:'IMPORTADO',
   icon:'✓',
   title:'Importado para a jornada oficial',
   message:
    row.observacao_admin||
    'A marcação offline foi importada automaticamente para o ponto oficial.'
  };
 }

 if(status==='duplicado'){
  return {
   className:'duplicate',
   label:'DUPLICADO',
   icon:'≋',
   title:'Registro duplicado',
   message:
    row.observacao_admin||
    'Já existia uma marcação oficial equivalente para este funcionário e data.'
  };
 }

 if(status==='rejeitado'){
  return {
   className:'rejected',
   label:'REJEITADO',
   icon:'×',
   title:'Registro rejeitado pelo administrador',
   message:
    row.observacao_admin||
    'O registro offline foi rejeitado durante a conferência administrativa.'
  };
 }

 if(status==='conflitante'){
  return {
   className:'conflict',
   label:'CONFLITO',
   icon:'!',
   title:'Registro com divergência',
   message:
    row.conflito||
    'O horário ou os dados do dispositivo precisam de conferência.'
  };
 }

 return {
  className:'pending',
  label:'PENDENTE',
  icon:'…',
  title:'Aguardando análise',
  message:
   row.conflito||
   'Este registro offline ainda precisa ser aprovado ou rejeitado.'
 };
}

function card(r){
 const actionable=['pendente','conflitante'].includes(r.status);
 const meta=contingencyStatusMeta(r);
 const occurredDate=new Date(r.ocorrido_em_dispositivo);
 const date=occurredDate.toLocaleDateString('pt-BR');
 const time=occurredDate.toLocaleTimeString('pt-BR',{
  hour:'2-digit',
  minute:'2-digit'
 });
 const synced=r.sincronizado_em?fmt(r.sincronizado_em):'—';
 const officialTime=
  r.horario_oficial||
  r.registrado_em_oficial||
  null;

 return `<article class="contingency-compact-card contingency-${meta.className}"
   data-status="${r.status}">
  <button type="button" class="contingency-card-summary"
   aria-expanded="false">
   <span class="contingency-card-accent"></span>

   <span class="contingency-summary-main">
    <small>${r.funcionario_nome} · ${r.matricula}</small>
    <strong>${label(r.tipo)}</strong>
    <span>${date} • ${time}</span>
    <em>${r.dispositivo_nome||'Dispositivo não informado'}</em>
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
     ${officialTime
      ?`<small>Horário oficial: ${fmt(officialTime)}</small>`
      :''}
    </div>
   </div>

   ${r.conflito&&actionable
    ?`<div class="notice compact danger"><b>Conflito:</b> ${r.conflito}</div>`
    :''}

   ${actionable
    ?`<div class="contingency-actions compact-actions">
      <label>
       Horário para aprovação
       <input data-time type="datetime-local"
        value="${new Date(
         new Date(r.ocorrido_em_dispositivo).getTime()-
         new Date(r.ocorrido_em_dispositivo).getTimezoneOffset()*60000
        ).toISOString().slice(0,16)}">
      </label>

      <label class="wide">
       Observação
       <textarea data-note
        placeholder="Conferência realizada, justificativa ou motivo da rejeição."></textarea>
      </label>

      <div class="compact-action-buttons">
       <button class="btn primary" data-approve="${r.id}">Aprovar</button>
       <button class="btn outline danger" data-reject="${r.id}">Rejeitar</button>
      </div>
     </div>`
    :''}
  </div>
 </article>`;
}

let activeTab='';

function updateTabCounts(rows){
 const counts={
  all:rows.length,
  pendente:rows.filter(r=>['pendente','conflitante'].includes(r.status)).length,
  aprovado:rows.filter(r=>r.status==='aprovado').length,
  rejeitado:rows.filter(r=>r.status==='rejeitado').length,
  duplicado:rows.filter(r=>r.status==='duplicado').length
 };

 Object.entries(counts).forEach(([key,value])=>{
  const element=document.getElementById(`tab-count-${key}`);
  if(element)element.textContent=String(value);
 });
}

function filterRowsByTab(rows){
 if(!activeTab)return rows;
 if(activeTab==='pendente'){
  return rows.filter(row=>['pendente','conflitante'].includes(row.status));
 }
 return rows.filter(row=>row.status===activeTab);
}

function bindCardInteractions(box){
 box.querySelectorAll('.contingency-card-summary').forEach(summary=>{
  summary.onclick=()=>{
   const card=summary.closest('.contingency-compact-card');
   const details=card.querySelector('.contingency-card-details');
   const expanded=summary.getAttribute('aria-expanded')==='true';

   summary.setAttribute('aria-expanded',String(!expanded));
   details.hidden=expanded;
   card.classList.toggle('is-expanded',!expanded);
  };
 });

 box.querySelectorAll('[data-approve]').forEach(button=>{
  button.onclick=()=>analyze(button,'aprovar');
 });

 box.querySelectorAll('[data-reject]').forEach(button=>{
  button.onclick=()=>analyze(button,'rejeitar');
 });
}

async function load(){
 const box=document.getElementById('cont-list');
 box.innerHTML='<div class="panel mini-empty">Carregando...</div>';

 try{
  const rows=await rpc('listar_contingencias_admin',{
   p_status:document.getElementById('cont-status').value||null,
   p_inicio:document.getElementById('cont-start').value||null,
   p_fim:document.getElementById('cont-end').value||null
  });

  updateTabCounts(rows);
  const filtered=filterRowsByTab(rows);

  document.getElementById('cont-count').textContent=
   `${rows.filter(r=>['pendente','conflitante'].includes(r.status)).length} pendente(s)`;

  box.innerHTML=filtered.length
   ?filtered.map(card).join('')
   :'<div class="panel mini-empty">Nenhum registro nesta categoria.</div>';

  bindCardInteractions(box);
 }catch(error){
  box.innerHTML='';
  toast(error.message,'warn');
 }
}

async function analyze(button,action){const card=button.closest('.contingency-card'),note=card.querySelector('[data-note]').value.trim(),time=card.querySelector('[data-time]').value;if(action==='rejeitar'&&note.length<5)return toast('Informe o motivo da rejeição.','warn');if(!confirm(action==='aprovar'?'Aprovar e criar a marcação oficial?':'Rejeitar este registro offline?'))return;card.querySelectorAll('button,input,textarea').forEach(e=>e.disabled=true);try{
 const recordId=
  action==='aprovar'
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
}catch(e){
 console.error('Falha ao analisar contingência',e);
 toast(e.message||'Não foi possível analisar o registro.','warn');
 card.querySelectorAll('button,input,textarea').forEach(x=>x.disabled=false);
}}
document.querySelectorAll('[data-tab-status]').forEach(button=>{
 button.onclick=()=>{
  activeTab=button.dataset.tabStatus||'';

  document.querySelectorAll('[data-tab-status]').forEach(tab=>{
   tab.classList.toggle('active',tab===button);
  });

  load();
 };
});

document.getElementById('cont-refresh').onclick=load;document.getElementById('cont-status').onchange=load;
(async()=>{await window.PlenitudeAuth.requireAccess({roles:['administrador']});const now=new Date(),start=new Date(now);start.setDate(now.getDate()-30);const dk=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;document.getElementById('cont-start').value=dk(start);document.getElementById('cont-end').value=dk(now);await load()})().catch(e=>toast(e.message,'warn'));
})();