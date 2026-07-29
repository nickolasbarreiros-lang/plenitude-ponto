const defaultSchedule=[
  {dia:'Segunda',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'19:00'},
  {dia:'Terça',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'19:00'},
  {dia:'Quarta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'18:00'},
  {dia:'Quinta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'18:30'},
  {dia:'Sexta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'17:00'}
];
const demoEmployee={nome:'Funcionário da loja',cpf:'',cargo:'Atendente',admissao:'',email:''};
const punchLabels=['Entrada','Início do almoço','Retorno do almoço','Saída'];
const STORAGE={schedule:'plenitudeSchedule',employee:'plenitudeEmployee',punches:'plenitudePunches',config:'plenitudeConfig',events:'plenitudeEvents',theme:'plenitudeTheme'};
let DB_STATE={profile:null,employees:[],employee:null,schedule:[]};
const dayNames=['Segunda','Terça','Quarta','Quinta','Sexta'];
function dbScheduleToUi(rows){const byDay=new Map((rows||[]).map(r=>[r.dia_semana,r]));return dayNames.map((dia,i)=>{const r=byDay.get(i+1);return r?{dia,entrada:r.entrada?.slice(0,5)||'',almoco:r.inicio_intervalo?.slice(0,5)||'',retorno:r.fim_intervalo?.slice(0,5)||'',saida:r.saida?.slice(0,5)||''}:defaultSchedule[i]});}
function errorText(error){const m=String(error?.message||error||'');if(m.includes('duplicate key'))return 'Já existe um cadastro com este CPF ou matrícula.';if(m.includes('row-level security'))return 'Seu usuário não tem permissão para esta operação.';if(m.includes('Failed to fetch'))return 'Não foi possível conectar ao banco de dados.';return m||'Ocorreu um erro inesperado.';}


const readJSON=(key,fallback)=>{try{return JSON.parse(localStorage.getItem(key)||'null')??fallback}catch{return fallback}};
const writeJSON=(key,value)=>localStorage.setItem(key,JSON.stringify(value));
async function requireAuth(){return window.PlenitudeAuth.requireSession()}
function getSchedule(){return readJSON(STORAGE.schedule,defaultSchedule)}
function getEmployee(){return readJSON(STORAGE.employee,demoEmployee)}
function getAllPunches(){return readJSON(STORAGE.punches,{})}
function getConfig(){return readJSON(STORAGE.config,{})}
function getEvents(){return readJSON(STORAGE.events,{})}
function localDateKey(d=new Date()){return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function getPunches(date=new Date()){return getAllPunches()[localDateKey(date)]||[]}
function savePunches(list,date=new Date()){const all=getAllPunches();all[localDateKey(date)]=list;writeJSON(STORAGE.punches,all)}
function minutes(a,b){if(!a||!b)return 0;const [h1,m1]=a.split(':').map(Number),[h2,m2]=b.split(':').map(Number);return(h2*60+m2)-(h1*60+m1)}
function totalDay(s){return s?minutes(s.entrada,s.almoco)+minutes(s.retorno,s.saida):0}
function fmtMinutes(value){const n=Math.max(0,Math.round(value||0)),h=Math.floor(n/60),m=n%60;return`${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`}
function signedMinutes(value){return`${value>=0?'+':'−'}${fmtMinutes(Math.abs(value))}`}
function dateFromKey(k){const [y,m,d]=k.split('-').map(Number);return new Date(y,m-1,d)}
function scheduleForDate(d){const map={1:0,2:1,3:2,4:3,5:4};const i=map[d.getDay()];return i===undefined?null:getSchedule()[i]}
function todaySchedule(){return scheduleForDate(new Date())}
function calcPunchDay(p,s){if(!p||p.length<4||!s)return null;const worked=minutes(p[0],p[1])+minutes(p[2],p[3]);return{worked,expected:totalDay(s),diff:worked-totalDay(s)}}
function toast(message,type='ok'){let box=document.querySelector('.toast');if(!box){box=document.createElement('div');box.className='toast';document.body.appendChild(box)}box.className=`toast show ${type}`;box.textContent=message;clearTimeout(box._timer);box._timer=setTimeout(()=>box.classList.remove('show'),2600)}
function applyTheme(theme){document.documentElement.dataset.theme=theme;localStorage.setItem(STORAGE.theme,theme);const btn=document.getElementById('theme-toggle');if(btn)btn.textContent=theme==='dark'?'☀':'◐'}
async function initCommon(){const session=await requireAuth();if(!session)return null;const theme=localStorage.getItem(STORAGE.theme)||'light';applyTheme(theme);const logout=document.getElementById('sair');if(logout)logout.onclick=async()=>{logout.disabled=true;try{await window.PlenitudeAuth.signOut()}catch(error){logout.disabled=false;toast('Não foi possível sair do sistema.','warn')}};if(!document.getElementById('theme-toggle')){const b=document.createElement('button');b.id='theme-toggle';b.className='theme-toggle';b.type='button';b.title='Alternar tema';b.onclick=()=>applyTheme(document.documentElement.dataset.theme==='dark'?'light':'dark');document.body.appendChild(b)} return session; }

async function initAdmin(){
  const session=await initCommon();if(!session)return;
  try{
    const [profile,employees]=await Promise.all([window.PlenitudeDB.profile(),window.PlenitudeDB.employees()]);
    DB_STATE.profile=profile;DB_STATE.employees=employees;DB_STATE.employee=employees[0]||null;
    DB_STATE.schedule=DB_STATE.employee?dbScheduleToUi(await window.PlenitudeDB.schedules(DB_STATE.employee.id)):defaultSchedule;
    const today=localDateKey(),marks=await window.PlenitudeDB.marksForRange(today,today);
    const employeeMarks=DB_STATE.employee?marks.filter(m=>m.funcionario_id===DB_STATE.employee.id):marks;
    const activeEmployees=employees.filter(f=>f.ativo!==false&&f.status!=='inativo');
    const marksByEmployee=new Map();marks.forEach(m=>{const list=marksByEmployee.get(m.funcionario_id)||[];list.push(m);marksByEmployee.set(m.funcionario_id,list)});
    const presentCount=activeEmployees.filter(f=>(marksByEmployee.get(f.id)||[]).length>0).length;
    const lunchCount=activeEmployees.filter(f=>{const list=(marksByEmployee.get(f.id)||[]).sort((a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em));return list.at(-1)?.tipo==='inicio_intervalo'}).length;
    document.getElementById('presentes-hoje').textContent=String(presentCount);
    document.getElementById('em-almoco').textContent=String(lunchCount);
    document.getElementById('ausentes-hoje').textContent=String(Math.max(0,activeEmployees.length-presentCount));
    const p=employeeMarks.map(m=>new Date(m.registrado_em).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}));
    const sched=scheduleForDateFrom(DB_STATE.schedule,new Date());
    document.getElementById('saudacao-admin').textContent=profile.nome||session.user.email||'Administrador';
    document.getElementById('data-atual').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(new Date());
    document.getElementById('total-func').textContent=String(employees.length);
    const box=document.getElementById('marcacoes-hoje');
    if(p.length){box.classList.remove('empty');box.innerHTML=p.map((x,i)=>`<div class="timeline-item"><span><i>${i+1}</i>${punchLabels[i]||'Marcação'}</span><strong>${x}</strong></div>`).join('');}
    else{box.classList.add('empty');}
    const schedule=DB_STATE.schedule,max=Math.max(...schedule.map(totalDay),1);
    document.getElementById('resumo-jornada').innerHTML=DB_STATE.employee?schedule.map(s=>`<div class="schedule-row-v4"><span class="schedule-day">${s.dia.slice(0,3)}</span><div class="schedule-line"><span style="width:${Math.max(34,Math.round(totalDay(s)/max*100))}%"></span></div><strong class="schedule-time">${s.entrada}–${s.saida}</strong><small class="schedule-break">Intervalo ${s.almoco}–${s.retorno}</small></div>`).join(''):'<div class="mini-empty">Cadastre um funcionário para configurar a jornada.</div>';
    if(p.length===4&&sched){const c=calcPunchDay(p,sched);document.getElementById('saldo-dia').textContent=signedMinutes(c.diff)}
    const next=p.length<4?punchLabels[p.length]:'Concluído';
    const indicators=document.getElementById('daily-indicators');
    if(indicators)indicators.innerHTML=`<article><span>Entrada prevista</span><strong>${sched?.entrada||'—'}</strong></article><article><span>Última marcação</span><strong>${p.at(-1)||'—'}</strong></article><article><span>Próxima etapa</span><strong>${next}</strong></article><article><span>Funcionário</span><strong>${DB_STATE.employee?.nome||'Nenhum cadastrado'}</strong></article>`;
    await renderWeekChartDB();
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}
function scheduleForDateFrom(schedule,d){const map={1:0,2:1,3:2,4:3,5:4};const i=map[d.getDay()];return i===undefined?null:schedule[i]}
async function renderWeekChartDB(){
  const el=document.getElementById('grafico-semana');if(!el)return;
  const now=new Date(),monday=new Date(now),delta=(now.getDay()+6)%7;monday.setDate(now.getDate()-delta);
  const friday=new Date(monday);friday.setDate(monday.getDate()+4);
  const marks=await window.PlenitudeDB.marksForRange(localDateKey(monday),localDateKey(friday));
  const names=['Seg','Ter','Qua','Qui','Sex'],vals=[],expected=[];
  for(let i=0;i<5;i++){const d=new Date(monday);d.setDate(monday.getDate()+i);const s=scheduleForDateFrom(DB_STATE.schedule,d);const p=marks.filter(m=>(!DB_STATE.employee||m.funcionario_id===DB_STATE.employee.id)&&m.data_local===localDateKey(d)).map(m=>new Date(m.registrado_em).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}));const c=calcPunchDay(p,s);vals.push(c?c.worked:0);expected.push(s?totalDay(s):0)}
  const max=Math.max(...vals,...expected,1);el.innerHTML=vals.map((v,i)=>`<div class="chart-column ${v?'':'is-empty'}"><div class="chart-value">${v?fmtMinutes(v):'—'}</div><div class="chart-track"><div class="chart-target" style="height:${Math.round(expected[i]/max*100)}%"></div><div class="chart-bar" style="height:${v?Math.max(8,Math.round(v/max*100)):6}%"></div></div><strong>${names[i]}</strong><small>${v?'Registrado':`Previsto ${fmtMinutes(expected[i])}`}</small></div>`).join('')
}
function renderWeekChart(){const all=getAllPunches(),now=new Date(),monday=new Date(now),delta=(now.getDay()+6)%7;monday.setDate(now.getDate()-delta);const names=['Seg','Ter','Qua','Qui','Sex'],vals=[],expected=[];for(let i=0;i<5;i++){const d=new Date(monday);d.setDate(monday.getDate()+i);const s=scheduleForDate(d),c=calcPunchDay(all[localDateKey(d)]||[],s);vals.push(c?c.worked:0);expected.push(s?totalDay(s):0)}const max=Math.max(...vals,...expected,1);document.getElementById('grafico-semana').innerHTML=vals.map((v,i)=>`<div class="chart-column ${v?'':'is-empty'}"><div class="chart-value">${v?fmtMinutes(v):'—'}</div><div class="chart-track"><div class="chart-target" style="height:${Math.round(expected[i]/max*100)}%"></div><div class="chart-bar" style="height:${v?Math.max(8,Math.round(v/max*100)):6}%"></div></div><strong>${names[i]}</strong><small>${v?'Registrado':`Previsto ${fmtMinutes(expected[i])}`}</small></div>`).join('')}

async function initFuncionarios(){
  const session=await initCommon();if(!session)return;
  const form=document.getElementById('func-form');
  const photoInput=document.getElementById('func-foto');if(photoInput)photoInput.onchange=async()=>{const file=photoInput.files?.[0];if(!file)return;try{window.__employeePhotoData=await resizeEmployeePhoto(file);renderAvatar(window.__employeePhotoData,document.getElementById('nome').value)}catch(error){toast(errorText(error),'warn')}};
  try{
    const employees=await window.PlenitudeDB.employees();DB_STATE.employees=employees;DB_STATE.employee=employees[0]||null;
    fillEmployeeForm(DB_STATE.employee);renderEmployee(DB_STATE.employee);
    form.onsubmit=async e=>{e.preventDefault();const button=form.querySelector('button[type="submit"]');button.disabled=true;button.textContent='Salvando...';try{const values={nome:document.getElementById('nome').value.trim(),cpf:document.getElementById('cpf').value.replace(/\D/g,''),cargo:document.getElementById('cargo').value.trim(),admissao:document.getElementById('admissao').value,email:document.getElementById('func-email').value.trim(),matricula:document.getElementById('matricula')?.value.trim()||null,status:document.getElementById('func-status').value,foto_url:window.__employeePhotoData||DB_STATE.employee?.foto_url||null,codigo_qr:DB_STATE.employee?.codigo_qr||null};const saved=await window.PlenitudeDB.saveEmployee(values,DB_STATE.employee?.id||null);DB_STATE.employee=saved;renderEmployee(saved);toast('Funcionário salvo no Supabase.')}catch(error){toast(errorText(error),'warn');console.error(error)}finally{button.disabled=false;button.textContent='Salvar funcionário'}};
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}
function fillEmployeeForm(f){['nome','cpf','cargo','admissao'].forEach(k=>{const el=document.getElementById(k);if(el)el.value=f?(k==='admissao'?f.data_admissao||'':f[k]||''):''});const email=document.getElementById('func-email');if(email)email.value='';const matricula=document.getElementById('matricula');if(matricula)matricula.value=f?.matricula||'';const status=document.getElementById('func-status');if(status)status.value=f?.status||'ativo';window.__employeePhotoData=f?.foto_url||null}
function employeeStatusLabel(status){return({ativo:'Ativo',ferias:'Férias',afastado:'Afastado',inativo:'Inativo'})[status]||'Ativo'}
function employeeInitials(name=''){return name.trim().split(/\s+/).slice(0,2).map(x=>x[0]).join('').toUpperCase()||'P'}
function renderAvatar(photo,name){const el=document.getElementById('func-avatar');if(!el)return;el.innerHTML=photo?`<img src="${photo}" alt="Foto de ${name||'funcionário'}">`:`<span>${employeeInitials(name)}</span>`}
function renderEmployee(f){document.getElementById('func-nome').textContent=f?.nome||'Nenhum funcionário cadastrado';const status=f?.status||'ativo',badge=document.getElementById('func-status-badge');if(badge){badge.className=`employee-status ${status}`;badge.innerHTML=`<i></i> ${employeeStatusLabel(status)}`};document.getElementById('func-status-top').textContent=f?`1 funcionário ${status==='ativo'?'ativo':'cadastrado'}`:'Nenhum funcionário';renderAvatar(f?.foto_url,f?.nome);document.getElementById('func-detalhes').innerHTML=f?`<span><strong>Cargo:</strong> ${f.cargo||'—'}</span><span><strong>CPF:</strong> ${f.cpf||'—'}</span><span><strong>Matrícula:</strong> ${f.matricula||'—'}</span><span><strong>Admissão:</strong> ${f.data_admissao?new Intl.DateTimeFormat('pt-BR').format(new Date(f.data_admissao+'T12:00:00')):'—'}</span><span><strong>Carga semanal:</strong> ${fmtMinutes(f.carga_semanal_minutos||2640)}</span>`:'<span>Preencha o formulário para cadastrar o primeiro funcionário.</span>';const code=f?.codigo_qr||'';document.getElementById('func-qr-code').textContent=code||'Será gerado ao salvar';const qr=document.getElementById('func-qrcode');if(qr){qr.innerHTML='';if(code&&window.QRCode)new QRCode(qr,{text:`${location.origin}${location.pathname.replace(/funcionarios\.html$/,'ponto.html')}?codigo=${encodeURIComponent(code)}`,width:112,height:112,colorDark:'#2a2526',colorLight:'#ffffff',correctLevel:QRCode.CorrectLevel.M})}}
async function resizeEmployeePhoto(file){if(!file.type.startsWith('image/'))throw new Error('Selecione um arquivo de imagem.');if(file.size>8*1024*1024)throw new Error('A imagem deve ter no máximo 8 MB.');const data=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=()=>reject(new Error('Não foi possível ler a imagem.'));r.readAsDataURL(file)});const img=await new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=()=>reject(new Error('Imagem inválida.'));i.src=data});const size=360,canvas=document.createElement('canvas');canvas.width=size;canvas.height=size;const ctx=canvas.getContext('2d'),scale=Math.max(size/img.width,size/img.height),w=img.width*scale,h=img.height*scale;ctx.drawImage(img,(size-w)/2,(size-h)/2,w,h);return canvas.toDataURL('image/jpeg',.78)}

async function initJornada(){
  const session=await initCommon();if(!session)return;
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
  const session=await initCommon();if(!session)return;
  const clock=()=>{const d=new Date();document.getElementById('clock-date').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(d);document.getElementById('clock-time').textContent=d.toLocaleTimeString('pt-BR')};clock();setInterval(clock,1000);
  try{
    const [profile,employees]=await Promise.all([window.PlenitudeDB.profile(),window.PlenitudeDB.employees()]);
    DB_STATE.profile=profile;DB_STATE.employees=employees;
    const selector=document.getElementById('ponto-funcionario-select');
    if(profile.papel==='administrador'){
      selector.hidden=false;
      selector.innerHTML=employees.length?employees.map(f=>`<option value="${f.id}">${f.nome}</option>`).join(''):'<option value="">Nenhum funcionário cadastrado</option>';
      DB_STATE.employee=employees[0]||null;
      selector.onchange=async()=>{DB_STATE.employee=employees.find(f=>f.id===selector.value)||null;renderClockEmployee(DB_STATE.employee);await loadRealPunches()};
    }else{
      DB_STATE.employee=employees.find(f=>f.auth_user_id===session.user.id)||employees[0]||null;
      selector.hidden=true;
    }
    if(!DB_STATE.employee){document.getElementById('clock-employee').textContent='Nenhum funcionário cadastrado';document.getElementById('registrar').disabled=true;renderRealPunches([]);return}
    renderClockEmployee(DB_STATE.employee);
    await loadRealPunches();
    document.getElementById('registrar').onclick=async()=>{
      const button=document.getElementById('registrar');button.disabled=true;button.classList.add('loading');
      try{const mark=await window.PlenitudeDB.registerPoint(DB_STATE.employee.id);await loadRealPunches();const label=labelForMarkType(mark?.tipo);const time=formatDbTime(mark?.registrado_em);toast(`${label} registrada às ${time}.`)}catch(error){toast(errorText(error),'warn');console.error(error)}finally{button.classList.remove('loading');}
    };
    window.PlenitudeDB.subscribeMarks(async()=>{if(document.visibilityState==='visible')await loadRealPunches()});
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}
function renderClockEmployee(f){if(!f)return;document.getElementById('clock-employee').textContent=f.nome;const status=document.getElementById('clock-status');if(status){status.textContent=employeeStatusLabel(f.status||'ativo');status.className=`${f.status||'ativo'}`};const avatar=document.getElementById('clock-avatar');if(avatar)avatar.innerHTML=f.foto_url?`<img src="${f.foto_url}" alt="Foto de ${f.nome}">`:`<span>${employeeInitials(f.nome)}</span>`}
function labelForMarkType(type){return({entrada:'Entrada',inicio_intervalo:'Início do almoço',fim_intervalo:'Retorno do almoço',saida:'Saída'})[type]||'Marcação'}
function formatDbTime(value){return value?new Date(value).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}):'—'}
async function loadRealPunches(){
  if(!DB_STATE.employee)return renderRealPunches([]);
  renderClockEmployee(DB_STATE.employee);
  const today=localDateKey(),marks=(await window.PlenitudeDB.marksForRange(today,today)).filter(m=>m.funcionario_id===DB_STATE.employee.id);
  renderRealPunches(marks);
}
function renderRealPunches(marks){
  const list=document.getElementById('lista-pontos'),button=document.getElementById('registrar');
  list.innerHTML=marks.length?marks.map(m=>`<div class="punch-item"><span>${labelForMarkType(m.tipo)}</span><strong>${formatDbTime(m.registrado_em)}</strong></div>`).join(''):'<div class="mini-empty">Nenhuma marcação feita hoje.</div>';
  document.getElementById('proxima').textContent=marks.length<4?`Próxima marcação: ${punchLabels[marks.length]}`:'Jornada de hoje concluída';
  if(button)button.disabled=!DB_STATE.employee||marks.length>=4;
  const progress=document.getElementById('punch-progress');if(progress)progress.innerHTML=punchLabels.map((_,i)=>`<span class="progress-step ${i<marks.length?'done':''}"></span>`).join('');
  const steps=document.getElementById('punch-steps');if(steps)steps.innerHTML=punchLabels.map((name,i)=>`<div class="punch-step ${i<marks.length?'done':''} ${i===marks.length?'current':''}"><span class="step-icon">${i<marks.length?'✓':i+1}</span><strong>${name}</strong><small>${marks[i]?formatDbTime(marks[i].registrado_em):'Aguardando'}</small></div>`).join('');
}

async function initRelatorios(){const session=await initCommon();if(!session)return;const month=document.getElementById('rel-mes'),now=new Date();month.value=`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}`;document.getElementById('atualizar-relatorio').onclick=renderRelatorio;document.getElementById('imprimir-relatorio').onclick=()=>window.print();await renderRelatorio()}
async function renderRelatorio(){
  try{
    const selected=document.getElementById('rel-mes').value,[year,month]=selected.split('-').map(Number),last=new Date(year,month,0).getDate();
    const start=`${selected}-01`,end=`${selected}-${String(last).padStart(2,'0')}`;
    const [employees,marks]=await Promise.all([window.PlenitudeDB.employees(),window.PlenitudeDB.marksForRange(start,end)]);
    const employee=employees[0]||null,employeeMarks=employee?marks.filter(m=>m.funcionario_id===employee.id):marks;
    const grouped={};employeeMarks.forEach(m=>(grouped[m.data_local]??=[]).push(m));
    let worked=0,diff=0;const rows=[];
    for(const k of Object.keys(grouped).sort()){
      const d=dateFromKey(k),dayMarks=grouped[k].sort((a,b)=>new Date(a.registrado_em)-new Date(b.registrado_em)),p=dayMarks.map(m=>formatDbTime(m.registrado_em));
      const scheduleRows=employee?dbScheduleToUi(await window.PlenitudeDB.schedules(employee.id)):defaultSchedule,c=calcPunchDay(p,scheduleForDateFrom(scheduleRows,d));
      if(c){worked+=c.worked;diff+=c.diff}rows.push({k,p,c});
    }
    document.getElementById('rel-dias').textContent=rows.length;document.getElementById('rel-horas').textContent=fmtMinutes(worked);document.getElementById('rel-saldo').textContent=signedMinutes(diff);
    const body=document.getElementById('relatorio-body'),empty=document.getElementById('relatorio-vazio');body.innerHTML=rows.map(r=>`<tr><td>${new Intl.DateTimeFormat('pt-BR').format(dateFromKey(r.k))}</td>${[0,1,2,3].map(i=>`<td>${r.p[i]||'—'}</td>`).join('')}<td>${r.c?fmtMinutes(r.c.worked):'—'}</td><td class="${r.c&&r.c.diff<0?'negative':'positive'}">${r.c?signedMinutes(r.c.diff):'—'}</td></tr>`).join('');empty.style.display=rows.length?'none':'block';
  }catch(error){toast(errorText(error),'warn');console.error(error)}
}

async function initConfiguracoes(){const session=await initCommon();if(!session)return;const cfg=getConfig();document.getElementById('empresa-nome').value=cfg.empresaNome||'Livraria Plenitude';document.getElementById('empresa-endereco').value=cfg.endereco||'Av. Primeira Avenida, 231, Shopping Laranjeiras, Serra/ES';document.getElementById('admin-nome').value=cfg.adminNome||'Administrador';document.getElementById('admin-email').value=cfg.adminEmail||'admin@plenitude.local';document.getElementById('config-form').onsubmit=e=>{e.preventDefault();writeJSON(STORAGE.config,{empresaNome:document.getElementById('empresa-nome').value,endereco:document.getElementById('empresa-endereco').value,adminNome:document.getElementById('admin-nome').value,adminEmail:document.getElementById('admin-email').value});toast('Configurações salvas com sucesso.')};document.getElementById('exportar-backup').onclick=()=>{const data={employee:getEmployee(),schedule:getSchedule(),punches:getAllPunches(),events:getEvents(),config:getConfig(),exportedAt:new Date().toISOString()};const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`plenitude-ponto-backup-${localDateKey()}.json`;a.click();URL.revokeObjectURL(a.href)};document.getElementById('limpar-marcacoes').onclick=()=>{if(confirm('Apagar todas as marcações de teste deste navegador?')){localStorage.removeItem(STORAGE.punches);toast('Marcações apagadas.')}}}

let calendarCursor=new Date();
async function initCalendario(){const session=await initCommon();if(!session)return;calendarCursor=new Date();document.getElementById('cal-prev').onclick=()=>{calendarCursor.setMonth(calendarCursor.getMonth()-1);renderCalendar()};document.getElementById('cal-next').onclick=()=>{calendarCursor.setMonth(calendarCursor.getMonth()+1);renderCalendar()};document.getElementById('event-form').onsubmit=e=>{e.preventDefault();const date=document.getElementById('event-date').value,type=document.getElementById('event-type').value,note=document.getElementById('event-note').value.trim();if(!date)return;const events=getEvents();events[date]={type,note};writeJSON(STORAGE.events,events);toast('Evento salvo no calendário.');renderCalendar()};renderCalendar()}
function renderCalendar(){const year=calendarCursor.getFullYear(),month=calendarCursor.getMonth(),first=new Date(year,month,1),last=new Date(year,month+1,0),events=getEvents(),punches=getAllPunches();document.getElementById('cal-title').textContent=new Intl.DateTimeFormat('pt-BR',{month:'long',year:'numeric'}).format(first);const grid=document.getElementById('calendar-grid');grid.innerHTML=['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'].map(x=>`<div class="cal-weekday">${x}</div>`).join('');for(let i=0;i<first.getDay();i++)grid.insertAdjacentHTML('beforeend','<div class="cal-day muted-day"></div>');for(let day=1;day<=last.getDate();day++){const d=new Date(year,month,day),key=localDateKey(d),ev=events[key],p=punches[key]||[],today=key===localDateKey();grid.insertAdjacentHTML('beforeend',`<button class="cal-day ${today?'today':''} ${ev?'has-event':''} ${p.length?'has-punch':''}" data-date="${key}"><span>${day}</span>${p.length?`<small>${p.length}/4 pontos</small>`:''}${ev?`<em>${ev.type}</em>`:''}</button>`)}grid.querySelectorAll('[data-date]').forEach(btn=>btn.onclick=()=>{const key=btn.dataset.date,ev=events[key];document.getElementById('event-date').value=key;document.getElementById('event-type').value=ev?.type||'Folga';document.getElementById('event-note').value=ev?.note||''})}
