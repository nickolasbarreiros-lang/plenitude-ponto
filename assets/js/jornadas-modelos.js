/* RC6.6 — jornadas-modelo: interface administrativa */
(()=>{
 const $=id=>document.getElementById(id);
 const api=async(name,args={})=>{
  const c=window.PlenitudeAuth?.client;
  if(!c)throw Error('Cliente Supabase indisponível.');
  const {data,error}=await c.rpc(name,args);if(error)throw error;return data;
 };
 const days=['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'];
 let models=[],assignments=[],employees=[];
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const message=(s,err=false)=>{if(typeof window.toast==='function')window.toast(s,err?'warn':undefined);else alert(s)};
 const rows=()=>[...document.querySelectorAll('#jornada-body tr')].map((tr,i)=>({dia_semana:i+1,entrada:tr.querySelector('[name=entrada]')?.value||'',almoco:tr.querySelector('[name=almoco]')?.value||'',retorno:tr.querySelector('[name=retorno]')?.value||'',saida:tr.querySelector('[name=saida]')?.value||''}));
 const paint=daysData=>{const trs=[...document.querySelectorAll('#jornada-body tr')];if(trs.length!==7)return false;trs.forEach((tr,i)=>{const d=daysData.find(x=>Number(x.dia_semana)===i+1)||{};for(const key of ['entrada','almoco','retorno','saida'])tr.querySelector(`[name=${key}]`).value=d[key]||'';});if(typeof window.updateTotals==='function')window.updateTotals();return true};
 const reload=async()=>{models=await api('rc66_listar_modelos');assignments=await api('rc66_listar_atribuicoes');employees=(await window.PlenitudeDB.employees()).filter(e=>e.ativo!==false);};
 const options=(selected='')=>'<option value="">Selecione...</option>'+models.map(m=>`<option value="${esc(m.id)}" ${m.id===selected?'selected':''}>${esc(m.nome)}</option>`).join('');
 const latest=id=>assignments.find(a=>a.funcionario_id===id);
 const fill=()=>{
  if($('rc66-modelo'))$('rc66-modelo').innerHTML='<option value="">Nova jornada</option>'+models.map(m=>`<option value="${esc(m.id)}">${esc(m.nome)}</option>`).join('');
  if($('rc66-atribuir-modelo'))$('rc66-atribuir-modelo').innerHTML=options();
  if($('rc66-employee-model'))$('rc66-employee-model').innerHTML=options();
  if($('rc66-funcionario'))$('rc66-funcionario').innerHTML=employees.map(e=>`<option value="${esc(e.id)}">${esc(e.nome)} — ${esc(e.matricula)}</option>`).join('');
 };
 const showEmployee=()=>{
  // Cada página possui seu próprio seletor: nunca utilizar o seletor de outra tela.
  const onRegistration=!!$('rc66-employee-assignment');
  const selector=onRegistration?$('employee-selector'):$('rc66-funcionario');
  const id=selector?.value||'';
  const active=employees.some(e=>e.id===id);
  const a=id?latest(id):null;
  const m=a?models.find(x=>x.id===a.modelo_id):null;
  if($('rc66-employee-status'))$('rc66-employee-status').textContent=m?`Jornada: ${m.nome} • desde ${a.vigencia_inicio}`:'Nenhuma jornada cadastrada';
  if($('rc66-vinculo'))$('rc66-vinculo').textContent=m?`Jornada atual: ${m.nome} • desde ${a.vigencia_inicio}`:'Nenhuma jornada cadastrada';
  if($('rc66-employee-model')){
   $('rc66-employee-model').value=m?.id||'';
   $('rc66-employee-model').disabled=!active;
  }
  if($('rc66-employee-assign')){
   $('rc66-employee-assign').disabled=!active;
   $('rc66-employee-assign').title=active?'':'Funcionários inativos não podem receber novas jornadas';
  }
 };

 const assign=async(id,model)=>{if(!employees.some(e=>e.id===id))throw Error('Selecione um funcionário ativo.');if(!id||!model)throw Error('Selecione funcionário e jornada.');if(!confirm('Aplicar a jornada selecionada ao funcionário a partir de hoje? Os horários atuais serão substituídos.'))return;await api('rc66_atribuir_modelo',{p_funcionario:id,p_modelo:model,p_vigencia:new Date().toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'})});await reload();fill();showEmployee();message('Jornada atribuída. Atualize o painel para conferir os horários.');};
 const safe=fn=>async()=>{try{await fn()}catch(e){console.error(e);message(e.message||String(e),true)}};
 async function start(){
  if($('rc66-panel')){
   const auth=await window.initCommon(['administrador']);if(!auth)return;
   const body=$('jornada-body');
   body.innerHTML=days.map((day,i)=>`<tr><td><strong>${day}</strong></td>${['entrada','almoco','retorno','saida'].map(key=>`<td><input type="time" name="${key}" value=""></td>`).join('')}<td class="total-dia">00:00</td></tr>`).join('');
   body.addEventListener('input',()=>window.updateTotals?.());window.updateTotals?.();
  }
  if(!$('rc66-panel')&&!$('rc66-employee-assignment'))return;
  try{await reload();fill();showEmployee()}catch(e){console.error(e);message('Instale o SQL RC6.6 antes de utilizar jornadas cadastradas: '+e.message,true);return;}
  $('employee-selector')?.addEventListener('change',()=>{showEmployee();setTimeout(showEmployee,0)});
  // Atualiza a visualização quando o cadastro altera o seletor programaticamente.
  if($('rc66-employee-assignment')){const sel=$('employee-selector');if(sel){const observer=new MutationObserver(()=>showEmployee());observer.observe(sel,{childList:true,subtree:true});}}
  $('rc66-funcionario')?.addEventListener('change',showEmployee);
  $('rc66-modelo')?.addEventListener('change',()=>{const m=models.find(x=>x.id===$('rc66-modelo').value);$('rc66-nome').value=m?.nome||'';$('rc66-descricao').value=m?.descricao||'';paint(m?.dias||[])});
  $('rc66-novo')?.addEventListener('click',()=>{$('rc66-modelo').value='';$('rc66-nome').value='';$('rc66-descricao').value='';paint([]);message('Informe o nome e os horários para criar a jornada.');});
  $('rc66-salvar')?.addEventListener('click',safe(async()=>{const id=$('rc66-modelo').value||null;const name=$('rc66-nome').value.trim();if(!name)throw Error('Informe o nome da jornada.');const data=rows();if(data.length!==7)throw Error('Aguarde a tabela carregar.');await api('rc66_salvar_modelo',{p_id:id,p_nome:name,p_descricao:$('rc66-descricao').value,p_dias:data});await reload();fill();message('Jornada-modelo salva.');}));
  $('rc66-atribuir')?.addEventListener('click',safe(()=>assign($('rc66-funcionario').value,$('rc66-atribuir-modelo').value)));
  $('rc66-employee-assign')?.addEventListener('click',safe(()=>assign($('employee-selector').value,$('rc66-employee-model').value)));
 }
 // Aguarda a inicialização do Supabase e a renderização da tabela.
 window.addEventListener('load',()=>setTimeout(start,200));
})();
