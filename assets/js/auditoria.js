(async function(){
'use strict';
const auth=window.PlenitudeAuth, db=window.PlenitudeDB;
const ctx=await auth.requireAccess({roles:['administrador']}); if(!ctx) return;
document.getElementById('sair')?.addEventListener('click',()=>auth.signOut());
const $=id=>document.getElementById(id), body=$('audit-body'), status=$('audit-status');
let page=0, rows=[], pageSize=100;
const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const dt=v=>v?new Intl.DateTimeFormat('pt-BR',{dateStyle:'short',timeStyle:'medium',timeZone:'America/Sao_Paulo'}).format(new Date(v)):'—';
const label=t=>({marcacoes:'Marcações',funcionarios:'Funcionários',jornadas:'Jornadas',ocorrencias:'Ocorrências',empresas:'Empresa',sistema:'Sistema',solicitacoes_ajuste_ponto:'Ajustes'}[t]||t||'—');
function filters(){return{start:$('audit-start').value,end:$('audit-end').value,action:$('audit-action').value,table:$('audit-table').value,query:$('audit-query').value.trim(),limit:pageSize,offset:page*pageSize}}
async function loadSummary(){try{const s=await db.securitySummary();$('audit-24h').textContent=s.eventos_24h||0;$('audit-logins').textContent=s.logins_30d||0;$('audit-changes').textContent=s.alteracoes_30d||0}catch(e){console.warn(e)}}
function render(){
 body.innerHTML=rows.length?rows.map((r,i)=>`<tr><td>${esc(dt(r.criado_em))}</td><td><strong>${esc(r.usuario_nome)}</strong><br><small>${esc(r.usuario_email)}</small></td><td><span class="audit-action-tag ${esc(String(r.acao).toLowerCase())}">${esc(r.acao)}</span></td><td>${esc(label(r.tabela))}</td><td>${esc(r.descricao||r.registro_id||'—')}</td><td>${esc(r.origem||'sistema')}</td><td><button class="btn small outline" data-detail="${i}">Ver</button></td></tr>`).join(''):`<tr><td colspan="7"><div class="empty-state"><strong>Nenhum evento encontrado</strong><span>Altere os filtros e tente novamente.</span></div></td></tr>`;
 status.textContent=`${rows.length} registro(s) nesta página.`;$('audit-page').textContent=`Página ${page+1}`;$('audit-prev').disabled=page===0;$('audit-next').disabled=rows.length<pageSize;
 body.querySelectorAll('[data-detail]').forEach(b=>b.onclick=()=>openDetail(rows[Number(b.dataset.detail)]));
}
async function load(){status.textContent='Consultando auditoria no Supabase...';try{rows=await db.auditLogs(filters());render()}catch(e){status.textContent=`Erro: ${e.message}`;body.innerHTML=''}}
function openDetail(r){$('audit-detail').innerHTML=`<div class="audit-detail-grid"><div><small>Data e hora</small><strong>${esc(dt(r.criado_em))}</strong></div><div><small>Usuário</small><strong>${esc(r.usuario_nome)} · ${esc(r.usuario_email)}</strong></div><div><small>Ação</small><strong>${esc(r.acao)}</strong></div><div><small>Área / registro</small><strong>${esc(label(r.tabela))} · ${esc(r.registro_id||'—')}</strong></div></div><h3>Dados anteriores</h3><pre class="audit-json">${esc(JSON.stringify(r.dados_anteriores,null,2)||'Sem dados anteriores')}</pre><h3>Dados novos</h3><pre class="audit-json">${esc(JSON.stringify(r.dados_novos,null,2)||'Sem dados novos')}</pre><p class="security-note">Este evento usa o horário do servidor Supabase e não o relógio do computador.</p>`;$('audit-dialog').showModal()}
$('audit-close').onclick=()=>$('audit-dialog').close();$('audit-filters').onsubmit=e=>{e.preventDefault();page=0;load()};$('audit-prev').onclick=()=>{if(page){page--;load()}};$('audit-next').onclick=()=>{if(rows.length===pageSize){page++;load()}};
$('audit-export').onclick=()=>{if(!rows.length)return;const cols=['criado_em','usuario_nome','usuario_email','acao','tabela','registro_id','descricao','origem'];const q=v=>'"'+String(v??'').replace(/"/g,'""')+'"';const csv='\ufeff'+[cols.join(';'),...rows.map(r=>cols.map(c=>q(c==='criado_em'?dt(r[c]):r[c])).join(';'))].join('\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));a.download=`auditoria-plenitude-${new Date().toISOString().slice(0,10)}.csv`;a.click();URL.revokeObjectURL(a.href)};
const now=new Date(), start=new Date(now);start.setDate(start.getDate()-30);$('audit-start').value=start.toISOString().slice(0,10);$('audit-end').value=now.toISOString().slice(0,10);
await Promise.all([loadSummary(),load()]);
})();
