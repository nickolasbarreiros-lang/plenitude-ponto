(function(){
'use strict';

const DEFAULT_TIMEZONE='America/Sao_Paulo';
const SYNC_INTERVAL=5*60*1000;
const WARNING_THRESHOLD_MS=60*1000;

let offsetMs=0;
let timezone=DEFAULT_TIMEZONE;
let source='local';
let lastSyncAt=null;
let syncing=null;
let listeners=new Set();

function localNow(){
 return new Date();
}

function now(){
 return new Date(Date.now()+offsetMs);
}

function info(){
 return {
  now:now(),
  timezone,
  source,
  offsetMs,
  lastSyncAt,
  online:navigator.onLine
 };
}

function emit(){
 const snapshot=info();
 listeners.forEach(listener=>{
  try{listener(snapshot);}catch(error){console.warn(error);}
 });
 window.dispatchEvent(new CustomEvent('plenitude-clock-change',{detail:snapshot}));
}

async function sync(){
 if(syncing)return syncing;

 syncing=(async()=>{
  if(!navigator.onLine){
   source='local';
   offsetMs=0;
   emit();
   return info();
  }

  const started=Date.now();

  try{
   const client=window.PlenitudeAuth?.client;
   if(!client)throw new Error('Cliente Supabase indisponível.');

   const {data,error}=await client.rpc('horario_oficial_sistema');
   if(error)throw error;

   const row=Array.isArray(data)?data[0]:data;
   if(!row?.agora)throw new Error('Horário oficial não retornado.');

   const finished=Date.now();
   const midpoint=started+((finished-started)/2);
   const serverMs=new Date(row.agora).getTime();

   offsetMs=serverMs-midpoint;
   timezone=row.timezone||DEFAULT_TIMEZONE;
   source='server';
   lastSyncAt=new Date();

   emit();
   return info();
  }catch(error){
   console.warn('Falha ao sincronizar o horário oficial.',error);

   /*
    * Online sem resposta do relógio oficial não deve fingir que a hora local
    * é oficial. Mantemos a origem como indisponível para sinalização visual.
    */
   source=navigator.onLine?'unavailable':'local';
   offsetMs=0;
   emit();
   return info();
  }finally{
   syncing=null;
  }
 })();

 return syncing;
}

function subscribe(listener){
 listeners.add(listener);
 listener(info());
 return ()=>listeners.delete(listener);
}

function formatDate(date=now(),options={}){
 return new Intl.DateTimeFormat('pt-BR',{
  timeZone:timezone,
  ...options
 }).format(date);
}

function formatTime(date=now(),options={}){
 return new Intl.DateTimeFormat('pt-BR',{
  timeZone:timezone,
  hour:'2-digit',
  minute:'2-digit',
  second:'2-digit',
  hour12:false,
  ...options
 }).format(date);
}

function differenceWarning(){
 const absolute=Math.abs(offsetMs);
 if(source!=='server'||absolute<WARNING_THRESHOLD_MS)return null;

 const minutes=Math.round(absolute/60000);
 return {
  minutes,
  direction:offsetMs>0?'atrasado':'adiantado',
  message:`O relógio deste computador está ${minutes} minuto(s) ${offsetMs>0?'atrasado':'adiantado'} em relação ao servidor.`
 };
}

window.addEventListener('online',()=>sync());
window.addEventListener('offline',()=>{
 source='local';
 offsetMs=0;
 emit();
});

document.addEventListener('visibilitychange',()=>{
 if(document.visibilityState==='visible')sync();
});

setInterval(()=>sync(),SYNC_INTERVAL);

window.PlenitudeClock=Object.freeze({
 now,
 localNow,
 info,
 sync,
 subscribe,
 formatDate,
 formatTime,
 differenceWarning
});
})();