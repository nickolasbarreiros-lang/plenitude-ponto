const defaultSchedule=[
  {dia:'Segunda',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'19:00'},
  {dia:'Terça',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'19:00'},
  {dia:'Quarta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'18:00'},
  {dia:'Quinta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'18:30'},
  {dia:'Sexta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'17:00'}
];
const punchLabels=['Entrada','Início do almoço','Retorno do almoço','Saída'];
const STORAGE={theme:'plenitudeTheme'};
let DB_STATE={profile:null,employees:[],employee:null,schedule:[]};
const dayNames=['Segunda','Terça','Quarta','Quinta','Sexta'];
function dbScheduleToUi(rows){const byDay=new Map((rows||[]).map(r=>[r.dia_semana,r]));return dayNames.map((dia,i)=>{const r=byDay.get(i+1);return r?{dia,entrada:r.entrada?.slice(0,5)||'',almoco:r.inicio_intervalo?.slice(0,5)||'',retorno:r.fim_intervalo?.slice(0,5)||'',saida:r.saida?.slice(0,5)||''}:defaultSchedule[i]});}
function errorText(error){const m=String(error?.message||error||'');if(m.includes('duplicate key'))return 'Já existe um cadastro com este CPF ou matrícula.';if(m.includes('row-level security'))return 'Seu usuário não tem permissão para esta operação.';if(m.includes('Failed to fetch'))return 'Não foi possível conectar ao banco de dados.';return m||'Ocorreu um erro inesperado.';}


async function requireAuth(roles=null){return window.PlenitudeAuth.requireAccess({roles})}
function localDateKey(d=new Date()){return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function minutes(a,b){if(!a||!b)return 0;const [h1,m1]=a.split(':').map(Number),[h2,m2]=b.split(':').map(Number);return(h2*60+m2)-(h1*60+m1)}
function totalDay(s){return s?minutes(s.entrada,s.almoco)+minutes(s.retorno,s.saida):0}
function fmtMinutes(value){const n=Math.max(0,Math.round(value||0)),h=Math.floor(n/60),m=n%60;return`${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`}
function signedMinutes(value){return`${value>=0?'+':'−'}${fmtMinutes(Math.abs(value))}`}
function dateFromKey(k){const [y,m,d]=k.split('-').map(Number);return new Date(y,m-1,d)}
function calcPunchDay(p,s){
  if(!p||p.length<4)return null;
  const worked=minutes(p[0],p[1])+minutes(p[2],p[3]);
  const expected=s?totalDay(s):0;
  return{worked,expected,diff:worked-expected,scheduled:!!s};
}
function toast(message,type='ok'){let box=document.querySelector('.toast');if(!box){box=document.createElement('div');box.className='toast';document.body.appendChild(box)}box.className=`toast show ${type}`;box.textContent=message;clearTimeout(box._timer);box._timer=setTimeout(()=>box.classList.remove('show'),2600)}
function applyTheme(theme){document.documentElement.dataset.theme=theme;localStorage.setItem(STORAGE.theme,theme);const btn=document.getElementById('theme-toggle');if(btn)btn.textContent=theme==='dark'?'☀':'◐'}
async function initCommon(roles=null){const context=await requireAuth(roles);if(!context)return null;const session=context.session;const theme=localStorage.getItem(STORAGE.theme)||'light';applyTheme(theme);const logout=document.getElementById('sair');if(logout)logout.onclick=async()=>{logout.disabled=true;try{await window.PlenitudeAuth.signOut()}catch(error){logout.disabled=false;toast('Não foi possível sair do sistema.','warn')}};if(!document.getElementById('theme-toggle')){const b=document.createElement('button');b.id='theme-toggle';b.className='theme-toggle';b.type='button';b.title='Alternar tema';b.onclick=()=>applyTheme(document.documentElement.dataset.theme==='dark'?'light':'dark');document.body.appendChild(b)} return context; }

function initDashboardShortcuts(){
  document.querySelectorAll('.dashboard-shortcut[data-href]').forEach(card=>{
    const open=()=>{
      if(card.classList.contains('is-opening'))return;
      card.classList.add('is-opening');
      window.location.href=card.dataset.href;
    };
    card.addEventListener('click',open);
    card.addEventListener('keydown',event=>{
      if(event.key==='Enter'||event.key===' '){
        event.preventDefault();
        open();
      }
    });
  });
}

async function initAdmin(){
  const context=await initCommon(['administrador']);if(!context)return;
  const session=context.session;
  initDashboardShortcuts();

  try{
    const profile=await window.PlenitudeDB.profile();
    const employees=profile.papel==='administrador'?await window.PlenitudeDB.employees():[];
    const activeEmployees=employees.filter(f=>f.ativo!==false&&f.status!=='inativo');

    DB_STATE.profile=profile;
    DB_STATE.employees=employees;

    const savedEmployeeId=localStorage.getItem('plenitude-dashboard-employee');
    DB_STATE.employee=activeEmployees.find(e=>e.id===savedEmployeeId)||activeEmployees[0]||null;

    document.getElementById('saudacao-admin').textContent=profile.nome||session.user.email||'Administrador';
    document.getElementById('data-atual').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(new Date());
    document.getElementById('total-func').textContent=String(activeEmployees.length);

    const today=localDateKey();
    const allTodayMarks=await window.PlenitudeDB.marksForRange(today,today);
    const tolerance=Number(profile.tolerancia_entrada_minutos||15);

    let presentCount=0,lunchCount=0,lateCount=0;
    for(const employee of activeEmployees){
      const employeeMarks=allTodayMarks
        .filter(m=>m.funcionario_id===employee.id)
        .sort((a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em));

      if(employeeMarks.length)presentCount++;
      if(employeeMarks.length===2)lunchCount++;

      if(employeeMarks.length){
        try{
          const rows=await window.PlenitudeDB.schedules(employee.id);
          const schedule=dbScheduleToUi(rows);
          const planned=scheduleForDateFrom(schedule,new Date());
          if(planned?.entrada){
            const actual=new Date(employeeMarks[0].registrado_em);
            const [h,m]=planned.entrada.split(':').map(Number);
            const plannedDate=new Date(actual);
            plannedDate.setHours(h,m,0,0);
            if((actual-plannedDate)/60000>tolerance)lateCount++;
          }
        }catch(error){
          console.warn('Não foi possível calcular atraso de',employee.nome,error);
        }
      }
    }

    document.getElementById('presentes-hoje').textContent=String(presentCount);
    document.getElementById('em-almoco').textContent=String(lunchCount);
    document.getElementById('ausentes-hoje').textContent=String(Math.max(0,activeEmployees.length-presentCount));
    document.getElementById('atrasos-hoje').textContent=String(lateCount);

    const select=document.getElementById('dashboard-employee-global');
    select.innerHTML=activeEmployees.map(employee=>
      `<option value="${employee.id}" ${DB_STATE.employee?.id===employee.id?'selected':''}>${employee.nome}</option>`
    ).join('');

    select.onchange=async()=>{
      DB_STATE.employee=activeEmployees.find(employee=>employee.id===select.value)||null;
      if(DB_STATE.employee)localStorage.setItem('plenitude-dashboard-employee',DB_STATE.employee.id);
      await refreshSelectedEmployeeDashboard();
    };

    await renderSmartDashboard(activeEmployees,lateCount,tolerance);
    await refreshSelectedEmployeeDashboard();
  }catch(error){
    toast(errorText(error),'warn');
    console.error(error);
  }
}

async function refreshSelectedEmployeeDashboard(){
  const employee=DB_STATE.employee;
  const today=localDateKey();
  const timeline=document.getElementById('marcacoes-hoje');
  const indicators=document.getElementById('daily-indicators');

  if(!employee){
    document.getElementById('analysis-matricula').textContent='—';
    document.getElementById('analysis-cargo').textContent='—';
    document.getElementById('analysis-status').textContent='Nenhum funcionário';
    timeline.classList.add('empty');
    timeline.innerHTML='<div class="empty-state"><div class="icon">👤</div><strong>Nenhum funcionário selecionado</strong><span>Cadastre ou ative um funcionário.</span></div>';
    document.getElementById('resumo-jornada').innerHTML='<div class="mini-empty">Nenhum funcionário disponível.</div>';
    document.getElementById('grafico-semana').innerHTML='';
    document.getElementById('grafico-mensal').innerHTML='';
    document.getElementById('saldo-mes').textContent='+00:00';
    if(indicators)indicators.innerHTML='';
    return;
  }

  const selectedId=employee.id;
  document.getElementById('analysis-matricula').textContent=employee.matricula||'—';
  document.getElementById('analysis-cargo').textContent=employee.cargo||'Não informado';
  document.getElementById('analysis-status').textContent=employee.ativo===false?'Inativo':'Ativo';

  const reportQuery=`?funcionario=${encodeURIComponent(selectedId)}`;
  const weekLink=document.getElementById('week-report-link');
  const monthLink=document.getElementById('month-report-link');
  const scheduleLink=document.getElementById('schedule-edit-link');
  if(weekLink)weekLink.href=`relatorios.html${reportQuery}`;
  if(monthLink)monthLink.href=`relatorios.html${reportQuery}`;
  if(scheduleLink)scheduleLink.href=`jornada.html${reportQuery}`;

  const scheduleRows=await window.PlenitudeDB.schedules(selectedId);
  if(DB_STATE.employee?.id!==selectedId)return;
  const selectedSchedule=dbScheduleToUi(scheduleRows);
  DB_STATE.schedule=selectedSchedule;

  // A consulta é refeita em cada troca para não reutilizar dados antigos do painel.
  const todayMarks=(await window.PlenitudeDB.marksForRange(today,today))
    .filter(mark=>mark.funcionario_id===selectedId)
    .sort((a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em));

  if(DB_STATE.employee?.id!==selectedId)return;

  const times=todayMarks.map(mark=>
    new Date(mark.registrado_em).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})
  );

  if(times.length){
    timeline.classList.remove('empty');
    timeline.innerHTML=times.map((time,index)=>`
      <div class="timeline-item">
        <span><i>${index+1}</i>${punchLabels[index]||'Marcação'}</span>
        <strong>${time}</strong>
      </div>`).join('');
  }else{
    timeline.classList.add('empty');
    timeline.innerHTML='<div class="empty-state"><div class="icon">🕘</div><strong>Nenhuma marcação registrada hoje</strong><span>Existem dados históricos nos gráficos abaixo quando houver registros em outras datas.</span></div>';
  }

  const max=Math.max(...selectedSchedule.map(totalDay),1);
  document.getElementById('resumo-jornada').innerHTML=selectedSchedule.map(item=>`
    <div class="schedule-row-v4">
      <span class="schedule-day">${item.dia.slice(0,3)}</span>
      <div class="schedule-line"><span style="width:${Math.max(34,Math.round(totalDay(item)/max*100))}%"></span></div>
      <strong class="schedule-time">${item.entrada}–${item.saida}</strong>
      <small class="schedule-break">Intervalo ${item.almoco}–${item.retorno}</small>
    </div>`).join('');

  const plannedToday=scheduleForDateFrom(selectedSchedule,new Date());
  const next=times.length<4?punchLabels[times.length]:'Concluído';

  // Busca o registro histórico mais recente para diferenciar "hoje vazio" de "sem dados".
  const lookbackStart=new Date();
  lookbackStart.setDate(lookbackStart.getDate()-30);
  const recentMarks=(await window.PlenitudeDB.marksForRange(localDateKey(lookbackStart),today))
    .filter(mark=>mark.funcionario_id===selectedId)
    .sort((a,b)=>new Date(b.registrado_em)-new Date(a.registrado_em));
  const latestHistorical=recentMarks[0]||null;
  const latestHistoricalText=latestHistorical
    ? `${new Date(latestHistorical.registrado_em).toLocaleDateString('pt-BR')} ${new Date(latestHistorical.registrado_em).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}`
    : '—';

  if(indicators)indicators.innerHTML=`
    <article><span>Entrada prevista hoje</span><strong>${plannedToday?.entrada||'Sem jornada'}</strong></article>
    <article><span>Última marcação hoje</span><strong>${times.at(-1)||'—'}</strong></article>
    <article><span>Próxima etapa hoje</span><strong>${times.length?next:'Entrada'}</strong></article>
    <article><span>Último registro em 30 dias</span><strong>${latestHistoricalText}</strong></article>`;

  const monthStart=`${today.slice(0,7)}-01`;
  const monthEnd=new Date(new Date().getFullYear(),new Date().getMonth()+1,0);
  let monthBalance=0;
  try{
    const bank=await window.PlenitudeDB.bankHours(selectedId,monthStart,localDateKey(monthEnd));
    monthBalance=Number(bank?.resumo?.saldo_minutos||0);
  }catch(error){
    console.warn('Saldo mensal indisponível',error);
  }
  if(DB_STATE.employee?.id!==selectedId)return;
  document.getElementById('saldo-mes').textContent=signedMinutes(monthBalance);

  await Promise.all([
    renderWeekChartDB(selectedId,selectedSchedule),
    renderMonthOverview(employee)
  ]);
}

async function renderSmartDashboard(activeEmployees,lateCount,tolerance){

  let pending=[];
  try{pending=await window.PlenitudeDB.adminAdjustmentRequests('pendente')}catch(e){console.warn('Ajustes pendentes indisponíveis',e)}
  const pendingCount=pending.length;
  const pendingEl=document.getElementById('ajustes-pendentes');if(pendingEl)pendingEl.textContent=String(pendingCount);
  const notes=[];
  if(pendingCount)notes.push({type:'warn',icon:'✓',title:`${pendingCount} ajuste${pendingCount===1?'':'s'} pendente${pendingCount===1?'':'s'}`,text:'Solicitações aguardando aprovação ou rejeição.',href:'ajustes.html?status=pendente&fila=1',label:'Analisar'});
  if(lateCount)notes.push({type:'danger',icon:'⏱',title:`${lateCount} atraso${lateCount===1?'':'s'} hoje`,text:`Entrada após a tolerância configurada de ${tolerance} minutos.`,href:'relatorios.html',label:'Detalhes'});
  const absent=activeEmployees.filter(e=>{const n=document.getElementById('ausentes-hoje');return Number(n?.textContent||0)>0}).length?Number(document.getElementById('ausentes-hoje')?.textContent||0):0;
  if(absent)notes.push({type:'warn',icon:'○',title:`${absent} ausência${absent===1?'':'s'} hoje`,text:'Funcionários ativos ainda sem registro de entrada.',href:'ponto.html',label:'Ver ponto'});
  if(!notes.length)notes.push({type:'ok',icon:'●',title:'Tudo em ordem',text:'Nenhuma pendência operacional identificada neste momento.',href:'relatorios.html',label:'Relatórios'});
  const box=document.getElementById('dashboard-notifications');
  if(box)box.innerHTML=notes.map(n=>`<article class="dashboard-note ${n.type}"><span class="note-icon">${n.icon}</span><div><strong>${n.title}</strong><small>${n.text}</small></div><a href="${n.href}">${n.label}</a></article>`).join('');
  const count=document.getElementById('notification-count');if(count)count.textContent=String(notes.filter(n=>n.type!=='ok').length);
}

async function renderMonthOverview(employee){
  const el=document.getElementById('grafico-mensal');if(!el)return;
  if(!employee){
    el.innerHTML='<div class="dashboard-empty-note">Cadastre um funcionário para visualizar o gráfico.</div>';
    return;
  }

  const employeeId=employee.id;
  const end=new Date(),start=new Date(end);
  start.setDate(end.getDate()-29);

  const [marks,scheduleRows]=await Promise.all([
    window.PlenitudeDB.marksForRange(localDateKey(start),localDateKey(end)),
    window.PlenitudeDB.schedules(employeeId)
  ]);

  const employeeMarks=marks.filter(mark=>mark.funcionario_id===employeeId);
  const schedule=dbScheduleToUi(scheduleRows);
  const days=[];
  let max=1;

  for(let i=0;i<30;i++){
    const date=new Date(start);
    date.setDate(start.getDate()+i);
    const key=localDateKey(date);
    const planned=scheduleForDateFrom(schedule,date);

    const dayMarks=employeeMarks
      .filter(mark=>mark.data_local===key)
      .sort((a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em));

    const punchTimes=dayMarks.map(mark=>
      new Date(mark.registrado_em).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})
    );

    const calculation=calcPunchDay(punchTimes,planned);
    const worked=calculation?.worked||0;
    const expected=planned?totalDay(planned):0;

    max=Math.max(max,worked,expected);

    days.push({
      date,
      worked,
      expected,
      scheduled:!!planned,
      count:punchTimes.length,
      absence:!!planned&&!punchTimes.length&&key<localDateKey(),
      partial:punchTimes.length>0&&punchTimes.length<4,
      extraDay:!planned&&punchTimes.length>=4
    });
  }

  el.innerHTML=days.map(day=>{
    let title;

    if(day.partial){
      title=`${day.date.toLocaleDateString('pt-BR')}: ${day.count} de 4 marcações — jornada incompleta`;
    }else if(day.extraDay){
      title=`${day.date.toLocaleDateString('pt-BR')}: ${fmtMinutes(day.worked)} trabalhadas em dia sem jornada prevista`;
    }else{
      title=`${day.date.toLocaleDateString('pt-BR')}: ${fmtMinutes(day.worked)} trabalhadas / ${fmtMinutes(day.expected)} previstas`;
    }

    const workedHeight=day.partial
      ? Math.max(12,day.count*18)
      : day.worked>0
        ? Math.max(8,Math.round(day.worked/max*100))
        : 2;

    const expectedHeight=day.expected>0
      ? Math.max(2,Math.round(day.expected/max*100))
      : 0;

    return `<div class="month-day
      ${day.date.getDay()===0||day.date.getDay()===6?'is-weekend':''}
      ${day.absence?'is-absence':''}
      ${day.partial?'is-partial':''}
      ${day.extraDay?'is-extra-day':''}"
      title="${title}">
      <div class="month-bars">
        <b style="height:${expectedHeight}%"></b>
        <i style="height:${workedHeight}%"></i>
      </div>
      <small>${String(day.date.getDate()).padStart(2,'0')}</small>
    </div>`;
  }).join('');
}
function scheduleForDateFrom(schedule,d){const map={1:0,2:1,3:2,4:3,5:4};const i=map[d.getDay()];return i===undefined?null:schedule[i]}
async function renderWeekChartDB(employeeId=DB_STATE.employee?.id,schedule=DB_STATE.schedule){
  const el=document.getElementById('grafico-semana');if(!el)return;
  if(!employeeId){
    el.innerHTML='<div class="dashboard-empty-note">Selecione um funcionário.</div>';
    return;
  }

  const now=new Date(),monday=new Date(now),delta=(now.getDay()+6)%7;
  monday.setDate(now.getDate()-delta);
  const sunday=new Date(monday);
  sunday.setDate(monday.getDate()+6);

  const marks=(await window.PlenitudeDB.marksForRange(localDateKey(monday),localDateKey(sunday)))
    .filter(mark=>mark.funcionario_id===employeeId);

  const names=['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'];
  const days=[];
  let max=1;

  for(let i=0;i<7;i++){
    const date=new Date(monday);
    date.setDate(monday.getDate()+i);
    const planned=scheduleForDateFrom(schedule,date);

    const dayMarks=marks
      .filter(mark=>mark.data_local===localDateKey(date))
      .sort((a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em));

    const punchTimes=dayMarks.map(mark=>
      new Date(mark.registrado_em).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})
    );

    const calculation=calcPunchDay(punchTimes,planned);
    const worked=calculation?.worked||0;
    const expected=planned?totalDay(planned):0;
    max=Math.max(max,worked,expected);

    days.push({
      date,
      worked,
      expected,
      scheduled:!!planned,
      count:punchTimes.length,
      first:punchTimes[0]||null,
      complete:punchTimes.length>=4,
      extraDay:!planned&&punchTimes.length>=4,
      isToday:localDateKey(date)===localDateKey()
    });
  }

  el.innerHTML=days.map((day,index)=>{
    let value='—';
    let subtitle=day.scheduled?`Previsto ${fmtMinutes(day.expected)}`:'Sem jornada prevista';
    let state='is-empty';

    if(day.complete){
      value=fmtMinutes(day.worked);
      subtitle=day.extraDay?'Trabalho extra no dia':'Jornada concluída';
      state=day.extraDay?'is-extra-day':'is-complete';
    }else if(day.count){
      value=`${day.count}/4`;
      subtitle=`Em andamento · entrada ${day.first}`;
      state='is-partial';
    }else if(day.isToday){
      subtitle=day.scheduled?'Aguardando marcação hoje':'Hoje sem jornada prevista';
      state='is-today-empty';
    }

    const expectedHeight=day.expected>0
      ? Math.round(day.expected/max*100)
      : 0;

    const workedHeight=day.complete
      ? Math.max(8,Math.round(day.worked/max*100))
      : day.count
        ? Math.max(12,day.count*18)
        : 4;

    return `<div class="chart-column ${state}" title="${day.date.toLocaleDateString('pt-BR')}">
      <div class="chart-value">${value}</div>
      <div class="chart-track">
        <div class="chart-target" style="height:${expectedHeight}%"></div>
        <div class="chart-bar" style="height:${workedHeight}%"></div>
      </div>
      <strong>${names[index]}</strong>
      <small>${subtitle}</small>
    </div>`;
  }).join('');
}

function setupEmployeePinEditor(){
  const edit=document.getElementById('editar-pin');
  const save=document.getElementById('salvar-pin');
  const cancel=document.getElementById('cancelar-pin');
  const area=document.getElementById('pin-edit-area');
  const generate=document.getElementById('gerar-pin');
  const pin=document.getElementById('func-pin');
  const confirmPin=document.getElementById('func-pin-confirm');
  const force=document.getElementById('exigir-troca-pin');
  const access=document.getElementById('acesso-pin-ativo');
  if(!edit||!save||!cancel||!area||!generate||!pin||!confirmPin)return;

  const setMode=(editing)=>{
    area.hidden=!editing;
    edit.hidden=editing;
    save.hidden=!editing;
    cancel.hidden=!editing;
    [pin,confirmPin,force,access,generate].forEach(el=>{if(el)el.disabled=!editing});
    if(editing){
      pin.value='';confirmPin.value='';
      requestAnimationFrame(()=>pin.focus());
    }else{
      pin.value='';confirmPin.value='';
      if(access)access.checked=DB_STATE.employee?.acesso_ponto_ativo!==false;
      if(force)force.checked=!!DB_STATE.employee?.exigir_troca_pin;
    }
  };

  edit.addEventListener('click',(event)=>{
    event.preventDefault();
    if(!DB_STATE.employee){toast('Salve os dados cadastrais antes de definir o PIN.','warn');return}
    setMode(true);
  });
  cancel.addEventListener('click',(event)=>{event.preventDefault();setMode(false)});
  generate.addEventListener('click',(event)=>{
    event.preventDefault();
    const value=String(Math.floor(1000+Math.random()*9000));
    pin.value=value;confirmPin.value=value;pin.type='text';confirmPin.type='text';
    toast(`PIN gerado: ${value}`);
  });
  save.addEventListener('click',async(event)=>{
    event.preventDefault();
    if(!DB_STATE.employee){toast('Salve os dados cadastrais antes de definir o PIN.','warn');return}
    const value=pin.value.trim(),confirmation=confirmPin.value.trim();
    if(!/^\d{4}$/.test(value)){toast('O PIN deve conter exatamente 4 números.','warn');return}
    if(value!==confirmation){toast('A confirmação do PIN não coincide.','warn');return}
    if(!confirm(`Confirmar alteração do PIN de ${DB_STATE.employee.nome} (matrícula ${DB_STATE.employee.matricula})?`))return;
    save.disabled=true;save.textContent='Salvando PIN...';
    try{
      const result=await window.PlenitudeDB.defineEmployeePin(DB_STATE.employee.id,value,!!force?.checked,access?.checked!==false);
      DB_STATE.employee={...DB_STATE.employee,...result,pin_configurado:true};
      setMode(false);
      await renderEmployee(DB_STATE.employee);
      toast(`PIN definido com sucesso para a matrícula ${result.matricula}.`);
    }catch(error){toast(errorText(error),'warn');console.error(error)}
    finally{save.disabled=false;save.textContent='Confirmar alteração do PIN'}
  });
  setMode(false);
}

async function initFuncionarios(){
  const context=await initCommon(['administrador']);if(!context)return;const session=context.session;
  setupEmployeePinEditor();
  const form=document.getElementById('func-form'),photoInput=document.getElementById('func-foto');
  if(photoInput)photoInput.onchange=async()=>{const file=photoInput.files?.[0];if(!file)return;try{window.__employeePhotoData=await resizeEmployeePhoto(file);window.__employeePhotoFileSelected=true;renderAvatar(window.__employeePhotoData,document.getElementById('nome').value);document.getElementById('foto-status').textContent='Nova foto pronta para envio.'}catch(error){toast(errorText(error),'warn')}};
  try{
    const employees=await window.PlenitudeDB.employees();DB_STATE.employees=employees;DB_STATE.employee=employees[0]||null;
    fillEmployeeForm(DB_STATE.employee);await renderEmployee(DB_STATE.employee);
    form.onsubmit=async e=>{e.preventDefault();const button=form.querySelector('button[type="submit"]');button.disabled=true;button.textContent='Salvando...';try{
      const values={nome:document.getElementById('nome').value.trim(),cpf:document.getElementById('cpf').value.replace(/\D/g,''),cargo:document.getElementById('cargo').value.trim(),admissao:document.getElementById('admissao').value,matricula:document.getElementById('matricula')?.value.trim()||null,status:document.getElementById('func-status').value,foto_url:DB_STATE.employee?.foto_url||null,codigo_qr:DB_STATE.employee?.codigo_qr||null};
      let saved=await window.PlenitudeDB.saveEmployee(values,DB_STATE.employee?.id||null);
      if(window.__employeePhotoFileSelected&&window.__employeePhotoData){document.getElementById('foto-status').textContent='Enviando foto...';saved=await window.PlenitudeDB.uploadEmployeePhoto(saved.id,window.__employeePhotoData)}
      DB_STATE.employee=saved;window.__employeePhotoFileSelected=false;window.__employeePhotoData=null;if(photoInput)photoInput.value='';fillEmployeeForm(saved);await renderEmployee(saved);toast('Funcionário salvo no Supabase.');
    }catch(error){toast(errorText(error),'warn');console.error(error)}finally{button.disabled=false;button.textContent='Salvar dados cadastrais'}};
    document.getElementById('remover-foto').onclick=async()=>{if(!DB_STATE.employee)return toast('Cadastre primeiro o funcionário.','warn');if(!confirm('Remover a foto deste funcionário?'))return;try{const saved=await window.PlenitudeDB.removeEmployeePhoto(DB_STATE.employee);DB_STATE.employee=saved;window.__employeePhotoData=null;window.__employeePhotoFileSelected=false;await renderEmployee(saved);document.getElementById('foto-status').textContent='Foto removida.';toast('Foto removida.')}catch(error){toast(errorText(error),'warn')}};
        document.getElementById('baixar-qr').onclick=downloadEmployeeQr;
    document.getElementById('imprimir-qr').onclick=printEmployeeQr;
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}
function fillEmployeeForm(f){['nome','cpf','cargo','admissao'].forEach(k=>{const el=document.getElementById(k);if(el)el.value=f?(k==='admissao'?f.data_admissao||'':f[k]||''):''});const matricula=document.getElementById('matricula');if(matricula)matricula.value=f?.matricula||'';const status=document.getElementById('func-status');if(status)status.value=f?.status||'ativo';const access=document.getElementById('acesso-pin-ativo');if(access)access.checked=f?.acesso_ponto_ativo!==false;const force=document.getElementById('exigir-troca-pin');if(force)force.checked=!!f?.exigir_troca_pin;window.__employeePhotoData=null;window.__employeePhotoFileSelected=false}
function employeeStatusLabel(status){return({ativo:'Ativo',ferias:'Férias',afastado:'Afastado',inativo:'Inativo'})[status]||'Ativo'}
function employeeInitials(name=''){return name.trim().split(/\s+/).slice(0,2).map(x=>x[0]).join('').toUpperCase()||'P'}
function employeePhoto(f){return f?.foto_resolvida||(/^https?:|^data:/i.test(f?.foto_url||'')?f.foto_url:null)}
function renderAvatar(photo,name){const el=document.getElementById('func-avatar');if(!el)return;el.innerHTML=photo?`<img src="${photo}" alt="Foto de ${name||'funcionário'}">`:`<span>${employeeInitials(name)}</span>`}
async function renderEmployee(f){document.getElementById('func-nome').textContent=f?.nome||'Nenhum funcionário cadastrado';const status=f?.status||'ativo',badge=document.getElementById('func-status-badge');if(badge){badge.className=`employee-status ${status}`;badge.innerHTML=`<i></i> ${employeeStatusLabel(status)}`};document.getElementById('func-status-top').textContent=f?`1 funcionário ${status==='ativo'?'ativo':'cadastrado'}`:'Nenhum funcionário';renderAvatar(employeePhoto(f),f?.nome);document.getElementById('foto-status').textContent=f?.foto_url?'Foto armazenada com segurança no Supabase.':'Nenhuma foto cadastrada.';const pinConfigured=!!(f&&(f.pin_hash||f.pin_configurado));document.getElementById('acesso-status').textContent=f?(pinConfigured?'PIN configurado. Use “Alterar PIN” para substituí-lo.':'PIN ainda não configurado. Clique em “Definir novo PIN”.'):'Salve primeiro os dados cadastrais.';const pinBadge=document.getElementById('pin-status-badge');if(pinBadge){pinBadge.className=`pin-status-badge ${pinConfigured?'configured':'pending'}`;pinBadge.textContent=pinConfigured?'PIN configurado':'Não configurado'}const pinMat=document.getElementById('pin-summary-matricula');if(pinMat)pinMat.textContent=f?.matricula||'—';const pinState=document.getElementById('pin-summary-status');if(pinState)pinState.textContent=pinConfigured?'Configurado':'Não configurado';const pinAccess=document.getElementById('pin-summary-access');if(pinAccess)pinAccess.textContent=f?(f.acesso_ponto_ativo===false?'Bloqueado':'Permitido'):'Aguardando cadastro';const editPin=document.getElementById('editar-pin');if(editPin){editPin.disabled=!f;editPin.textContent=pinConfigured?'Alterar PIN':'Definir novo PIN'};document.getElementById('func-detalhes').innerHTML=f?`<span><strong>Cargo:</strong> ${f.cargo||'—'}</span><span><strong>CPF:</strong> ${f.cpf||'—'}</span><span><strong>Matrícula:</strong> ${f.matricula||'—'}</span><span><strong>Admissão:</strong> ${f.data_admissao?new Intl.DateTimeFormat('pt-BR').format(new Date(f.data_admissao+'T12:00:00')):'—'}</span><span><strong>Carga semanal:</strong> ${fmtMinutes(f.carga_semanal_minutos||2640)}</span><span><strong>Acesso:</strong> ${f.acesso_ponto_ativo===false?'Bloqueado':'Matrícula + PIN'}</span>`:'<span>Preencha o formulário para cadastrar o primeiro funcionário.</span>';const code=f?.codigo_qr||'';document.getElementById('func-qr-code').textContent=code||'Será gerado ao salvar';const qr=document.getElementById('func-qrcode');if(qr){qr.innerHTML='';if(code&&window.QRCode)new QRCode(qr,{text:`${location.origin}${location.pathname.replace(/funcionarios\.html$/,'ponto.html')}?codigo=${encodeURIComponent(code)}`,width:112,height:112,colorDark:'#2a2526',colorLight:'#ffffff',correctLevel:QRCode.CorrectLevel.M})}}
function qrCanvasOrImage(){const box=document.getElementById('func-qrcode');return box?.querySelector('canvas')||box?.querySelector('img')}
function downloadEmployeeQr(){const source=qrCanvasOrImage();if(!source)return toast('Salve o funcionário para gerar o QR.','warn');const a=document.createElement('a');a.download=`qr-${(DB_STATE.employee?.nome||'funcionario').toLowerCase().replace(/[^a-z0-9]+/g,'-')}.png`;a.href=source.tagName==='CANVAS'?source.toDataURL('image/png'):source.src;a.click()}
function printEmployeeQr(){if(!DB_STATE.employee||!qrCanvasOrImage())return toast('Salve o funcionário para gerar o QR.','warn');const src=qrCanvasOrImage().tagName==='CANVAS'?qrCanvasOrImage().toDataURL('image/png'):qrCanvasOrImage().src,w=open('','_blank','width=520,height=650');w.document.write(`<title>QR de ${DB_STATE.employee.nome}</title><style>body{font-family:Arial;text-align:center;padding:40px}img{width:280px;height:280px}h1{font-size:24px}p{font-size:14px}</style><h1>${DB_STATE.employee.nome}</h1><img src="${src}"><p>${DB_STATE.employee.codigo_qr||''}</p>`);w.document.close();w.onload=()=>w.print()}
async function resizeEmployeePhoto(file){if(!file.type.startsWith('image/'))throw new Error('Selecione um arquivo de imagem.');if(file.size>8*1024*1024)throw new Error('A imagem deve ter no máximo 8 MB.');const data=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=()=>reject(new Error('Não foi possível ler a imagem.'));r.readAsDataURL(file)});const img=await new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=()=>reject(new Error('Imagem inválida.'));i.src=data});const size=480,canvas=document.createElement('canvas');canvas.width=size;canvas.height=size;const ctx=canvas.getContext('2d'),scale=Math.max(size/img.width,size/img.height),w=img.width*scale,h=img.height*scale;ctx.drawImage(img,(size-w)/2,(size-h)/2,w,h);return canvas.toDataURL('image/jpeg',.82)}

async function initJornada(){
  const context=await initCommon(['administrador']);if(!context)return;const session=context.session;
  const tbody=document.getElementById('jornada-body');
  try{
    const employees=await window.PlenitudeDB.employees();DB_STATE.employee=employees[0]||null;
    if(!DB_STATE.employee){tbody.innerHTML='<tr><td colspan="6"><div class="mini-empty">Cadastre primeiro um funcionário.</div></td></tr>';document.getElementById('jornada-form').querySelector('button[type="submit"]').disabled=true;return}
    const rows=await window.PlenitudeDB.schedules(DB_STATE.employee.id),schedule=dbScheduleToUi(rows);DB_STATE.schedule=schedule;
    tbody.innerHTML='';schedule.forEach((s,i)=>tbody.insertAdjacentHTML('beforeend',`<tr data-i="${i}"><td><strong>${s.dia}</strong></td><td><input type="time" name="entrada" value="${s.entrada}"></td><td><input type="time" name="almoco" value="${s.almoco}"></td><td><input type="time" name="retorno" value="${s.retorno}"></td><td><input type="time" name="saida" value="${s.saida}"></td><td class="total-dia">${fmtMinutes(totalDay(s))}</td></tr>`));
    tbody.addEventListener('input',updateTotals);updateTotals();
    document.getElementById('jornada-form').onsubmit=async e=>{e.preventDefault();const button=e.currentTarget.querySelector('button[type="submit"]');button.disabled=true;button.textContent='Salvando...';try{const arr=[...tbody.querySelectorAll('tr')].map(tr=>({dia:tr.cells[0].innerText,entrada:tr.querySelector('[name=entrada]').value,almoco:tr.querySelector('[name=almoco]').value,retorno:tr.querySelector('[name=retorno]').value,saida:tr.querySelector('[name=saida]').value}));await window.PlenitudeDB.saveSchedules(DB_STATE.employee.id,arr);DB_STATE.schedule=arr;updateTotals();toast('Jornada salva no Supabase.')}catch(error){toast(errorText(error),'warn');console.error(error)}finally{button.disabled=false;button.textContent='Salvar jornada'}};
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}
function updateTotals(){let weekly=0;document.querySelectorAll('#jornada-body tr').forEach(tr=>{if(!tr.querySelector('[name=entrada]'))return;const g=n=>tr.querySelector(`[name=${n}]`).value,s={entrada:g('entrada'),almoco:g('almoco'),retorno:g('retorno'),saida:g('saida')},t=totalDay(s);weekly+=t;tr.querySelector('.total-dia').textContent=fmtMinutes(t)});const total=document.getElementById('total-semanal');if(total)total.textContent=fmtMinutes(weekly)}

async function initPonto(){
  const context=await initCommon(['administrador','funcionario']);if(!context)return;const session=context.session;
  const clock=()=>{const d=new Date();document.getElementById('clock-date').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(d);document.getElementById('clock-time').textContent=d.toLocaleTimeString('pt-BR')};clock();setInterval(clock,1000);
  try{
    const profile=await window.PlenitudeDB.profile();
    const employees=profile.papel==='administrador'?await window.PlenitudeDB.employees():[];
    DB_STATE.profile=profile;DB_STATE.employees=employees;
    const selector=document.getElementById('ponto-funcionario-select');
    if(profile.papel==='administrador'){
      selector.hidden=false;
      selector.innerHTML=employees.length?employees.map(f=>`<option value="${f.id}">${f.nome}</option>`).join(''):'<option value="">Nenhum funcionário cadastrado</option>';
      DB_STATE.employee=employees[0]||null;
      selector.onchange=async()=>{DB_STATE.employee=employees.find(f=>f.id===selector.value)||null;renderClockEmployee(DB_STATE.employee);await loadRealPunches()};
    }else{
      DB_STATE.employee=await window.PlenitudeDB.ownEmployee();
      selector.hidden=true;
      document.body.classList.add('employee-mode');
      const back=document.querySelector('.back-link');if(back)back.remove();
    }
    if(!DB_STATE.employee){document.getElementById('clock-employee').textContent=profile.papel==='funcionario'?'Conta ainda não vinculada a um funcionário':'Nenhum funcionário cadastrado';document.getElementById('clock-status').textContent='Acesso pendente';document.getElementById('registrar').disabled=true;renderRealPunches([]);return}
    renderClockEmployee(DB_STATE.employee);
    await loadRealPunches();
    document.getElementById('registrar').onclick=async()=>{
      const button=document.getElementById('registrar');button.disabled=true;button.classList.add('loading');
      try{const mark=await window.PlenitudeDB.registerPoint(DB_STATE.employee.id);await loadRealPunches();const label=labelForMarkType(mark?.tipo);const time=formatDbTime(mark?.registrado_em);toast(`${label} registrada às ${time}.`)}catch(error){toast(errorText(error),'warn');console.error(error)}finally{button.classList.remove('loading');}
    };
    window.PlenitudeDB.subscribeMarks(async()=>{if(document.visibilityState==='visible')await loadRealPunches()});
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}
function renderClockEmployee(f){if(!f)return;document.getElementById('clock-employee').textContent=f.nome;const status=document.getElementById('clock-status');if(status){status.textContent=employeeStatusLabel(f.status||'ativo');status.className=`${f.status||'ativo'}`};const avatar=document.getElementById('clock-avatar'),photo=employeePhoto(f);if(avatar)avatar.innerHTML=photo?`<img src="${photo}" alt="Foto de ${f.nome}">`:`<span>${employeeInitials(f.nome)}</span>`}
function labelForMarkType(type){return({entrada:'Entrada',inicio_intervalo:'Início do almoço',fim_intervalo:'Retorno do almoço',saida:'Saída'})[type]||'Marcação'}
function formatDbTime(value){return value?new Date(value).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}):'—'}
async function loadRealPunches(){
  if(!DB_STATE.employee)return renderRealPunches([]);
  renderClockEmployee(DB_STATE.employee);
  const today=localDateKey(),marks=(await window.PlenitudeDB.marksForRange(today,today)).filter(m=>m.funcionario_id===DB_STATE.employee.id);
  renderRealPunches(marks);
  if(DB_STATE.profile?.papel==='funcionario') await renderEmployeeSummary(marks);
}
function renderRealPunches(marks){
  const list=document.getElementById('lista-pontos'),button=document.getElementById('registrar');
  list.innerHTML=marks.length?marks.map(m=>`<div class="punch-item"><span>${labelForMarkType(m.tipo)}</span><strong>${formatDbTime(m.registrado_em)}</strong></div>`).join(''):'<div class="mini-empty">Nenhuma marcação feita hoje.</div>';
  document.getElementById('proxima').textContent=marks.length<4?`Próxima marcação: ${punchLabels[marks.length]}`:'Jornada de hoje concluída';
  if(button)button.disabled=!DB_STATE.employee||marks.length>=4;
  const progress=document.getElementById('punch-progress');if(progress)progress.innerHTML=punchLabels.map((_,i)=>`<span class="progress-step ${i<marks.length?'done':''}"></span>`).join('');
  const steps=document.getElementById('punch-steps');if(steps)steps.innerHTML=punchLabels.map((name,i)=>`<div class="punch-step ${i<marks.length?'done':''} ${i===marks.length?'current':''}"><span class="step-icon">${i<marks.length?'✓':i+1}</span><strong>${name}</strong><small>${marks[i]?formatDbTime(marks[i].registrado_em):'Aguardando'}</small></div>`).join('');
}


async function renderEmployeeSummary(todayMarks){
  const panel=document.getElementById('employee-self-service');if(!panel||!DB_STATE.employee)return;
  try{
    const now=new Date(),firstMonth=new Date(now.getFullYear(),now.getMonth(),1);
    const monday=new Date(now);monday.setDate(now.getDate()-((now.getDay()+6)%7));
    const [scheduleRows,weekMarks,monthMarks]=await Promise.all([
      window.PlenitudeDB.schedules(DB_STATE.employee.id),
      window.PlenitudeDB.marksForRange(localDateKey(monday),localDateKey(now)),
      window.PlenitudeDB.marksForRange(localDateKey(firstMonth),localDateKey(now))
    ]);
    const schedule=dbScheduleToUi(scheduleRows);
    const balanceFor=(marks)=>{
      const grouped={};marks.filter(m=>m.funcionario_id===DB_STATE.employee.id).forEach(m=>(grouped[m.data_local]??=[]).push(m));
      let total=0;
      Object.entries(grouped).forEach(([key,list])=>{
        const times=list.sort((a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em)).map(m=>formatDbTime(m.registrado_em));
        const c=calcPunchDay(times,scheduleForDateFrom(schedule,dateFromKey(key)));if(c)total+=c.diff;
      });return total;
    };
    const todayTimes=todayMarks.map(m=>formatDbTime(m.registrado_em));
    const todayCalc=calcPunchDay(todayTimes,scheduleForDateFrom(schedule,now));
    document.getElementById('self-today-balance').textContent=todayCalc?signedMinutes(todayCalc.diff):'Em andamento';
    document.getElementById('self-week-balance').textContent=signedMinutes(balanceFor(weekMarks));
    document.getElementById('self-month-balance').textContent=signedMinutes(balanceFor(monthMarks));
    document.getElementById('self-profile-name').textContent=DB_STATE.employee.nome||'—';
    document.getElementById('self-profile-role').textContent=DB_STATE.employee.cargo||'Funcionário';
    document.getElementById('self-profile-code').textContent=DB_STATE.employee.matricula||DB_STATE.employee.codigo_qr||'—';
    panel.hidden=false;
  }catch(error){console.error(error)}
}

async function initRelatorios(){
  const context=await initCommon(['administrador']);if(!context)return;
  const month=document.getElementById('rel-mes'),now=new Date();
  month.value=`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}`;
  try{
    const [employees,profile]=await Promise.all([window.PlenitudeDB.employees(),window.PlenitudeDB.profile()]);
    DB_STATE.employees=employees;DB_STATE.profile=profile;
    const select=document.getElementById('rel-funcionario');
    select.innerHTML=employees.length?employees.map(f=>`<option value="${f.id}">${f.nome} — ${f.matricula||'sem matrícula'}</option>`).join(''):'<option value="">Nenhum funcionário cadastrado</option>';
    document.getElementById('atualizar-relatorio').onclick=renderRelatorio;
    document.getElementById('imprimir-relatorio').onclick=()=>window.print();
    select.onchange=renderRelatorio;month.onchange=renderRelatorio;
    await renderRelatorio();
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}
function balanceStatusLabel(status){return({completo:'Completo',falta:'Falta',pendente:'Pendente',aguardando:'Aguardando',futuro:'Futuro',sem_jornada:'Sem jornada',extra:'Hora extra',folga:'Folga',ferias:'Férias',feriado:'Feriado',atestado:'Atestado'})[status]||status||'—'}
function balanceStatusClass(status){return ['falta','pendente'].includes(status)?'negative':['completo','extra'].includes(status)?'positive':''}
async function renderRelatorio(){
  try{
    const selected=document.getElementById('rel-mes').value,employeeId=document.getElementById('rel-funcionario').value;
    if(!selected||!employeeId){document.getElementById('relatorio-body').innerHTML='';document.getElementById('relatorio-vazio').style.display='block';return}
    const [year,month]=selected.split('-').map(Number),last=new Date(year,month,0).getDate(),start=`${selected}-01`,end=`${selected}-${String(last).padStart(2,'0')}`;
    const employee=DB_STATE.employees.find(f=>f.id===employeeId)||{};
    const company=DB_STATE.profile?.empresas||{};
    document.getElementById('espelho-empresa').textContent=company.nome_fantasia||company.razao_social||'Livraria Plenitude';
    document.getElementById('espelho-endereco').textContent=[company.endereco,company.cidade,company.uf].filter(Boolean).join(' — ')||'—';
    document.getElementById('espelho-periodo').textContent=new Intl.DateTimeFormat('pt-BR',{month:'long',year:'numeric'}).format(new Date(year,month-1,1));
    document.getElementById('espelho-emissao').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'short',timeStyle:'short'}).format(new Date());
    document.getElementById('espelho-funcionario').textContent=employee.nome||'—';
    document.getElementById('espelho-matricula').textContent=employee.matricula||'—';
    document.getElementById('espelho-cargo').textContent=employee.cargo||'—';
    document.getElementById('espelho-admissao').textContent=employee.data_admissao?new Intl.DateTimeFormat('pt-BR').format(dateFromKey(employee.data_admissao)):'—';
    document.title=`Espelho de Ponto - ${employee.nome||'Funcionário'} - ${selected}`;
    const result=await window.PlenitudeDB.bankHours(employeeId,start,end),summary=result.resumo||{},days=result.dias||[];
    document.getElementById('rel-dias').textContent=summary.dias_trabalhados||0;
    document.getElementById('rel-previsto').textContent=fmtMinutes(summary.previsto_minutos||0);
    document.getElementById('rel-horas').textContent=fmtMinutes(summary.trabalhado_minutos||0);
    document.getElementById('rel-saldo').textContent=signedMinutes(summary.saldo_minutos||0);
    document.getElementById('rel-creditos').textContent=`+${fmtMinutes(summary.credito_minutos||0)}`;
    document.getElementById('rel-debitos').textContent=`−${fmtMinutes(summary.debito_minutos||0)}`;
    document.getElementById('rel-pendencias').textContent=String((summary.pendencias||0)+(summary.faltas||0));
    const relevant=days.filter(d=>d.previsto_minutos>0||d.quantidade_marcacoes>0||d.ocorrencia);
    const body=document.getElementById('relatorio-body'),empty=document.getElementById('relatorio-vazio');
    body.innerHTML=relevant.map(r=>{
      const marks=(r.marcacoes||[]).map(v=>formatDbTime(v));
      const saldo=r.saldo_minutos===null||r.saldo_minutos===undefined?'—':signedMinutes(r.saldo_minutos);
      return `<tr><td>${new Intl.DateTimeFormat('pt-BR',{weekday:'short',day:'2-digit',month:'2-digit'}).format(dateFromKey(r.data))}</td>${[0,1,2,3].map(i=>`<td>${marks[i]||'—'}</td>`).join('')}<td>${fmtMinutes(r.previsto_minutos||0)}</td><td>${fmtMinutes(r.trabalhado_minutos||0)}</td><td class="${r.saldo_minutos<0?'negative':r.saldo_minutos>0?'positive':''}">${saldo}</td><td><span class="report-status ${balanceStatusClass(r.status)}">${balanceStatusLabel(r.status)}</span>${r.tolerancia_aplicada?' <small title="Horário real preservado; tolerância aplicada apenas ao cálculo">Tolerância</small>':''}${r.alerta_intervalo?' <small class="negative">'+(r.alerta_intervalo==='intervalo_curto'?'Intervalo curto':'Intervalo excedido')+'</small>':''}</td></tr>`;
    }).join('');
    empty.style.display=relevant.length?'none':'block';
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}

async function initConfiguracoes(){
  const context=await initCommon(['administrador']);if(!context)return;const session=context.session;
  try{
    const profile=await window.PlenitudeDB.profile();
    const company=profile.empresas||{};
    document.getElementById('empresa-nome').value=company.nome_fantasia||company.razao_social||'Livraria Plenitude';
    document.getElementById('empresa-endereco').value=company.endereco||'';
    document.getElementById('admin-nome').value=profile.nome||'Administrador';
    document.getElementById('admin-email').value=profile.email||session.user.email||'';
    document.getElementById('admin-email').readOnly=true;
    document.getElementById('tol-entrada').value=company.tolerancia_entrada_minutos??15;document.getElementById('tol-saida').value=company.tolerancia_saida_minutos??10;document.getElementById('int-min').value=company.intervalo_minimo_minutos??60;document.getElementById('int-max').value=company.intervalo_maximo_minutos??120;document.getElementById('extras-auto').checked=company.horas_extras_automaticas!==false;document.getElementById('limite-banco').value=Math.round((company.limite_banco_horas_minutos??2400)/60);
    document.getElementById('config-form').onsubmit=async e=>{
      e.preventDefault();
      const button=e.submitter; if(button)button.disabled=true;
      try{
        await window.PlenitudeDB.updateSettings({
          empresaNome:document.getElementById('empresa-nome').value,
          endereco:document.getElementById('empresa-endereco').value,
          adminNome:document.getElementById('admin-nome').value
        });
        toast('Configurações salvas no Supabase.');
      }catch(error){toast(errorText(error),'warn');console.error(error)}finally{if(button)button.disabled=false}
    };
    document.getElementById('politicas-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;if(b)b.disabled=true;try{await window.PlenitudeDB.savePointPolicies({entrada:Number(document.getElementById('tol-entrada').value),saida:Number(document.getElementById('tol-saida').value),intervaloMinimo:Number(document.getElementById('int-min').value),intervaloMaximo:Number(document.getElementById('int-max').value),extrasAutomaticas:document.getElementById('extras-auto').checked,limiteBanco:Number(document.getElementById('limite-banco').value)*60});toast('Políticas de ponto salvas.');}catch(error){toast(errorText(error),'warn')}finally{if(b)b.disabled=false}};
    const masterStatus=await window.PlenitudeDB.masterPinStatus();
    const masterConfigured=Boolean(masterStatus?.configurado);
    const masterBadge=document.getElementById('master-pin-badge');
    masterBadge.textContent=masterConfigured?'Configurado':'Não configurado';
    if(masterConfigured)masterBadge.classList.add('success');
    document.getElementById('master-current-wrap').hidden=!masterConfigured;
    document.getElementById('master-pin-form').onsubmit=async e=>{
      e.preventDefault();const b=e.submitter;if(b)b.disabled=true;
      const current=document.getElementById('master-pin-current').value.trim();
      const next=document.getElementById('master-pin-new').value.trim();
      const confirmPin=document.getElementById('master-pin-confirm').value.trim();
      try{
        if(!/^\d{6}$/.test(next))throw new Error('O PIN Mestre deve ter exatamente 6 números.');
        if(next!==confirmPin)throw new Error('A confirmação do PIN Mestre não confere.');
        if(masterConfigured&&!/^\d{6}$/.test(current))throw new Error('Informe o PIN Mestre atual.');
        await window.PlenitudeDB.setMasterPin(next,current);
        toast(masterConfigured?'PIN Mestre alterado.':'PIN Mestre configurado.');
        document.getElementById('master-pin-form').reset();
        masterBadge.textContent='Configurado';masterBadge.classList.add('success');document.getElementById('master-current-wrap').hidden=false;
      }catch(error){toast(errorText(error),'warn')}finally{if(b)b.disabled=false}
    };
    document.getElementById('exportar-backup').onclick=async()=>{
      const button=document.getElementById('exportar-backup');button.disabled=true;
      try{
        const data=await window.PlenitudeDB.backupData();
        const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'}),a=document.createElement('a');
        a.href=URL.createObjectURL(blob);a.download=`plenitude-ponto-backup-${localDateKey()}.json`;a.click();URL.revokeObjectURL(a.href);
        toast('Backup do Supabase baixado.');
      }catch(error){toast(errorText(error),'warn');console.error(error)}finally{button.disabled=false}
    };
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}

let calendarCursor=new Date();
let CALENDAR_STATE={employee:null,events:[],marks:[]};
const occurrenceTypeToDb={'Folga':'folga','Férias':'ferias','Feriado':'feriado','Atestado':'atestado','Compensação':'compensacao'};
const occurrenceTypeFromDb={folga:'Folga',ferias:'Férias',feriado:'Feriado',atestado:'Atestado',compensacao:'Compensação',justificativa:'Justificativa'};
async function initCalendario(){
  const context=await initCommon(['administrador']);if(!context)return;const session=context.session;
  try{
    const employees=await window.PlenitudeDB.employees();CALENDAR_STATE.employee=employees[0]||null;
    calendarCursor=new Date();
    document.getElementById('cal-prev').onclick=async()=>{calendarCursor.setMonth(calendarCursor.getMonth()-1);await renderCalendar()};
    document.getElementById('cal-next').onclick=async()=>{calendarCursor.setMonth(calendarCursor.getMonth()+1);await renderCalendar()};
    document.getElementById('event-form').onsubmit=async e=>{
      e.preventDefault();
      if(!CALENDAR_STATE.employee){toast('Cadastre um funcionário antes de adicionar ocorrências.','warn');return}
      const date=document.getElementById('event-date').value,type=document.getElementById('event-type').value,note=document.getElementById('event-note').value.trim();
      if(!date)return;
      const button=e.submitter;if(button)button.disabled=true;
      try{
        await window.PlenitudeDB.saveOccurrence(CALENDAR_STATE.employee.id,{tipo:occurrenceTypeToDb[type],dataInicio:date,dataFim:date,descricao:note});
        toast('Ocorrência salva no Supabase.');await renderCalendar();
      }catch(error){toast(errorText(error),'warn');console.error(error)}finally{if(button)button.disabled=false}
    };
    await renderCalendar();
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}
async function renderCalendar(){
  const year=calendarCursor.getFullYear(),month=calendarCursor.getMonth(),first=new Date(year,month,1),last=new Date(year,month+1,0);
  const start=localDateKey(first),end=localDateKey(last);
  if(CALENDAR_STATE.employee){
    [CALENDAR_STATE.events,CALENDAR_STATE.marks]=await Promise.all([
      window.PlenitudeDB.occurrencesForRange(CALENDAR_STATE.employee.id,start,end),
      window.PlenitudeDB.marksForRange(start,end)
    ]);
  }else{CALENDAR_STATE.events=[];CALENDAR_STATE.marks=[]}
  const eventsByDate={};CALENDAR_STATE.events.forEach(ev=>{eventsByDate[ev.data_inicio]=ev});
  const marksByDate={};CALENDAR_STATE.marks.filter(m=>!CALENDAR_STATE.employee||m.funcionario_id===CALENDAR_STATE.employee.id).forEach(m=>(marksByDate[m.data_local]??=[]).push(m));
  document.getElementById('cal-title').textContent=new Intl.DateTimeFormat('pt-BR',{month:'long',year:'numeric'}).format(first);
  const grid=document.getElementById('calendar-grid');grid.innerHTML=['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'].map(x=>`<div class="cal-weekday">${x}</div>`).join('');
  for(let i=0;i<first.getDay();i++)grid.insertAdjacentHTML('beforeend','<div class="cal-day muted-day"></div>');
  for(let day=1;day<=last.getDate();day++){
    const d=new Date(year,month,day),key=localDateKey(d),ev=eventsByDate[key],p=marksByDate[key]||[],today=key===localDateKey();
    grid.insertAdjacentHTML('beforeend',`<button class="cal-day ${today?'today':''} ${ev?'has-event':''} ${p.length?'has-punch':''}" data-date="${key}"><span>${day}</span>${p.length?`<small>${p.length}/4 pontos</small>`:''}${ev?`<em>${occurrenceTypeFromDb[ev.tipo]||ev.tipo}</em>`:''}</button>`);
  }
  grid.querySelectorAll('[data-date]').forEach(btn=>btn.onclick=()=>{
    const key=btn.dataset.date,ev=eventsByDate[key];document.getElementById('event-date').value=key;
    document.getElementById('event-type').value=ev?occurrenceTypeFromDb[ev.tipo]||'Folga':'Folga';document.getElementById('event-note').value=ev?.descricao||'';
  });
}



async function initAjustes(){
 const context=await initCommon(['administrador']);if(!context)return;
 const filter=document.getElementById('adjustment-filter');
 const params=new URLSearchParams(location.search);
 const requestedStatus=params.get('status');
 const queueMode=params.get('fila')==='1';

 if(requestedStatus && [...filter.options].some(option=>option.value===requestedStatus)){
   filter.value=requestedStatus;
 }

 function focusFirstPending(){
   if(!queueMode)return;
   const first=document.querySelector('.adjustment-admin-card[data-status="pendente"]');
   if(!first)return;
   first.classList.add('queue-current');
   first.scrollIntoView({behavior:'smooth',block:'center'});
   const textarea=first.querySelector('textarea');
   if(textarea)setTimeout(()=>textarea.focus({preventScroll:true}),300);
 }

 async function render(){
  try{
   const rows=await window.PlenitudeDB.adminAdjustmentRequests(filter.value||null);
   const list=document.getElementById('adjustments-list');
   const pendingRows=rows.filter(row=>row.status==='pendente');
   document.getElementById('adjustment-count').textContent=`${pendingRows.length} pendentes`;
   document.getElementById('adjustments-empty').style.display=rows.length?'none':'block';

   if(queueMode && pendingRows.length===0){
     list.innerHTML=`
      <div class="queue-complete">
       <div class="icon">✓</div>
       <h3>Nenhum ajuste pendente</h3>
       <p>A fila de análise foi concluída.</p>
       <a class="btn primary" href="admin.html">Voltar ao painel</a>
      </div>`;
     document.getElementById('adjustments-empty').style.display='none';
     return;
   }

   list.innerHTML=rows.map(r=>{
    const queueIndex=pendingRows.findIndex(item=>item.id===r.id);
    return `
    <article class="adjustment-admin-card" data-status="${r.status}" data-adjustment-id="${r.id}">
     <div class="adjustment-admin-main">
      <div class="request-heading">
       <div><small>${r.matricula||'—'}</small><h3>${r.funcionario_nome}</h3></div>
       <span class="request-status ${r.status}">${r.status}</span>
      </div>
      ${queueMode&&r.status==='pendente'?`<div class="queue-position">Ajuste ${queueIndex+1} de ${pendingRows.length}</div>`:''}
      <div class="request-facts">
       <span><b>Data</b>${new Date(r.data_marcacao+'T12:00:00').toLocaleDateString('pt-BR')}</span>
       <span><b>Marcação</b>${labelForMarkType(r.tipo_marcacao)}</span>
       <span><b>Horário</b>${String(r.horario_solicitado).slice(0,5)}</span>
      </div>
      <p>${r.justificativa}</p>
      ${r.resposta_administrador?`<div class="admin-response"><b>Resposta:</b> ${r.resposta_administrador}</div>`:''}
     </div>
     ${r.status==='pendente'?`
      <div class="request-actions">
       <textarea id="response-${r.id}" placeholder="Resposta opcional para a funcionária"></textarea>
       <button class="btn primary" data-decision="aprovada" data-id="${r.id}">Aprovar e incluir ponto</button>
       <button class="btn outline danger" data-decision="rejeitada" data-id="${r.id}">Rejeitar</button>
      </div>`:''}
    </article>`;
   }).join('');

   list.querySelectorAll('[data-decision]').forEach(button=>button.onclick=async()=>{
    const decision=button.dataset.decision;
    const id=button.dataset.id;
    const response=document.getElementById(`response-${id}`)?.value||'';
    if(!confirm(decision==='aprovada'?'Aprovar e criar esta marcação?':'Rejeitar esta solicitação?'))return;

    const card=button.closest('.adjustment-admin-card');
    card?.querySelectorAll('button').forEach(item=>item.disabled=true);
    try{
     await window.PlenitudeDB.decideAdjustment(id,decision,response);
     toast(decision==='aprovada'?'Ajuste aprovado e ponto incluído.':'Solicitação rejeitada.');
     await render();
    }catch(error){
     toast(errorText(error),'warn');
     card?.querySelectorAll('button').forEach(item=>item.disabled=false);
    }
   });

   focusFirstPending();
  }catch(error){
   toast(errorText(error),'warn');
   console.error(error);
  }
 }

 filter.onchange=()=>{
   const url=new URL(location.href);
   if(filter.value)url.searchParams.set('status',filter.value);
   else url.searchParams.delete('status');
   history.replaceState({},'',url);
   render();
 };
 document.getElementById('refresh-adjustments').onclick=render;
 await render();
}
