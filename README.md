# Plenitude Ponto — versão inicial

Projeto separado do Orquidário, pronto para ser colocado em um repositório próprio no GitHub.

## Estrutura
- `index.html`: login
- `admin.html`: painel administrativo
- `ponto.html`: tela de registro
- `funcionarios.html`: cadastro do funcionário
- `jornada.html`: jornada semanal
- `assets/css/estilos.css`: visual
- `assets/js/app.js`: funcionamento
- `assets/img/logo-plenitude.png`: logomarca

## Acesso demonstrativo
- E-mail: `admin@plenitude.local`
- Senha: `123456`

## Como publicar
1. Crie um repositório novo chamado `plenitude-ponto`.
2. Envie todo o conteúdo desta pasta para a raiz do repositório.
3. Abra **Settings > Pages**.
4. Em **Build and deployment**, escolha **Deploy from a branch**.
5. Selecione a branch `main` e a pasta `/root`.
6. Salve e aguarde o endereço do GitHub Pages.

## Importante
Nesta versão os dados ficam no `localStorage` do navegador. A próxima fase deve conectar login e registros a um banco de dados como Supabase.
