# RC5.60 — proteção crítica do registro de ponto

- restaura no banco a trava mínima de 30 minutos;
- impede chamadas simultâneas por funcionário com advisory lock;
- bloqueia nova marcação nos primeiros cinco segundos;
- valida a sequência Entrada → Almoço → Retorno → Saída;
- protege também o registro feito pelo administrador;
- adiciona trava de requisição no frontend;
- detecta Service Worker atualizado e recarrega a página automaticamente;
- mostra aviso de atualização durante a troca de versão.

A migração SQL desta versão é obrigatória.
