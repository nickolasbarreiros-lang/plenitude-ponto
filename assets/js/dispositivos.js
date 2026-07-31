(function(){
 'use strict';

 const client=window.PlenitudeAuth.client;
 const KEY='plenitude-device-token';

 const token=()=>localStorage.getItem(KEY)||'';

 function randomToken(){
  const bytes=new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes,value=>value.toString(16).padStart(2,'0')).join('');
 }

 function fmt(value){
  return value?new Date(value).toLocaleString('pt-BR'):'—';
 }

 function typeLabel(type){
  return {
   terminal:'Terminal da loja',
   homologacao:'Homologação',
   contingencia:'Contingência'
  }[type]||'Dispositivo';
 }

 async function rpc(name,args={}){
  const {data,error}=await client.rpc(name,args);
  if(error)throw error;
  return data;
 }

 async function currentStatus(){
  const box=document.getElementById('current-device-status');
  const badge=document.getElementById('device-badge');

  try{
   const data=await rpc('validar_dispositivo_ponto_detalhado',{p_token:token()});
   const result=Array.isArray(data)?data[0]:data;

   if(result?.autorizado){
    box.dataset.deviceId=result.id||'';
    box.className='device-status-box authorized';
    box.innerHTML=`
     <strong>✓ Este navegador está autorizado</strong>
     <span>${result.nome||'Computador autorizado'} · ${typeLabel(result.tipo)}</span>`;
    badge.textContent='Autorizado';
    badge.classList.add('success');
   }else{
    box.dataset.deviceId='';
    box.className='device-status-box blocked';
    box.innerHTML=`
     <strong>Este navegador não está autorizado</strong>
     <span>Você pode autorizá-lo sem revogar os demais equipamentos.</span>`;
    badge.textContent='Não autorizado';
    badge.classList.remove('success');
   }

   return result||null;
  }catch(error){
   box.dataset.deviceId='';
   box.textContent=error.message;
   badge.textContent='Erro';
   badge.classList.remove('success');
   return null;
  }
 }

 async function list(){
  const data=await rpc('listar_dispositivos_ponto_multi_admin');
  const box=document.getElementById('device-list');
  const rows=data||[];
  const currentId=document.getElementById('current-device-status').dataset.deviceId||'';

  const activeCount=rows.filter(row=>row.ativo).length;

  box.innerHTML=rows.length
   ?`<div class="device-list-summary">
      <strong>${activeCount} dispositivo${activeCount===1?'':'s'} ativo${activeCount===1?'':'s'}</strong>
      <span>Limite operacional: 10 ativos</span>
     </div>`+
     rows.map(device=>{
      const isCurrent=device.id===currentId;
      return `<div class="device-row ${device.ativo?'active':''} ${isCurrent?'current':''}">
       <div>
        <div class="device-title-line">
         <strong>${device.nome}</strong>
         <span class="device-type">${typeLabel(device.tipo)}</span>
         ${isCurrent?'<span class="device-current">Este navegador</span>':''}
        </div>
        <small>${device.ativo?'Ativo':'Revogado'} · autorizado em ${fmt(device.autorizado_em)}</small>
        <small>Último uso: ${fmt(device.ultimo_uso_em)}</small>
        ${device.observacao?`<small>Observação: ${device.observacao}</small>`:''}
       </div>
       ${device.ativo
        ?`<button class="btn outline danger revoke-device" data-id="${device.id}" data-current="${isCurrent}" type="button">Revogar</button>`
        :''}
      </div>`;
     }).join('')
   :'<div class="mini-empty">Nenhum computador autorizado.</div>';

  box.querySelectorAll('.revoke-device').forEach(button=>{
   button.onclick=async()=>{
    const isCurrent=button.dataset.current==='true';
    const warning=isCurrent
     ?'Revogar este navegador? Ele deixará de registrar ponto imediatamente.'
     :'Revogar este computador? Os demais continuarão funcionando normalmente.';

    if(!confirm(warning))return;

    const reason=prompt('Motivo da revogação (opcional):')||'';
    const masterPin=prompt('Digite o PIN Mestre de 6 números para confirmar:')||'';

    if(!/^\d{6}$/.test(masterPin)){
     toast('PIN Mestre inválido.','warn');
     return;
    }

    button.disabled=true;

    try{
     await rpc('revogar_dispositivo_ponto_master_admin',{
      p_id:button.dataset.id,
      p_motivo:reason,
      p_master_pin:masterPin
     });

     if(isCurrent){
      localStorage.removeItem(KEY);
     }

     toast(
      isCurrent
       ?'Este navegador foi revogado.'
       :'Dispositivo revogado. Os demais permanecem ativos.'
     );

     await currentStatus();
     await list();
    }catch(error){
     toast(error.message,'warn');
    }finally{
     button.disabled=false;
    }
   };
  });
 }

 document.getElementById('authorize-device-form').onsubmit=async event=>{
  event.preventDefault();

  const button=event.submitter;
  button.disabled=true;

  try{
   const current=await currentStatus();

   if(current?.autorizado){
    throw new Error('Este navegador já está autorizado. Revogue-o antes de gerar uma nova autorização.');
   }

   const masterPin=prompt('Digite o PIN Mestre de 6 números para autorizar este computador:')||'';

   if(!/^\d{6}$/.test(masterPin)){
    throw new Error('PIN Mestre inválido.');
   }

   const newToken=randomToken();

   await rpc('autorizar_dispositivo_ponto_multi_master_admin',{
    p_token:newToken,
    p_nome:document.getElementById('device-name').value,
    p_tipo:document.getElementById('device-type').value,
    p_user_agent:navigator.userAgent,
    p_master_pin:masterPin
   });

   localStorage.setItem(KEY,newToken);

   toast('Computador autorizado sem revogar os demais.');

   await currentStatus();
   await list();
  }catch(error){
   toast(error.message,'warn');
  }finally{
   button.disabled=false;
  }
 };

 (async()=>{
  try{
   await window.PlenitudeAuth.requireAccess({roles:['administrador']});
   await currentStatus();
   await list();
  }catch(error){
   toast(error.message,'warn');
  }
 })();
})();