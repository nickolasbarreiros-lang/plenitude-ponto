const CACHE='plenitude-ponto-rc5-6';
const CORE=[
 './',
 './index.html',
 './ponto.html',
 './assets/css/estilos.css',
 './assets/js/supabase-config.js',
 './assets/js/auth.js',
 './assets/js/database.js',
 './assets/js/app.js',
 './assets/js/offline-contingencia.js',
 './assets/js/ponto-pin.js',
 './assets/js/employee-login.js',
 './assets/js/access-status.js',
 './assets/img/logo-plenitude.png',
 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'
];

async function cacheCore(){
 const cache=await caches.open(CACHE);
 const results=[];

 for(const url of CORE){
  try{
   const request=new Request(url,{cache:'reload',mode:url.startsWith('http')?'cors':'same-origin'});
   const response=await fetch(request);
   if(!response.ok)throw new Error(`HTTP ${response.status}`);
   await cache.put(url,response.clone());
   results.push({url,ok:true});
  }catch(error){
   const cached=await cache.match(url);
   results.push({url,ok:Boolean(cached),error:error.message});
  }
 }

 return results;
}

self.addEventListener('install',event=>{
 event.waitUntil(cacheCore());
 self.skipWaiting();
});

self.addEventListener('activate',event=>{
 event.waitUntil(
  caches.keys().then(keys=>Promise.all(
   keys.filter(key=>key!==CACHE).map(key=>caches.delete(key))
  ))
 );
 self.clients.claim();
});

self.addEventListener('message',event=>{
 if(event.data?.type==='CACHE_OFFLINE_CORE'){
  event.waitUntil(
   cacheCore().then(results=>{
    event.source?.postMessage({
     type:'CACHE_OFFLINE_RESULT',
     cache:CACHE,
     results
    });
   })
  );
 }

 if(event.data?.type==='OFFLINE_STATUS'){
  event.waitUntil(
   caches.open(CACHE).then(async cache=>{
    const results=[];
    for(const url of CORE){
     results.push({url,ok:Boolean(await cache.match(url))});
    }
    event.source?.postMessage({
     type:'OFFLINE_STATUS_RESULT',
     cache:CACHE,
     results
    });
   })
  );
 }
});

self.addEventListener('fetch',event=>{
 if(event.request.method!=='GET')return;

 const url=new URL(event.request.url);
 if(url.hostname.includes('supabase.co'))return;

 event.respondWith(
  fetch(event.request).then(response=>{
   if(response.ok){
    const copy=response.clone();
    caches.open(CACHE).then(cache=>cache.put(event.request,copy)).catch(()=>{});
   }
   return response;
  }).catch(async()=>{
   const cached=await caches.match(event.request);
   if(cached)return cached;

   if(event.request.mode==='navigate'){
    return caches.match('./ponto.html');
   }

   return new Response('Recurso indisponível offline.',{
    status:503,
    headers:{'Content-Type':'text/plain; charset=utf-8'}
   });
  })
 );
});