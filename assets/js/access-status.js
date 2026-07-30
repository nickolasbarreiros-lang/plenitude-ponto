(function(){
  'use strict';
  const clock=document.getElementById('access-clock');
  const date=document.getElementById('access-date');
  const network=document.getElementById('access-network');
  const dot=document.getElementById('access-online-dot');
  function tick(){
    const now=new Date();
    if(clock) clock.textContent=now.toLocaleTimeString('pt-BR');
    if(date) date.textContent=now.toLocaleDateString('pt-BR',{weekday:'long',day:'2-digit',month:'long',year:'numeric'});
  }
  function connectivity(){
    const online=navigator.onLine;
    if(network) network.textContent=online?'Sistema online':'Sem conexão com a internet';
    if(dot) dot.classList.toggle('offline',!online);
  }
  tick(); connectivity(); setInterval(tick,1000);
  addEventListener('online',connectivity); addEventListener('offline',connectivity);
})();
