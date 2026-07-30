(async function(){
  'use strict';
  const context=await initCommon(['administrador']);if(!context)return;
  const state={rows:[],selected:null};
  const monthInput=document.getElementById('fc-mes');
  const now=new Date();monthInput.value=`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}`;
  const fmtDate=value=>value?new Intl.DateTimeFormat('pt-BR',{dateStyle:'short',timeStyle:'short'}).format(new Date(value)):'—';
  const competence=(y,m)=>new Intl.DateTimeFormat('pt-BR',{month:'long',year:'numeric'}).format(new Date(y,m-1,1));
  const key=(y,m)=>`${y}-${String(m).padStart(2,'0')}`;
  function selectedParts(){const [year,month]=(monthInput.value||'').split('-').map(Number);return{year,month}}
  function rowFor(y,m){return state.rows.find(r=>Number(r.ano)===y&&Number(r.mes)===m)}
  function renderSelected(){
    const {year,month}=selectedParts(),row=rowFor(year,month),box=document.getElementById('fc-selected-status'),button=document.getElementById('fc-fechar');
    if(!year||!month){box.innerHTML='';button.disabled=true;return}
    if(row?.status==='fechado'){
      box.className='closure-current-status closed';box.innerHTML=`<strong>🔒 ${competence(year,month)} está fechada.</strong><span>Para alterar dados, use “Reabrir” no histórico.</span>`;button.disabled=true;
    }else{
      box.className='closure-current-status open';box.innerHTML=`<strong>🔓 ${competence(year,month)} está aberta.</strong><span>O fechamento bloqueará alterações nessa competência.</span>`;button.disabled=false;
    }
  }
  function render(){
    const closed=state.rows.filter(r=>r.status==='fechado').length,reopened=state.rows.filter(r=>r.status==='reaberto').length,current=rowFor(now.getFullYear(),now.getMonth()+1);
    document.getElementById('fc-fechados').textContent=closed;document.getElementById('fc-reabertos').textContent=reopened;
    document.getElementById('fc-atual').textContent=key(now.getFullYear(),now.getMonth()+1);
    document.getElementById('fc-atual-status').textContent=current?.status==='fechado'?'Fechada e protegida':'Aberta para lançamentos';
    const latest=[...state.rows].sort((a,b)=>new Date(b.atualizado_em)-new Date(a.atualizado_em))[0];document.getElementById('fc-ultima').textContent=latest?fmtDate(latest.atualizado_em):'—';
    const body=document.getElementById('fc-body'),empty=document.getElementById('fc-empty');
    body.innerHTML=state.rows.map(r=>`<tr><td><strong>${competence(r.ano,r.mes)}</strong><small>${key(r.ano,r.mes)}</small></td><td><span class="closure-tag ${r.status}">${r.status==='fechado'?'🔒 Fechada':'🔓 Reaberta'}</span></td><td>${r.status==='fechado'?fmtDate(r.fechado_em):fmtDate(r.reaberto_em)}</td><td>${r.status==='fechado'?(r.fechado_por_nome||'Administrador'):(r.reaberto_por_nome||'Administrador')}</td><td>${r.observacao||'—'}</td><td>${r.status==='fechado'?`<button class="btn outline compact" data-reopen="${r.ano}-${r.mes}">Reabrir</button>`:'<button class="btn primary compact" data-close="'+r.ano+'-'+r.mes+'">Fechar novamente</button>'}</td></tr>`).join('');
    empty.style.display=state.rows.length?'none':'block';
    body.querySelectorAll('[data-reopen]').forEach(btn=>btn.onclick=()=>openReopen(...btn.dataset.reopen.split('-').map(Number)));
    body.querySelectorAll('[data-close]').forEach(btn=>btn.onclick=()=>{const [y,m]=btn.dataset.close.split('-').map(Number);monthInput.value=key(y,m);renderSelected();window.scrollTo({top:0,behavior:'smooth'})});
    renderSelected();
  }
  async function load(){
    try{state.rows=await window.PlenitudeDB.monthClosures(now.getFullYear()-5,now.getFullYear()+1);render()}catch(error){toast(errorText(error),'warn');console.error(error)}
  }
  async function closeMonth(){
    const {year,month}=selectedParts(),button=document.getElementById('fc-fechar');if(!year||!month)return;
    if(!confirm(`Fechar ${competence(year,month)}? As alterações desse mês serão bloqueadas.`))return;
    button.disabled=true;
    const masterPin=prompt('Digite o PIN Mestre de 6 números para fechar a competência:')||'';if(!/^\d{6}$/.test(masterPin)){toast('PIN Mestre inválido.','warn');button.disabled=false;return}try{await window.PlenitudeDB.closeMonth(year,month,document.getElementById('fc-observacao').value,masterPin);toast('Competência fechada e protegida.');document.getElementById('fc-observacao').value='';await load()}catch(error){toast(errorText(error),'warn');console.error(error)}finally{renderSelected()}
  }
  function openReopen(year,month){state.selected={year,month};document.getElementById('fc-dialog-title').textContent=`Reabrir ${competence(year,month)}`;document.getElementById('fc-motivo').value='';document.getElementById('fc-dialog').showModal()}
  document.getElementById('fc-dialog').addEventListener('close',async e=>{
    if(e.target.returnValue!=='default'||!state.selected)return;
    const reason=document.getElementById('fc-motivo').value.trim();if(reason.length<5){toast('Informe um motivo com pelo menos 5 caracteres.','warn');return}
    const masterPin=prompt('Digite o PIN Mestre de 6 números para reabrir a competência:')||'';if(!/^\d{6}$/.test(masterPin)){toast('PIN Mestre inválido.','warn');return}try{await window.PlenitudeDB.reopenMonth(state.selected.year,state.selected.month,reason,masterPin);toast('Competência reaberta. A ação foi auditada.');state.selected=null;await load()}catch(error){toast(errorText(error),'warn');console.error(error)}
  });
  document.getElementById('fc-fechar').onclick=closeMonth;document.getElementById('fc-refresh').onclick=load;monthInput.onchange=renderSelected;
  await load();
})();
