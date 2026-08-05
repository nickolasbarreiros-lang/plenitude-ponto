(function(){
'use strict';

const state={rows:[],selected:null,mode:null};
const $=id=>document.getElementById(id);
const fmtDate=value=>new Date(value+'T12:00:00').toLocaleDateString('pt-BR');
const fmtTime=value=>new Date(value).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit',second:'2-digit'});
const labels={
 entrada:'Entrada',
 inicio_intervalo:'Início do almoço',
 fim_intervalo:'Retorno do almoço',
 saida:'Saída'
};

function dateKey(date){
 return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}

function escapeHtml(value){
 return String(value??'')
  .replaceAll('&','&amp;')
  .replaceAll('<','&lt;')
  .replaceAll('>','&gt;')
  .replaceAll('"','&quot;')
  .replaceAll("'","&#039;");
}

function markCard(row){
 const archived=row.estado==='arquivada';
 return `<article class="managed-mark-card ${archived?'is-archived':''}">
  <div class="managed-mark-main">
   <small>${escapeHtml(row.funcionario_nome)} · ${escapeHtml(row.matricula||'—')}</small>
   <strong>${escapeHtml(labels[row.tipo]||row.tipo)}</strong>
   <span>${fmtDate(row.data_local)} às ${fmtTime(row.registrado_em)}</span>
   <em>${escapeHtml(row.origem||'Origem não informada')}</em>
   ${archived?`<p><b>Motivo:</b> ${escapeHtml(row.motivo)}</p>`:''}
  </div>
  <span class="managed-mark-status ${archived?'archived':'active'}">${archived?'ARQUIVADA':'ATIVA'}</span>
  <div class="managed-mark-actions">
   ${!archived?`<button class="btn outline" data-soft="${row.id_original}">Remover do sistema</button>`:''}
   <button class="btn danger" data-hard="${escapeHtml(row.chave)}">Excluir definitivamente</button>
  </div>
 </article>`;
}

function render(){
 const list=$('gm-list');
 const active=state.rows.filter(row=>row.estado==='ativa').length;
 const archived=state.rows.length-active;
 $('gm-summary').innerHTML=`
  <span><b>${active}</b> ativa(s)</span>
  <span><b>${archived}</b> arquivada(s)</span>
  <span><b>${state.rows.length}</b> resultado(s)</span>`;

 list.innerHTML=state.rows.length
  ?state.rows.map(markCard).join('')
  :'<div class="panel mini-empty">Nenhuma marcação encontrada no período.</div>';

 list.querySelectorAll('[data-soft]').forEach(button=>{
  button.onclick=()=>{
   const row=state.rows.find(item=>String(item.id_original)===button.dataset.soft&&item.estado==='ativa');
   openDialog(row,'soft');
  };
 });

 list.querySelectorAll('[data-hard]').forEach(button=>{
  const row=state.rows.find(item=>item.chave===button.dataset.hard);
  button.onclick=()=>openDialog(row,'hard');
 });
}

async function load(){
 $('gm-list').innerHTML='<div class="panel mini-empty">Carregando...</div>';
 try{
  state.rows=await window.PlenitudeDB.managedMarks(
   $('gm-employee').value||null,
   $('gm-start').value,
   $('gm-end').value,
   $('gm-archived').checked
  );
  render();
 }catch(error){
  console.error(error);
  $('gm-list').innerHTML=`<div class="panel mini-empty">Erro: ${escapeHtml(error.message)}</div>`;
  toast(error.message,'warn');
 }
}

function openDialog(row,mode){
 if(!row)return;
 state.selected=row;
 state.mode=mode;
 const hard=mode==='hard';

 $('gm-dialog-level').textContent=hard?'EXCLUSÃO NÍVEL 2':'EXCLUSÃO NÍVEL 1';
 $('gm-dialog-title').textContent=hard?'Excluir definitivamente':'Remover do sistema';
 $('gm-hard-fields').hidden=!hard;
 $('gm-submit').textContent=hard?'Excluir definitivamente':'Arquivar marcação';
 $('gm-submit').className=hard?'btn danger':'btn primary';
 $('gm-reason').value='';
 $('gm-confirmation').value='';
 $('gm-master-pin').value='';
 $('gm-dialog-mark').innerHTML=`
  <strong>${escapeHtml(row.funcionario_nome)}</strong>
  <span>${escapeHtml(labels[row.tipo]||row.tipo)} — ${fmtDate(row.data_local)} às ${fmtTime(row.registrado_em)}</span>
  <small>Estado atual: ${row.estado==='arquivada'?'Arquivada':'Ativa'}</small>`;
 $('gm-dialog').showModal();
}

async function submit(event){
 event.preventDefault();
 const row=state.selected;
 const reason=$('gm-reason').value.trim();
 const submitButton=$('gm-submit');

 if(reason.length<(state.mode==='hard'?12:8)){
  return toast(`Informe um motivo com pelo menos ${state.mode==='hard'?12:8} caracteres.`,'warn');
 }

 submitButton.disabled=true;
 submitButton.setAttribute('aria-busy','true');

 try{
  if(state.mode==='soft'){
   await window.PlenitudeDB.archiveMark(row.id_original,reason);
   toast('Marcação removida do sistema e arquivada para auditoria.');
  }else{
   await window.PlenitudeDB.permanentlyDeleteMark({
    markId:row.estado==='ativa'?row.id_original:null,
    archiveId:row.estado==='arquivada'?row.arquivo_id:null,
    reason,
    confirmation:$('gm-confirmation').value,
    masterPin:$('gm-master-pin').value
   });
   toast('Marcação excluída definitivamente.');
  }

  $('gm-dialog').close();
  await load();
 }catch(error){
  console.error(error);
  toast(error.message,'warn');
 }finally{
  submitButton.disabled=false;
  submitButton.removeAttribute('aria-busy');
 }
}

(async()=>{
 await window.PlenitudeAuth.requireAccess({roles:['administrador']});
 const employees=await window.PlenitudeDB.employees();
 $('gm-employee').innerHTML='<option value="">Todos</option>'+
  employees.filter(item=>item.ativo!==false).map(item=>
   `<option value="${item.id}">${escapeHtml(item.nome)} — ${escapeHtml(item.matricula||'—')}</option>`
  ).join('');

 const now=new Date();
 const start=new Date(now.getFullYear(),now.getMonth(),1);
 $('gm-start').value=dateKey(start);
 $('gm-end').value=dateKey(now);

 $('gm-search').onclick=load;
 $('gm-employee').onchange=load;
 $('gm-archived').onchange=load;
 $('gm-form').onsubmit=submit;
 $('gm-cancel').onclick=()=>$('gm-dialog').close();

 await load();
})().catch(error=>{
 console.error(error);
 toast(error.message,'warn');
});

})();