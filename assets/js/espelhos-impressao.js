(async function(){
 'use strict';

 const context=await initCommon(['administrador']);
 if(!context)return;

 const params=new URLSearchParams(location.search);
 const selected=params.get('mes');
 const requestedEmployee=params.get('funcionario');
 const printAll=params.get('todos')==='1';

 if(!/^\d{4}-\d{2}$/.test(selected||'')){
  toast('Competência inválida.','warn');
  return;
 }

 const [year,month]=selected.split('-').map(Number);
 const lastDay=new Date(year,month,0).getDate();
 const start=`${selected}-01`;
 const end=`${selected}-${String(lastDay).padStart(2,'0')}`;

 const competenceLabel=new Intl.DateTimeFormat('pt-BR',{
  month:'long',
  year:'numeric'
 }).format(new Date(year,month-1,1));

 const root=document.getElementById('mirror-print-root');
 const printButton=document.getElementById('batch-print');

 document.getElementById('batch-back').onclick=()=>history.back();
 printButton.onclick=()=>window.print();

 function statusLabel(status){
  return ({
   completo:'Completo',
   falta:'Falta',
   pendente:'Pendente',
   aguardando:'Aguardando',
   futuro:'Futuro',
   sem_jornada:'Sem jornada',
   extra:'Hora extra',
   folga:'Folga',
   ferias:'Férias',
   feriado:'Feriado',
   atestado:'Atestado'
  })[status]||status||'—';
 }

 function safe(value){
  return String(value??'')
   .replace(/&/g,'&amp;')
   .replace(/</g,'&lt;')
   .replace(/>/g,'&gt;')
   .replace(/"/g,'&quot;');
 }

 function mirrorPage(employee,company,result,index,total){
  const summary=result.resumo||{};
  const days=(result.dias||[]).filter(day=>
   day.previsto_minutos>0||
   day.quantidade_marcacoes>0||
   day.ocorrencia
  );

  const rows=days.map(day=>{
   const marks=(day.marcacoes||[]).map(value=>formatDbTime(value));
   const balance=
    day.saldo_minutos===null||day.saldo_minutos===undefined
     ?'—'
     :signedMinutes(day.saldo_minutos);

   return `<tr>
    <td>${new Intl.DateTimeFormat('pt-BR',{
      weekday:'short',
      day:'2-digit',
      month:'2-digit'
     }).format(dateFromKey(day.data))}</td>
    ${[0,1,2,3].map(i=>`<td>${marks[i]||'—'}</td>`).join('')}
    <td>${fmtMinutes(day.previsto_minutos||0)}</td>
    <td>${fmtMinutes(day.trabalhado_minutos||0)}</td>
    <td>${balance}</td>
    <td>${safe(statusLabel(day.status))}</td>
   </tr>`;
  }).join('');

  const densityClass=
   days.length>=29
    ?' mirror-density-max'
    :days.length>=24
      ?' mirror-density-compact'
      :'';

  return `<section class="mirror-print-page${densityClass}">
   <header class="time-sheet-header">
    <img src="assets/img/logo-plenitude.png" alt="Plenitude">
    <div>
     <p>ESPELHO DE PONTO MENSAL</p>
     <h2>${safe(company.nome_fantasia||company.razao_social||'Livraria Plenitude')}</h2>
     <span>${safe([company.endereco,company.cidade,company.uf].filter(Boolean).join(' - ')||'—')}</span>
    </div>
    <div class="time-sheet-period">
     <small>Competência</small>
     <strong>${safe(competenceLabel)}</strong>
     <small>Documento</small>
     <strong>${index+1} de ${total}</strong>
    </div>
   </header>

   <div class="time-sheet-identification">
    <div><small>Funcionário</small><strong>${safe(employee.nome||'—')}</strong></div>
    <div><small>Matrícula</small><strong>${safe(employee.matricula||'—')}</strong></div>
    <div><small>Cargo</small><strong>${safe(employee.cargo||'—')}</strong></div>
    <div><small>Admissão</small><strong>${employee.data_admissao
      ?new Intl.DateTimeFormat('pt-BR').format(dateFromKey(employee.data_admissao))
      :'—'}</strong></div>
   </div>

   <div class="mirror-print-summary">
    <div><span>Dias trabalhados</span><strong>${summary.dias_trabalhados||0}</strong></div>
    <div><span>Horas previstas</span><strong>${fmtMinutes(summary.previsto_minutos||0)}</strong></div>
    <div><span>Horas trabalhadas</span><strong>${fmtMinutes(summary.trabalhado_minutos||0)}</strong></div>
    <div><span>Saldo</span><strong>${signedMinutes(summary.saldo_minutos||0)}</strong></div>
    <div><span>Créditos</span><strong>+${fmtMinutes(summary.credito_minutos||0)}</strong></div>
    <div><span>Débitos</span><strong>-${fmtMinutes(summary.debito_minutos||0)}</strong></div>
   </div>

   <table class="mirror-print-table">
    <thead>
     <tr>
      <th>Data</th>
      <th>Entrada</th>
      <th>Almoço</th>
      <th>Retorno</th>
      <th>Saída</th>
      <th>Previsto</th>
      <th>Trabalhado</th>
      <th>Saldo</th>
      <th>Status</th>
     </tr>
    </thead>
    <tbody>${rows||'<tr><td colspan="9">Nenhuma jornada no período.</td></tr>'}</tbody>
   </table>

   <footer class="mirror-paper-signatures">
    <p>Declaro que conferi as marcações e os totais apresentados neste espelho de ponto.</p>
    <div>
     <section>
      <span></span>
      <strong>Assinatura do funcionário</strong>
      <small>Data: ____/____/________</small>
     </section>
     <section>
      <span></span>
      <strong>Assinatura da empresa</strong>
      <small>Data: ____/____/________</small>
     </section>
    </div>
   </footer>
  </section>`;
 }

 try{
  const [employees,profile]=await Promise.all([
   window.PlenitudeDB.employees(),
   window.PlenitudeDB.profile()
  ]);

  let selectedEmployees=employees.filter(item=>item.ativo!==false);

  if(requestedEmployee&&!printAll){
   selectedEmployees=selectedEmployees.filter(item=>item.id===requestedEmployee);
  }

  if(!selectedEmployees.length){
   root.innerHTML='<div class="panel mini-empty">Nenhum funcionário encontrado.</div>';
   return;
  }

  document.getElementById('batch-title').textContent=
   requestedEmployee&&!printAll
    ?`Espelho de ${selectedEmployees[0].nome}`
    :`Espelhos de ${competenceLabel}`;

  document.getElementById('batch-subtitle').textContent=
   `${selectedEmployees.length} documento(s) preparado(s) para impressão.`;

  const company=profile?.empresas||{};
  const pages=[];

  for(let index=0;index<selectedEmployees.length;index++){
   const employee=selectedEmployees[index];

   document.getElementById('batch-subtitle').textContent=
    `Gerando ${index+1} de ${selectedEmployees.length}: ${employee.nome}`;

   const result=await window.PlenitudeDB.bankHours(
    employee.id,
    start,
    end
   );

   pages.push(
    mirrorPage(
     employee,
     company,
     result,
     index,
     selectedEmployees.length
    )
   );
  }

  root.innerHTML=pages.join('');
  document.getElementById('batch-subtitle').textContent=
   `${selectedEmployees.length} documento(s) pronto(s). Use Imprimir / Salvar PDF.`;
  printButton.disabled=false;
 }catch(error){
  root.innerHTML='<div class="panel mini-empty">Não foi possível gerar os espelhos.</div>';
  toast(errorText(error),'warn');
  console.error(error);
 }
})();