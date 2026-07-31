const CACHE='plenitude-ponto-rc5-0';
const CORE=[
 './','./index.html','./ponto.html','./assets/css/estilos.css',
 './assets/js/supabase-config.js','./assets/js/auth.js','./assets/js/database.js',
 './assets/js/app.js','./assets/js/offline-contingencia.js','./assets/js/ponto-pin.js',
 './assets/img/logo-plenitude.png',
 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'
];

self.addEventListener('install',event=>{
 event.waitUntil(caches.open(CACHE).then(cache=>Promise.allSettled(CORE.map(url=>cache.add(url)))));
 self.skipWaiting();
});

self.addEventListener('activate',event=>{
 event.waitUntil(
  caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
 );
 self.clients.claim();
});

self.addEventListener('fetch',event=>{
 if(event.request.method!=='GET')return;
 const url=new URL(event.request.url);
 if(url.hostname.includes('supabase.co'))return;

 event.respondWith(
  fetch(event.request).then(response=>{
   const copy=response.clone();
   caches.open(CACHE).then(cache=>cache.put(event.request,copy)).catch(()=>{});
   return response;
  }).catch(()=>caches.match(event.request).then(cached=>cached||caches.match('./ponto.html')))
 );
});