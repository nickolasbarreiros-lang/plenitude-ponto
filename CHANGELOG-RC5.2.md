# Plenitude Ponto RC5.2 — Login do funcionário offline

## Correção principal

A tela de login não depende mais obrigatoriamente do Supabase quando a internet está indisponível.

## Funcionamento

- Após um login online bem-sucedido, o navegador armazena um verificador criptográfico do PIN.
- O PIN não é armazenado em texto aberto.
- O verificador é vinculado à matrícula e ao token do computador autorizado.
- Em modo offline, a matrícula e o PIN são validados localmente.
- Somente funcionários que já entraram ao menos uma vez com internet podem acessar offline.
- Cada funcionário preparado fica armazenado separadamente no navegador.
- O Service Worker passou a armazenar também os arquivos da tela de login.
- O diagnóstico informa quantos funcionários estão preparados para login offline.

## Segurança

- Troca ou revogação do token do dispositivo invalida a preparação anterior.
- PIN incorreto continua impedindo o acesso.
- Registros realizados após o login offline permanecem sujeitos à sincronização e aprovação administrativa.
