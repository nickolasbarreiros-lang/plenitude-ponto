const defaultSchedule=[{dia:'Segunda',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'19:00'},{dia:'Terça',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'19:00'},{dia:'Quarta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'18:00'},{dia:'Quinta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'18:30'},{dia:'Sexta',entrada:'09:00',almoco:'13:00',retorno:'13:30',saida:'17:00'}];
const demoEmployee={nome:'Funcionário da loja',cpf:'',cargo:'Atendente',admissao:'',email:''};
function requireAuth(){if(sessionStorage.getItem('plenitudeAuth')!=='1')location.href='index.html'}
function bindLogout(){const b=document.getElementById('sair');if(b)b.onclick=()=>{sessionStorage.removeItem('plenitudeAuth');location.href='index.html'}}
function getSchedule(){return JSON.parse(localStorage.getItem('plenitudeSchedule')||'null')||defaultSchedule}
function getEmployee(){return JSON.parse(localStorage.getItem('plenitudeEmployee')||'null')||demoEmployee}
function localDateKey(d=new Date()){return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function getPunches(){const all=JSON.parse(localStorage.getItem('plenitudePunches')||'{}');return all[localDateKey()]||[]}
function savePunches(list){const all=JSON.parse(localStorage.getItem('plenitudePunches')||'{}');all[localDateKey()]=list;localStorage.setItem('plenitudePunches',JSON.stringify(all))}
function minutes(a,b){const [h1,m1]=a.split(':').map(Number),[h2,m2]=b.split(':').map(Number);return(h2*60+m2)-(h1*60+m1)}
function totalDay(s){return minutes(s.entrada,s.almoco)+minutes(s.retorno,s.saida)}
function fmtMinutes(n){const h=Math.floor(n/60),m=n%60;return`${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`}
function todaySchedule(){const day=new Date().getDay();const map={1:0,2:1,3:2,4:3,5:4};return map[day]!==undefined?getSchedule()[map[day]]:null}
function labels(){return['Entrada','Início do almoço','Retorno do almoço','Saída']}
function initCommon(){requireAuth();bindLogout()}
function initAdmin(){initCommon();document.getElementById('data-atual').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(new Date());document.getElementById('total-func').textContent='1';const p=getPunches(),box=document.getElementById('marcacoes-hoje');if(p.length){box.classList.remove('empty');box.innerHTML=p.map((x,i)=>`<div class="timeline-item"><span>${labels()[i]||'Marcação'}</span><strong>${x}</strong></div>`).join('');document.getElementById('status-hoje').textContent=p.length>=4?'Jornada concluída':'Em andamento';document.getElementById('ultima-marcacao').textContent=`Última: ${p[p.length-1]}`}const sched=getSchedule();document.getElementById('resumo-jornada').innerHTML=sched.map(s=>`<div class="schedule-row"><span>${s.dia}</span><strong>${s.entrada}–${s.saida}</strong></div>`).join('');if(p.length===4&&todaySchedule()){const worked=minutes(p[0],p[1])+minutes(p[2],p[3]),expected=totalDay(todaySchedule()),diff=worked-expected;document.getElementById('saldo-dia').textContent=`${diff>=0?'+':'−'}${fmtMinutes(Math.abs(diff))}`}}
function initFuncionarios(){initCommon();const f=getEmployee();['nome','cpf','cargo','admissao'].forEach(k=>document.getElementById(k).value=f[k]||'');document.getElementById('func-email').value=f.email||'';renderEmployee(f);document.getElementById('func-form').onsubmit=e=>{e.preventDefault();const n={nome:document.getElementById('nome').value,cpf:document.getElementById('cpf').value,cargo:document.getElementById('cargo').value,admissao:document.getElementById('admissao').value,email:document.getElementById('func-email').value};localStorage.setItem('plenitudeEmployee',JSON.stringify(n));renderEmployee(n);alert('Funcionário salvo com sucesso.')}}
function renderEmployee(f){document.getElementById('func-nome').textContent=f.nome||'Funcionário da loja';document.getElementById('func-detalhes').innerHTML=`<span><strong>Cargo:</strong> ${f.cargo||'—'}</span><span><strong>CPF:</strong> ${f.cpf||'—'}</span><span><strong>Admissão:</strong> ${f.admissao||'—'}</span><span><strong>E-mail:</strong> ${f.email||'—'}</span>`}
function initJornada(){initCommon();const tbody=document.getElementById('jornada-body');getSchedule().forEach((s,i)=>tbody.insertAdjacentHTML('beforeend',`<tr data-i="${i}"><td><strong>${s.dia}</strong></td><td><input type="time" name="entrada" value="${s.entrada}"></td><td><input type="time" name="almoco" value="${s.almoco}"></td><td><input type="time" name="retorno" value="${s.retorno}"></td><td><input type="time" name="saida" value="${s.saida}"></td><td class="total-dia">${fmtMinutes(totalDay(s))}</td></tr>`));tbody.addEventListener('input',updateTotals);updateTotals();document.getElementById('jornada-form').onsubmit=e=>{e.preventDefault();const arr=[...tbody.querySelectorAll('tr')].map(tr=>({dia:tr.cells[0].innerText,entrada:tr.querySelector('[name=entrada]').value,almoco:tr.querySelector('[name=almoco]').value,retorno:tr.querySelector('[name=retorno]').value,saida:tr.querySelector('[name=saida]').value}));localStorage.setItem('plenitudeSchedule',JSON.stringify(arr));updateTotals();alert('Jornada salva com sucesso.')}}
function updateTotals(){let weekly=0;document.querySelectorAll('#jornada-body tr').forEach(tr=>{const g=n=>tr.querySelector(`[name=${n}]`).value,s={entrada:g('entrada'),almoco:g('almoco'),retorno:g('retorno'),saida:g('saida')},t=totalDay(s);weekly+=t;tr.querySelector('.total-dia').textContent=fmtMinutes(t)});document.getElementById('total-semanal').textContent=fmtMinutes(weekly)}
function initPonto(){requireAuth();document.getElementById('clock-employee').textContent=getEmployee().nome;const clock=()=>{const d=new Date();document.getElementById('clock-date').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(d);document.getElementById('clock-time').textContent=d.toLocaleTimeString('pt-BR')};clock();setInterval(clock,1000);renderPunches();document.getElementById('registrar').onclick=()=>{const p=getPunches();if(p.length>=4){alert('As quatro marcações de hoje já foram registradas.');return}p.push(new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}));savePunches(p);renderPunches()}}
function renderPunches(){const p=getPunches();document.getElementById('lista-pontos').innerHTML=p.map((x,i)=>`<div class="punch-item"><span>${labels()[i]}</span><strong>${x}</strong></div>`).join('');document.getElementById('proxima').textContent=p.length<4?`Próxima marcação: ${labels()[p.length]}`:'Jornada de hoje concluída';document.getElementById('registrar').disabled=p.length>=4}


function getAllPunches(){return JSON.parse(localStorage.getItem('plenitudePunches')||'{}')}
function dateFromKey(k){const [y,m,d]=k.split('-').map(Number);return new Date(y,m-1,d)}
function scheduleForDate(d){const map={1:0,2:1,3:2,4:3,5:4};const i=map[d.getDay()];return i===undefined?null:getSchedule()[i]}
function calcPunchDay(p,s){if(!p||p.length<4||!s)return null;const worked=minutes(p[0],p[1])+minutes(p[2],p[3]);return{worked,expected:totalDay(s),diff:worked-totalDay(s)}}
function initAdmin(){initCommon();const cfg=JSON.parse(localStorage.getItem('plenitudeConfig')||'{}');document.getElementById('saudacao-admin').textContent=cfg.adminNome||'Administrador';document.getElementById('data-atual').textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(new Date());document.getElementById('total-func').textContent='1';const p=getPunches(),box=document.getElementById('marcacoes-hoje');if(p.length){box.classList.remove('empty');box.innerHTML=p.map((x,i)=>`<div class="timeline-item"><span>${labels()[i]||'Marcação'}</span><strong>${x}</strong></div>`).join('');document.getElementById('status-hoje').textContent=p.length>=4?'Jornada concluída':'Em andamento';document.getElementById('ultima-marcacao').textContent=`Última: ${p[p.length-1]}`}const sched=getSchedule();document.getElementById('resumo-jornada').innerHTML=sched.map(s=>`<div class="schedule-row"><span>${s.dia}</span><strong>${s.entrada}–${s.saida}</strong></div>`).join('');if(p.length===4&&todaySchedule()){const c=calcPunchDay(p,todaySchedule());document.getElementById('saldo-dia').textContent=`${c.diff>=0?'+':'−'}${fmtMinutes(Math.abs(c.diff))}`}renderWeekChart()}
function renderWeekChart(){const all=getAllPunches(),now=new Date(),monday=new Date(now);const delta=(now.getDay()+6)%7;monday.setDate(now.getDate()-delta);const names=['Seg','Ter','Qua','Qui','Sex'];const vals=[];for(let i=0;i<5;i++){const d=new Date(monday);d.setDate(monday.getDate()+i);const p=all[localDateKey(d)]||[];const c=calcPunchDay(p,scheduleForDate(d));vals.push(c?c.worked:0)}const max=Math.max(600,...vals);document.getElementById('grafico-semana').innerHTML=vals.map((v,i)=>`<div class="chart-column"><div class="chart-track"><div class="chart-bar" style="height:${Math.max(v?8:0,Math.round(v/max*100))}%"></div></div><strong>${names[i]}</strong><small>${fmtMinutes(v)}</small></div>`).join('')}
function renderPunches(){const p=getPunches();document.getElementById('lista-pontos').innerHTML=p.map((x,i)=>`<div class="punch-item"><span>${labels()[i]}</span><strong>${x}</strong></div>`).join('');document.getElementById('proxima').textContent=p.length<4?`Próxima marcação: ${labels()[p.length]}`:'Jornada de hoje concluída';document.getElementById('registrar').disabled=p.length>=4;const progress=document.getElementById('punch-progress');if(progress)progress.innerHTML=labels().map((_,i)=>`<span class="progress-step ${i<p.length?'done':''}"></span>`).join('')}
function initRelatorios(){initCommon();const month=document.getElementById('rel-mes');const now=new Date();month.value=`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}`;document.getElementById('atualizar-relatorio').onclick=renderRelatorio;document.getElementById('imprimir-relatorio').onclick=()=>window.print();renderRelatorio()}
function renderRelatorio(){const selected=document.getElementById('rel-mes').value,all=getAllPunches(),rows=[];let worked=0,diff=0;Object.keys(all).sort().forEach(k=>{if(!k.startsWith(selected))return;const d=dateFromKey(k),p=all[k],s=scheduleForDate(d),c=calcPunchDay(p,s);if(c){worked+=c.worked;diff+=c.diff}rows.push({k,p,c})});document.getElementById('rel-dias').textContent=rows.length;document.getElementById('rel-horas').textContent=fmtMinutes(worked);document.getElementById('rel-saldo').textContent=`${diff>=0?'+':'−'}${fmtMinutes(Math.abs(diff))}`;const body=document.getElementById('relatorio-body'),empty=document.getElementById('relatorio-vazio');body.innerHTML=rows.map(r=>`<tr><td>${new Intl.DateTimeFormat('pt-BR').format(dateFromKey(r.k))}</td>${[0,1,2,3].map(i=>`<td>${r.p[i]||'—'}</td>`).join('')}<td>${r.c?fmtMinutes(r.c.worked):'—'}</td><td>${r.c?`${r.c.diff>=0?'+':'−'}${fmtMinutes(Math.abs(r.c.diff))}`:'—'}</td></tr>`).join('');empty.style.display=rows.length?'none':'block'}
function initConfiguracoes(){initCommon();const cfg=JSON.parse(localStorage.getItem('plenitudeConfig')||'{}');document.getElementById('empresa-nome').value=cfg.empresaNome||'Livraria Plenitude';document.getElementById('empresa-endereco').value=cfg.endereco||'Av. Primeira Avenida, 231, Shopping Laranjeiras, Serra/ES';document.getElementById('admin-nome').value=cfg.adminNome||'Administrador';document.getElementById('admin-email').value=cfg.adminEmail||'admin@plenitude.local';document.getElementById('config-form').onsubmit=e=>{e.preventDefault();localStorage.setItem('plenitudeConfig',JSON.stringify({empresaNome:document.getElementById('empresa-nome').value,endereco:document.getElementById('empresa-endereco').value,adminNome:document.getElementById('admin-nome').value,adminEmail:document.getElementById('admin-email').value}));alert('Configurações salvas com sucesso.')};document.getElementById('exportar-backup').onclick=()=>{const data={employee:getEmployee(),schedule:getSchedule(),punches:getAllPunches(),config:JSON.parse(localStorage.getItem('plenitudeConfig')||'{}'),exportedAt:new Date().toISOString()};const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`plenitude-ponto-backup-${localDateKey()}.json`;a.click();URL.revokeObjectURL(a.href)};document.getElementById('limpar-marcacoes').onclick=()=>{if(confirm('Apagar todas as marcações de teste deste navegador?')){localStorage.removeItem('plenitudePunches');alert('Marcações apagadas.')}}}

/* refinamentos v4 */
function initAdmin(){
  initCommon();
  const cfg=JSON.parse(localStorage.getItem('plenitudeConfig')||'{}');
  const saudacao=document.getElementById('saudacao-admin');
  if(saudacao)saudacao.textContent=cfg.adminNome||'Administrador';
  const data=document.getElementById('data-atual');
  if(data)data.textContent=new Intl.DateTimeFormat('pt-BR',{dateStyle:'full'}).format(new Date());
  document.getElementById('total-func').textContent='1';

  const p=getPunches(),box=document.getElementById('marcacoes-hoje');
  if(p.length){
    box.classList.remove('empty');
    box.innerHTML=p.map((x,i)=>`<div class="timeline-item"><span>${labels()[i]||'Marcação'}</span><strong>${x}</strong></div>`).join('');
    document.getElementById('status-hoje').textContent=p.length>=4?'Jornada concluída':'Em andamento';
    document.getElementById('ultima-marcacao').textContent=`Última: ${p[p.length-1]}`;
  }

  const sched=getSchedule();
  const maxMinutes=Math.max(...sched.map(totalDay),1);
  document.getElementById('resumo-jornada').innerHTML=sched.map(s=>{
    const pct=Math.max(34,Math.round(totalDay(s)/maxMinutes*100));
    return `<div class="schedule-row-v4"><span class="schedule-day">${s.dia.slice(0,3)}</span><div class="schedule-line"><span style="width:${pct}%"></span></div><strong class="schedule-time">${s.entrada}–${s.saida}</strong><small class="schedule-break">Intervalo ${s.almoco}–${s.retorno}</small></div>`;
  }).join('');

  if(p.length===4&&todaySchedule()){
    const c=calcPunchDay(p,todaySchedule());
    document.getElementById('saldo-dia').textContent=`${c.diff>=0?'+':'−'}${fmtMinutes(Math.abs(c.diff))}`;
  }
  renderWeekChart();
}

function renderWeekChart(){
  const all=getAllPunches(),now=new Date(),monday=new Date(now);
  const delta=(now.getDay()+6)%7;monday.setDate(now.getDate()-delta);
  const names=['Seg','Ter','Qua','Qui','Sex'],vals=[],expected=[];
  for(let i=0;i<5;i++){
    const d=new Date(monday);d.setDate(monday.getDate()+i);
    const s=scheduleForDate(d),p=all[localDateKey(d)]||[],c=calcPunchDay(p,s);
    vals.push(c?c.worked:0);expected.push(s?totalDay(s):0);
  }
  const max=Math.max(600,...vals,...expected);
  document.getElementById('grafico-semana').innerHTML=vals.map((v,i)=>{
    const visual=v||Math.round(expected[i]*.18);
    const h=Math.max(12,Math.round(visual/max*100));
    return `<div class="chart-column ${v?'':'is-empty'}"><div class="chart-track"><div class="chart-bar" style="height:${h}%"></div></div><strong>${names[i]}</strong><small>${v?fmtMinutes(v):'Sem registro'}</small></div>`;
  }).join('');
}

function renderPunches(){
  const p=getPunches(),names=labels();
  const list=document.getElementById('lista-pontos');
  list.innerHTML=p.map((x,i)=>`<div class="punch-item"><span>${names[i]}</span><strong>${x}</strong></div>`).join('');
  document.getElementById('proxima').textContent=p.length<4?`Próxima marcação: ${names[p.length]}`:'Jornada de hoje concluída';
  document.getElementById('registrar').disabled=p.length>=4;
  const progress=document.getElementById('punch-progress');
  if(progress)progress.innerHTML=names.map((_,i)=>`<span class="progress-step ${i<p.length?'done':''}"></span>`).join('');
  const steps=document.getElementById('punch-steps');
  if(steps)steps.innerHTML=names.map((name,i)=>`<div class="punch-step ${i<p.length?'done':''}"><span class="step-icon">${i<p.length?'✓':i+1}</span><strong>${name}</strong><small>${p[i]||'Aguardando'}</small></div>`).join('');
}
