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
 const occurred=fmt(r.ocorrido_em_dispositivo);
 const synced=fmt(r.sincronizado_em);
 const officialTime=
  r.horario_oficial||
  r.registrado_em_oficial||
  null;

 return `<article class="panel contingency-card contingency-${meta.className}">
  <div class="contingency-card-head">
   <div>
    <small>${r.funcionario_nome} · ${r.matricula}</small>
    <h3>${label(r.tipo)} — ${occurred}</h3>
    <p>Dispositivo: ${r.dispositivo_nome} · sincronizado em ${synced}</p>
   </div>
   <span class="contingency-status-badge ${meta.className}">
    <b>${meta.icon}</b>${meta.label}
   </span>
  </div>

  ${r.conflito&&actionable
   ?`<div class="notice compact danger"><b>Conflito:</b> ${r.conflito}</div>`
   :''}

  ${actionable
   ?`<div class="contingency-actions">
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

      <button class="btn primary" data-approve="${r.id}">
       Aprovar
      </button>

      <button class="btn outline danger" data-reject="${r.id}">
       Rejeitar
      </button>
     </div>`
   :`<div class="contingency-history-detail ${meta.className}">
      <span class="contingency-history-icon">${meta.icon}</span>
      <div>
       <strong>${meta.title}</strong>
       <p>${meta.message}</p>
       ${officialTime
        ?`<small>Horário oficial: ${fmt(officialTime)}</small>`
        :''}
      </div>
     </div>`}
 </article>`;
}
async function load(){const box=document.getElementById('cont-list');box.innerHTML='<div class="mini-empty">Carregando...</div>';try{const rows=await rpc('listar_contingencias_admin',{p_status:document.getElementById('cont-status').value||null,p_inicio:document.getElementById('cont-start').value||null,p_fim:document.getElementById('cont-end').value||null});document.getElementById('cont-count').textContent=`${rows.filter(r=>['pendente','conflitante'].includes(r.status)).length} pendente(s)`;box.innerHTML=rows.length?rows.map(card).join(''):'<div class="panel mini-empty">Nenhum registro de contingência.</div>';box.querySelectorAll('[data-approve]').forEach(b=>b.onclick=()=>analyze(b,'aprovar'));box.querySelectorAll('[data-reject]').forEach(b=>b.onclick=()=>analyze(b,'rejeitar'))}catch(e){box.innerHTML='';toast(e.message,'warn')}}
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
document.getElementById('cont-refresh').onclick=load;document.getElementById('cont-status').onchange=load;
(async()=>{await window.PlenitudeAuth.requireAccess({roles:['administrador']});const now=new Date(),start=new Date(now);start.setDate(now.getDate()-30);const dk=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;document.getElementById('cont-start').value=dk(start);document.getElementById('cont-end').value=dk(now);await load()})().catch(e=>toast(e.message,'warn'));
})();