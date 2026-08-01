# RC5.37 — aplicação forçada do layout compacto

A RC5.36 estava publicada, mas o navegador continuava servindo o HTML e o
JavaScript antigos pelo Service Worker.

Correções:

- novos nomes físicos para o JavaScript e CSS da contingência;
- folha de estilo exclusiva com seletores de alta prioridade;
- limpeza automática, uma única vez, dos caches e Service Workers antigos;
- recarregamento automático da página após a limpeza;
- dois cards por linha garantidos em telas acima de 980 px.
