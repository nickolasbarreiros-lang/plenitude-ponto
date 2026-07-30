(async function(){
 const auth=window.PlenitudeAuth, client=auth?.client; const ctx=await auth.requireAccess({roles:['administrador']}); if(!ctx||!client)return;
 const status=document.getElementById('status'); document.getElementById('sair').onclick=()=>auth.signOut();
 async function run(fn,confirmText){if(confirmText&&!confirm(confirmText))return; status.textContent='Processando...'; try{const {data,error}=await client.rpc(fn);if(error)throw error;status.textContent=fn.startsWith('criar')?'Funcionário teste pronto. Matrícula 999, PIN 9999.':`Reset concluído. ${data?.registros_removidos||0} registro(s) removido(s).`;}catch(e){alert(e.message);status.textContent='Erro: '+e.message;}}
 document.getElementById('criar').onclick=()=>run('criar_funcionario_homologacao_admin');
 document.getElementById('resetar').onclick=()=>run('resetar_funcionario_homologacao_admin','Apagar todos os registros de teste da matrícula 999? Os dados da Roseli não serão alterados.');

 const scenarios=[
  ['Fluxo do funcionário','Login com matrícula 999 e PIN 9999'],['Fluxo do funcionário','Registrar entrada'],['Fluxo do funcionário','Registrar saída para almoço'],['Fluxo do funcionário','Registrar retorno do almoço'],['Fluxo do funcionário','Registrar saída final'],['Fluxo do funcionário','Confirmar jornada encerrada'],
  ['Movimentação temporária','Registrar saída temporária'],['Movimentação temporária','Registrar retorno temporário'],['Movimentação temporária','Classificar movimentação no painel'],
  ['Ajustes','Solicitar marcação esquecida'],['Ajustes','Aprovar solicitação'],['Ajustes','Rejeitar solicitação'],['Ajustes','Confirmar reflexo no relatório'],
  ['Administração','Criar funcionário'],['Administração','Definir ou alterar PIN'],['Administração','Bloquear e reativar acesso'],['Administração','Autorizar e revogar dispositivo'],['Administração','Gerar backup'],['Administração','Consultar auditoria'],
  ['Relatórios','Conferir saldo diário'],['Relatórios','Conferir saldo semanal'],['Relatórios','Conferir saldo mensal'],['Relatórios','Gerar espelho em PDF'],['Relatórios','Exportar CSV'],
  ['Fechamento','Fechar competência'],['Fechamento','Confirmar bloqueio de alterações'],['Fechamento','Reabrir com motivo e PIN Mestre'],
  ['Segurança','Testar PIN incorreto'],['Segurança','Testar computador não autorizado'],['Segurança','Testar sessão expirada ou logout'],['Resiliência','Testar sem internet e mensagem amigável'],['Resiliência','Testar duas abas abertas']
 ];
 const key='plenitude-homologacao-rc2-1';
 let saved={}; try{saved=JSON.parse(localStorage.getItem(key)||'{}')}catch(_){saved={}};
 const list=document.getElementById('checklist'), text=document.getElementById('checklist-progresso'), bar=document.getElementById('checklist-barra');
 function renderChecklist(){
  list.innerHTML=''; let last='';
  scenarios.forEach(([group,label],i)=>{if(group!==last){const h=document.createElement('h3');h.textContent=group;list.appendChild(h);last=group;}const row=document.createElement('label');row.className='homolog-check';row.innerHTML=`<input type="checkbox" data-i="${i}" ${saved[i]?'checked':''}><span>${label}</span>`;list.appendChild(row);});
  list.querySelectorAll('input').forEach(el=>el.onchange=()=>{saved[el.dataset.i]=el.checked;localStorage.setItem(key,JSON.stringify(saved));updateProgress();}); updateProgress();
 }
 function updateProgress(){const done=scenarios.filter((_,i)=>saved[i]).length;const pct=Math.round(done/scenarios.length*100);text.textContent=`${done} de ${scenarios.length} testes concluídos (${pct}%)`;bar.style.width=pct+'%';}
 document.getElementById('marcar-todos').onclick=()=>{scenarios.forEach((_,i)=>saved[i]=true);localStorage.setItem(key,JSON.stringify(saved));renderChecklist();};
 document.getElementById('limpar-checklist').onclick=()=>{if(confirm('Limpar todo o checklist de homologação deste navegador?')){saved={};localStorage.removeItem(key);renderChecklist();}};
 renderChecklist();

 document.getElementById('diagnosticar').onclick=async()=>{
  const btn=document.getElementById('diagnosticar'), summary=document.getElementById('diagnostico-resumo'), grid=document.getElementById('diagnostico-lista');btn.disabled=true;btn.textContent='Verificando...';summary.textContent='Consultando o Supabase...';grid.innerHTML='';
  try{const {data,error}=await client.rpc('diagnostico_homologacao_admin');if(error)throw error;summary.className='homolog-summary '+(data.status==='aprovado'?'ok':'warn');summary.textContent=`${data.aprovados} de ${data.total} verificações aprovadas. ${data.pendentes?data.pendentes+' item(ns) exigem atenção.':'Instalação técnica aprovada.'}`;(data.checks||[]).forEach(c=>{const el=document.createElement('div');el.className='homolog-diagnostic '+(c.ok?'ok':'fail');el.innerHTML=`<strong>${c.ok?'✓':'!' } ${c.item}</strong><small>${c.grupo}${c.detalhe?' · '+c.detalhe:''}</small>`;grid.appendChild(el);});}
  catch(e){summary.className='homolog-summary fail';summary.textContent='Diagnóstico indisponível: '+e.message;}
  finally{btn.disabled=false;btn.textContent='Executar diagnóstico';}
 };
})();
