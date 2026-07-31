(async function(){'use strict';
 const C={
  consulta_medica:'Consulta médica',atestado:'Atestado/declaração',servico_externo:'Serviço externo',curso:'Curso/treinamento',banco:'Banco/atividade pessoal',particular:'Saída particular',saida_autorizada:'Saída autorizada',compensacao:'Compensação',hora_extra_autorizada:'Hora extra autorizada',home_office:'Home office',outro:'Outro'
 }, E={pendente:'Pendente',descontar:'Descontar',abonar:'Abonar',trabalhado:'Conta como trabalho',credito:'Crédito autorizado'};
 const fmt=v=>v?new Date(v).toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'}):'Aguardando retorno';
 const context=await initCommon(['administrador']);if(!context)return;
 const employees=await PlenitudeDB.employees();
 const opts=employees.map(f=>`<option value="${f.id}">${f.nome} — ${f.matricula||'sem matrícula'}</option>`).join('');
 document.getElementById('mov-funcionario').innerHTML=opts;document.getElementById('mov-filter-employee').insertAdjacentHTML('beforeend',opts);
 document.getElementById('mov-classificacao').innerHTML=Object.entries(C).map(([v,l])=>`<option value="${v}">${l}</option>`).join('');
 const now=new Date(),start=new Date(now.getFullYear(),now.getMonth(),1);const key=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
 document.getElementById('mov-filter-start').value=key(start);document.getElementById('mov-filter-end').value=key(now);
 const dt=d=>{const z=new Date(d.getTime()-d.getTimezoneOffset()*60000);return z.toISOString().slice(0,16)};document.getElementById('mov-inicio').value=dt(now);document.getElementById('mov-fim').value=dt(new Date(now.getTime()+60*60000));
 function localInputValue(value){
  const d=new Date(value);
  const local=new Date(d.getTime()-d.getTimezoneOffset()*60000);
  return local.toISOString().slice(0,16);
 }

 function suggestedReturn(r){
  const start=new Date(r.inicio_em);
  const suggested=new Date(start.getTime()+60*60000);
  const now=new Date();
  return localInputValue(suggested>now?now:suggested);
 }

 function editor(r){
  const isOpen=r.status==='aberta';

  return `<article class="movement-admin-card" data-movement-id="${r.id}">
   <div class="movement-card-head">
    <div>
     <small>${r.funcionario_nome} · ${r.matricula||'sem matrícula'}</small>
     <h3>${fmt(r.inicio_em)} → ${fmt(r.fim_em)}</h3>
     <p>${r.motivo_informado||'Sem motivo informado'}</p>
    </div>
    <span class="request-status ${isOpen?'pendente':r.status==='cancelada'?'rejeitada':r.aprovado?'aprovada':'pendente'}">
     ${isOpen?'aguardando retorno':r.status==='cancelada'?'arquivada':r.aprovado?'analisada':'aguardando análise'}
    </span>
   </div>

   ${isOpen?`
    <div class="movement-resolution">
     <div class="notice compact">
      O funcionário não registrou o retorno. Informe o horário correto ou arquive o lançamento se ele for indevido.
     </div>

     <div class="movement-resolution-grid">
      <label>
       Horário correto do retorno
       <input data-return-time type="datetime-local" value="${suggestedReturn(r)}" min="${localInputValue(r.inicio_em)}">
      </label>

      <label class="wide">
       Observação administrativa
       <textarea data-return-note maxlength="500" placeholder="Ex.: Funcionário confirmou retorno às 16:10."></textarea>
      </label>
     </div>

     <div class="movement-resolution-actions">
      <button class="btn primary" data-register-return="${r.id}">Registrar retorno manual</button>
      <button class="btn outline danger" data-archive="${r.id}">Arquivar ocorrência</button>
     </div>
    </div>`
    :r.status==='cancelada'
      ?`<div class="admin-response"><b>Arquivada:</b> ${r.observacao_admin||'Sem observação.'}</div>`
      :`<div class="movement-review-grid">
       <label>Classificação
        <select data-class>
         ${Object.entries(C).map(([v,l])=>`<option value="${v}" ${r.classificacao===v?'selected':''}>${l}</option>`).join('')}
        </select>
       </label>
       <label>Efeito
        <select data-effect>
         ${Object.entries(E).filter(([v])=>v!=='pendente').map(([v,l])=>`<option value="${v}" ${r.efeito_calculo===v?'selected':''}>${l}</option>`).join('')}
        </select>
       </label>
       <label class="wide">Observação
        <textarea data-note>${r.observacao_admin||''}</textarea>
       </label>
       <button class="btn primary" data-save="${r.id}">Salvar análise</button>
      </div>`}
  </article>`;
 }
 async function load(){
  const box=document.getElementById('movement-admin-list');
  box.innerHTML='<div class="mini-empty">Carregando...</div>';

  try{
   const rows=await PlenitudeDB.adminMovements(
    document.getElementById('mov-filter-start').value,
    document.getElementById('mov-filter-end').value,
    document.getElementById('mov-filter-employee').value||null,
    document.getElementById('mov-filter-pending').checked
   );

   document.getElementById('movement-pending-count').textContent=
    `${rows.filter(r=>r.status==='aberta'||r.efeito_calculo==='pendente').length} pendentes`;

   box.innerHTML=rows.map(editor).join('');
   document.getElementById('movement-admin-empty').hidden=rows.length>0;

   box.querySelectorAll('[data-save]').forEach(button=>{
    button.onclick=async()=>{
     const card=button.closest('.movement-admin-card');
     button.disabled=true;
     try{
      await PlenitudeDB.analyzeMovement(
       button.dataset.save,
       card.querySelector('[data-class]').value,
       card.querySelector('[data-effect]').value,
       card.querySelector('[data-note]').value
      );
      toast('Movimentação analisada com sucesso.');
      await load();
     }catch(error){
      toast(errorText(error),'warn');
     }finally{
      button.disabled=false;
     }
    };
   });

   box.querySelectorAll('[data-register-return]').forEach(button=>{
    button.onclick=async()=>{
     const card=button.closest('.movement-admin-card');
     const timeInput=card.querySelector('[data-return-time]');
     const note=card.querySelector('[data-return-note]').value.trim();

     if(!timeInput.value){
      timeInput.focus();
      return toast('Informe o horário correto do retorno.','warn');
     }

     if(!confirm('Registrar manualmente este retorno? A ação ficará gravada na auditoria.'))return;

     card.querySelectorAll('button,input,textarea').forEach(el=>el.disabled=true);
     button.textContent='Registrando...';

     try{
      await PlenitudeDB.regularizeMovementReturn(
       button.dataset.registerReturn,
       new Date(timeInput.value).toISOString(),
       note
      );
      toast('Retorno regularizado. Agora classifique o efeito da movimentação.');
      await load();
     }catch(error){
      toast(errorText(error),'warn');
      card.querySelectorAll('button,input,textarea').forEach(el=>el.disabled=false);
      button.textContent='Registrar retorno manual';
     }
    };
   });

   box.querySelectorAll('[data-archive]').forEach(button=>{
    button.onclick=async()=>{
     const reason=prompt(
      'Informe por que esta ocorrência deve ser arquivada:',
      'Registro de teste ou lançamento indevido.'
     );
     if(reason===null)return;
     if(reason.trim().length<5)return toast('Informe um motivo para arquivar.','warn');

     if(!confirm('Arquivar esta ocorrência? Ela deixará de aparecer como pendência.'))return;

     button.disabled=true;
     try{
      await PlenitudeDB.archiveMovement(button.dataset.archive,reason.trim());
      toast('Ocorrência arquivada e registrada na auditoria.');
      await load();
     }catch(error){
      toast(errorText(error),'warn');
     }finally{
      button.disabled=false;
     }
    };
   });
  }catch(error){
   box.innerHTML='';
   toast(errorText(error),'warn');
  }
 }
 document.getElementById('mov-refresh').onclick=load;
 document.getElementById('movement-create-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const start=new Date(document.getElementById('mov-inicio').value),end=new Date(document.getElementById('mov-fim').value);await PlenitudeDB.createAdminMovement(document.getElementById('mov-funcionario').value,start.toISOString(),end.toISOString(),document.getElementById('mov-classificacao').value,document.getElementById('mov-efeito').value,document.getElementById('mov-observacao').value);toast('Lançamento criado com sucesso.');await load()}catch(err){toast(errorText(err),'warn')}finally{b.disabled=false}};
 await load();
})();