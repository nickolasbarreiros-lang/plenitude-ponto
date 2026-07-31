(function(){
'use strict';

const DB_NAME='plenitude-contingencia';
const DB_VERSION=1;
const STORE='registros';
const META='meta';
let dbPromise=null;

function openDB(){
 if(dbPromise)return dbPromise;
 dbPromise=new Promise((resolve,reject)=>{
  const request=indexedDB.open(DB_NAME,DB_VERSION);
  request.onupgradeneeded=()=>{
   const db=request.result;
   if(!db.objectStoreNames.contains(STORE)){
    const store=db.createObjectStore(STORE,{keyPath:'evento_offline_id'});
    store.createIndex('status','status');
    store.createIndex('data_local','data_local');
   }
   if(!db.objectStoreNames.contains(META))db.createObjectStore(META,{keyPath:'key'});
  };
  request.onsuccess=()=>resolve(request.result);
  request.onerror=()=>reject(request.error);
 });
 return dbPromise;
}

async function tx(storeName,mode,callback){
 const db=await openDB();
 return new Promise((resolve,reject)=>{
  const transaction=db.transaction(storeName,mode);
  const store=transaction.objectStore(storeName);
  let result;
  try{result=callback(store,transaction)}catch(error){reject(error);return}
  transaction.oncomplete=()=>resolve(result);
  transaction.onerror=()=>reject(transaction.error);
  transaction.onabort=()=>reject(transaction.error);
 });
}

function requestResult(request){
 return new Promise((resolve,reject)=>{
  request.onsuccess=()=>resolve(request.result);
  request.onerror=()=>reject(request.error);
 });
}

async function all(){
 const db=await openDB();
 return requestResult(db.transaction(STORE,'readonly').objectStore(STORE).getAll());
}

async function pending(){
 return (await all()).filter(item=>item.status==='local'||item.status==='erro');
}

async function put(record){
 const db=await openDB();
 await requestResult(db.transaction(STORE,'readwrite').objectStore(STORE).put(record));
 return record;
}

async function remove(id){
 const db=await openDB();
 await requestResult(db.transaction(STORE,'readwrite').objectStore(STORE).delete(id));
}

async function setMeta(key,value){
 const db=await openDB();
 await requestResult(db.transaction(META,'readwrite').objectStore(META).put({key,value}));
}

async function getMeta(key){
 const db=await openDB();
 const row=await requestResult(db.transaction(META,'readonly').objectStore(META).get(key));
 return row?.value;
}

function uuid(){
 return crypto.randomUUID?crypto.randomUUID():
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{
   const r=Math.random()*16|0,v=c==='x'?r:(r&3|8);return v.toString(16);
  });
}

async function sha256(text){
 if(!crypto.subtle)return '';
 const data=new TextEncoder().encode(text);
 const digest=await crypto.subtle.digest('SHA-256',data);
 return Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
}

async function createRecord({employee,tipo,deviceToken,existing=[]}){
 const now=new Date();
 const previous=(await pending()).sort((a,b)=>a.criado_local_em.localeCompare(b.criado_local_em)).at(-1);
 const evento=uuid();
 const payload={
  evento_offline_id:evento,
  funcionario_id:employee.id,
  funcionario_nome:employee.nome,
  matricula:employee.matricula,
  tipo,
  ocorrido_em_dispositivo:now.toISOString(),
  data_local:`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`,
  fuso_horario:Intl.DateTimeFormat().resolvedOptions().timeZone||'America/Sao_Paulo',
  offset_minutos:now.getTimezoneOffset(),
  criado_local_em:now.toISOString(),
  hash_anterior:previous?.hash_evento||'',
  user_agent:navigator.userAgent,
  status:'local',
  tentativas:0
 };
 payload.hash_evento=await sha256(JSON.stringify({...payload,deviceToken:deviceToken.slice(-8)}));
 await put(payload);
 return payload;
}

async function counts(){
 const rows=await all();
 return {
  local:rows.filter(r=>r.status==='local'||r.status==='erro').length,
  sincronizado:rows.filter(r=>r.status==='sincronizado').length,
  total:rows.length
 };
}

async function syncOne(record,client,deviceToken){
 const {data,error}=await client.rpc('sincronizar_marcacao_contingencia',{
  p_dispositivo_token:deviceToken,
  p_evento_offline_id:record.evento_offline_id,
  p_funcionario_id:record.funcionario_id,
  p_tipo:record.tipo,
  p_ocorrido_em_dispositivo:record.ocorrido_em_dispositivo,
  p_data_local:record.data_local,
  p_fuso_horario:record.fuso_horario,
  p_offset_minutos:record.offset_minutos,
  p_criado_local_em:record.criado_local_em,
  p_hash_evento:record.hash_evento||null,
  p_hash_anterior:record.hash_anterior||null,
  p_user_agent:record.user_agent
 });
 if(error)throw error;
 record.status='sincronizado';
 record.sincronizado_em=new Date().toISOString();
 record.servidor=Array.isArray(data)?data[0]:data;
 await put(record);
 return record;
}

async function syncAll(client,deviceToken){
 const queue=await pending();
 const results=[];
 for(const record of queue){
  try{
   results.push(await syncOne(record,client,deviceToken));
  }catch(error){
   record.status='erro';
   record.tentativas=(record.tentativas||0)+1;
   record.ultimo_erro=error.message||String(error);
   await put(record);
   if(/Failed to fetch|NetworkError|Load failed|fetch/i.test(record.ultimo_erro))break;
  }
 }
 return results;
}

async function selfTest(){
 const testId=`diagnostico-${uuid()}`;
 const now=new Date().toISOString();
 const record={
  evento_offline_id:testId,
  funcionario_id:'diagnostico-local',
  funcionario_nome:'DIAGNÓSTICO LOCAL',
  matricula:'TESTE',
  tipo:'entrada',
  ocorrido_em_dispositivo:now,
  data_local:now.slice(0,10),
  fuso_horario:Intl.DateTimeFormat().resolvedOptions().timeZone||'America/Sao_Paulo',
  offset_minutos:new Date().getTimezoneOffset(),
  criado_local_em:now,
  hash_anterior:'',
  hash_evento:await sha256(testId),
  user_agent:navigator.userAgent,
  status:'diagnostico'
 };

 await put(record);
 const rows=await all();
 const readBack=rows.find(item=>item.evento_offline_id===testId);
 await remove(testId);
 const after=await all();

 return {
  write:Boolean(readBack),
  read:Boolean(readBack&&readBack.hash_evento===record.hash_evento),
  cleanup:!after.some(item=>item.evento_offline_id===testId)
 };
}

window.PlenitudeOffline=Object.freeze({
 openDB,all,pending,put,remove,createRecord,counts,syncAll,setMeta,getMeta,selfTest
});
})();