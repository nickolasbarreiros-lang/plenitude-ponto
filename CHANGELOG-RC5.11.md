# Plenitude Ponto RC5.11 — Correção do Service Worker no modo online

## Causa

O Service Worker estava interceptando qualquer requisição que não fosse do Supabase, inclusive recursos injetados pelo navegador, extensões e DevTools. Quando esses recursos não estavam no cache, ele devolvia status 503.

Por isso o console mostrava erros como `app.css: 503`, embora `app.css` não pertença ao sistema.

## Correções

- O Service Worker agora intercepta somente:
  - arquivos do próprio domínio;
  - biblioteca oficial carregada pelo jsDelivr.
- Recursos de extensões, DevTools e outros domínios não são mais interceptados.
- No modo online, a rede permanece como fonte principal.
- O cache é usado apenas como contingência quando a rede realmente falha.
- `login.js` foi incluído entre os arquivos essenciais offline.
- A página inicial passa a registrar e atualizar o Service Worker corrigido.
