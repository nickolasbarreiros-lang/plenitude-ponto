(async function(){
'use strict';
console.info('[Plenitude Ponto] Backup RC4.11 carregado — somente RPC exportar_backup_admin.');
const auth=window.PlenitudeAuth, client=auth?.client;
const ctx=await auth.requireAccess({roles:['administrador']}); if(!ctx||!client) return;
document.getElementById('sair')?.addEventListener('click',()=>auth.signOut());
const $=id=>document.getElementById(id);
const state={data:null,integrity:null};
const isoDate=d=>d.toISOString().slice(0,10);
const localDateTime=v=>v?new Intl.DateTimeFormat('pt-BR',{dateStyle:'short',timeStyle:'medium',timeZone:'America/Sao_Paulo'}).format(new Date(v)):'';
const csvValue=v=>{if(v===null||v===undefined)return '""';if(typeof v==='object')v=JSON.stringify(v);return '"'+String(v).replace(/"/g,'""')+'"'};
const makeCsv=(rows,columns)=>'\ufeff'+[columns.map(c=>csvValue(c.label)).join(';'),...rows.map(r=>columns.map(c=>csvValue(typeof c.value==='function'?c.value(r):r[c.value])).join(';'))].join('\n');
function download(blob,name){const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}
function period(){const start=$('bk-start').value,end=$('bk-end').value;if(!start||!end)throw new Error('Informe as datas inicial e final.');if(start>end)throw new Error('A data inicial não pode ser posterior à final.');return{start,end}}
async function loadData(){
 const {start,end}=period();$('bk-progress').textContent='Consultando o Supabase...';
 const [profile,backupResult]=await Promise.all([
  window.PlenitudeDB.profile(),
  client.rpc('exportar_backup_admin',{p_inicio:start,p_fim:end})
 ]);

 if(backupResult.error){
  console.error('[Backup RC4.11] Falha na RPC exportar_backup_admin:',backupResult.error);
  throw backupResult.error;
 }

 const backup=backupResult.data||{};
 const funcionarios=backup.funcionarios||[];
 const jornadas=backup.jornadas||[];
 const marcacoes=backup.marcacoes||[];
 const ocorrencias=backup.ocorrencias||[];
 const ajustes=backup.ajustes||[];
 const auditoria=backup.auditoria||[];
 const banco=[];
 for(let i=0;i<funcionarios.length;i++){
  const f=funcionarios[i];$('bk-progress').textContent=`Calculando banco de horas (${i+1}/${funcionarios.length})...`;
  try{const result=await window.PlenitudeDB.bankHours(f.id,start,end);banco.push({funcionario_id:f.id,funcionario_nome:f.nome,matricula:f.matricula,...(result.resumo||{})})}
  catch(error){banco.push({funcionario_id:f.id,funcionario_nome:f.nome,matricula:f.matricula,erro:error.message})}
 }
 state.data={versao:'23',sistema:'Plenitude Ponto',periodo:{inicio:start,fim:end},empresa:profile.empresas,perfil:{id:profile.id,nome:profile.nome,email:profile.email,papel:profile.papel},funcionarios,jornadas,marcacoes,ocorrencias,ajustes,auditoria,banco_horas:banco,exportado_em:new Date().toISOString()};
 $('bk-funcionarios').textContent=funcionarios.length;$('bk-marcacoes').textContent=marcacoes.length;$('bk-progress').textContent='Dados atualizados.';
 return state.data;
}
const defs={
 funcionarios:{name:'funcionarios.csv',columns:[['Nome','nome'],['Matrícula','matricula'],['CPF','cpf'],['Cargo','cargo'],['Admissão','data_admissao'],['Status','status'],['Ativo',r=>r.ativo?'Sim':'Não'],['Criado em',r=>localDateTime(r.criado_em)]]},
 jornadas:{name:'jornadas.csv',columns:[['Funcionário ID','funcionario_id'],['Dia da semana','dia_semana'],['Entrada','entrada'],['Início intervalo','inicio_intervalo'],['Fim intervalo','fim_intervalo'],['Saída','saida'],['Ativa',r=>r.ativo?'Sim':'Não']]},
 marcacoes:{name:'marcacoes.csv',columns:[['Funcionário ID','funcionario_id'],['Data','data_local'],['Tipo','tipo'],['Horário servidor',r=>localDateTime(r.registrado_em)],['Origem','origem'],['Ajustada',r=>r.ajustada?'Sim':'Não'],['Observação','observacao']]},
 ocorrencias:{name:'ocorrencias.csv',columns:[['Funcionário ID','funcionario_id'],['Tipo','tipo'],['Início','data_inicio'],['Fim','data_fim'],['Descrição','descricao'],['Aprovada',r=>r.aprovado?'Sim':'Não']]},
 ajustes:{name:'ajustes-de-ponto.csv',columns:[['Funcionário ID','funcionario_id'],['Data','data_marcacao'],['Tipo','tipo_marcacao'],['Horário solicitado','horario_solicitado'],['Justificativa','justificativa'],['Status','status'],['Resposta','resposta_administrador'],['Criado em',r=>localDateTime(r.criado_em)],['Analisado em',r=>localDateTime(r.analisado_em)]]},
 auditoria:{name:'auditoria.csv',columns:[['Data e hora',r=>localDateTime(r.criado_em)],['Usuário ID','usuario_id'],['Ação','acao'],['Tabela','tabela'],['Registro','registro_id'],['Descrição','descricao'],['Origem','origem'],['Dados anteriores','dados_anteriores'],['Dados novos','dados_novos']]},
 banco:{name:'banco-de-horas.csv',columns:[['Funcionário','funcionario_nome'],['Matrícula','matricula'],['Previsto (min)','previsto_minutos'],['Trabalhado (min)','trabalhado_minutos'],['Saldo (min)','saldo_minutos'],['Crédito (min)','credito_minutos'],['Débito (min)','debito_minutos'],['Faltas','faltas'],['Pendências','pendencias'],['Erro','erro']]}
};
for(const [k,d] of Object.entries(defs))d.columns=d.columns.map(([label,value])=>({label,value}));
function rowsFor(k){return k==='banco'?state.data.banco_horas:state.data[k]}
async function ensure(){return state.data||loadData()}
async function exportOne(kind){const data=await ensure();if(kind==='empresa'){download(new Blob([JSON.stringify({empresa:data.empresa,perfil:data.perfil,exportado_em:data.exportado_em},null,2)],{type:'application/json'}),'empresa-configuracoes.json');return}const d=defs[kind];download(new Blob([makeCsv(rowsFor(kind),d.columns)],{type:'text/csv;charset=utf-8'}),d.name)}
function integrity(data){
 const issues=[];const schedulesBy=new Map();data.jornadas.forEach(j=>{if(!schedulesBy.has(j.funcionario_id))schedulesBy.set(j.funcionario_id,[]);schedulesBy.get(j.funcionario_id).push(j)});
 data.funcionarios.filter(f=>f.ativo!==false).forEach(f=>{const rows=schedulesBy.get(f.id)||[];if(!rows.length)issues.push({level:'erro',title:`${f.nome} sem jornada`,detail:'Funcionário ativo não possui jornada semanal cadastrada.'});else if(rows.filter(r=>r.ativo!==false).length<5)issues.push({level:'aviso',title:`Jornada incompleta: ${f.nome}`,detail:`Apenas ${rows.filter(r=>r.ativo!==false).length} dia(s) ativo(s) cadastrado(s).`})});
 const validEmployees=new Set(data.funcionarios.map(f=>f.id));data.marcacoes.filter(m=>!validEmployees.has(m.funcionario_id)).forEach(m=>issues.push({level:'erro',title:'Marcação órfã',detail:`Registro ${m.id} não possui funcionário válido.`}));
 const dayMap=new Map();data.marcacoes.forEach(m=>{const key=`${m.funcionario_id}|${m.data_local}`;if(!dayMap.has(key))dayMap.set(key,[]);dayMap.get(key).push(m)});for(const [key,marks] of dayMap){if(marks.length!==4)issues.push({level:'aviso',title:'Dia com marcações incompletas',detail:`${key.replace('|',' em ')} possui ${marks.length} marcação(ões).`})}
 data.banco_horas.filter(b=>b.erro).forEach(b=>issues.push({level:'erro',title:`Falha no banco de horas: ${b.funcionario_nome}`,detail:b.erro}));
 return issues;
}
function renderIntegrity(issues){state.integrity=issues;$('bk-alertas').textContent=issues.length;const el=$('bk-integrity');el.innerHTML=issues.length?issues.map(i=>`<div class="integrity-item ${i.level}"><span>${i.level==='erro'?'!':'⚠'}</span><div><strong>${i.title}</strong><small>${i.detail}</small></div></div>`).join(''):'<div class="integrity-item ok"><span>✓</span><div><strong>Nenhuma inconsistência encontrada</strong><small>As verificações automáticas do período foram concluídas.</small></div></div>'}
async function fullBackup(){const button=$('bk-completo');button.disabled=true;try{const data=await loadData();const issues=integrity(data);renderIntegrity(issues);$('bk-progress').textContent='Montando arquivo ZIP...';const zip=new JSZip();for(const [k,d] of Object.entries(defs))zip.file(d.name,makeCsv(rowsFor(k),d.columns));zip.file('empresa.json',JSON.stringify({empresa:data.empresa,perfil:data.perfil},null,2));zip.file('backup-completo.json',JSON.stringify(data,null,2));zip.file('integridade.json',JSON.stringify({verificado_em:new Date().toISOString(),quantidade_alertas:issues.length,itens:issues},null,2));zip.file('manifesto.json',JSON.stringify({sistema:data.sistema,versao:data.versao,periodo:data.periodo,exportado_em:data.exportado_em,contagens:{funcionarios:data.funcionarios.length,jornadas:data.jornadas.length,marcacoes:data.marcacoes.length,ocorrencias:data.ocorrencias.length,ajustes:data.ajustes.length,auditoria:data.auditoria.length,banco_horas:data.banco_horas.length}},null,2));const blob=await zip.generateAsync({type:'blob',compression:'DEFLATE',compressionOptions:{level:6}},m=>$('bk-progress').textContent=`Compactando: ${Math.round(m.percent)}%`);download(blob,`backup-plenitude-${data.periodo.inicio}-a-${data.periodo.fim}.zip`);localStorage.setItem('plenitude-ultimo-backup',new Date().toISOString());$('bk-ultima').textContent=new Date().toLocaleDateString('pt-BR');$('bk-progress').textContent='Backup concluído.';await window.PlenitudeDB.recordAuditEvent('BACKUP','Backup completo gerado',{periodo:data.periodo,contagens:{funcionarios:data.funcionarios.length,marcacoes:data.marcacoes.length}})}catch(e){$('bk-progress').textContent=`Erro: ${e.message}`}finally{button.disabled=false}}
$('bk-refresh').onclick=()=>loadData().catch(e=>$('bk-progress').textContent=`Erro: ${e.message}`);$('bk-completo').onclick=fullBackup;$('bk-check').onclick=async()=>{try{renderIntegrity(integrity(await ensure()))}catch(e){$('bk-integrity').innerHTML=`<div class="mini-empty">Erro: ${e.message}</div>`}};
document.querySelectorAll('[data-export]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await exportOne(b.dataset.export)}catch(e){alert(e.message)}finally{b.disabled=false}});
$('bk-import').onchange=async e=>{const file=e.target.files?.[0];if(!file)return;try{const obj=JSON.parse(await file.text());const required=['funcionarios','jornadas','marcacoes','exportado_em'];const missing=required.filter(k=>!(k in obj));if(missing.length)throw new Error(`Estrutura inválida. Campos ausentes: ${missing.join(', ')}`);$('bk-import-result').innerHTML=`<span class="status-dot online"></span> Backup válido: ${obj.funcionarios.length} funcionário(s), ${obj.marcacoes.length} marcação(ões), exportado em ${localDateTime(obj.exportado_em)}. Nenhum dado foi alterado.`}catch(err){$('bk-import-result').textContent=`Arquivo inválido: ${err.message}`}};
const now=new Date(),start=new Date(now.getFullYear(),now.getMonth(),1);$('bk-start').value=isoDate(start);$('bk-end').value=isoDate(now);const last=localStorage.getItem('plenitude-ultimo-backup');$('bk-ultima').textContent=last?new Date(last).toLocaleDateString('pt-BR'):'Nunca';
await loadData().catch(e=>$('bk-progress').textContent=`Erro ao carregar: ${e.message}`);
})();
