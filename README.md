# Plenitude Ponto — V9

Sistema de controle de ponto da Livraria Plenitude, hospedado no GitHub Pages e conectado ao Supabase.

## Implementado nesta versão

- autenticação real pelo Supabase Auth;
- sessão persistente e logout;
- proteção das páginas internas;
- leitura do perfil e da empresa vinculada;
- cadastro e edição do funcionário no PostgreSQL;
- cadastro e edição da jornada semanal no PostgreSQL;
- painel lendo funcionário, jornada e marcações disponíveis no banco.

## Ainda temporariamente local

- calendário;
- configurações visuais;
- marcações criadas pela tela de ponto;
- relatórios baseados nas marcações locais.

A próxima etapa vinculará uma conta Auth ao funcionário e ativará a função segura `registrar_ponto()`.


## V10 — Registro de ponto real

1. Execute `supabase-v10-registro-ponto.sql` no SQL Editor do Supabase.
2. Publique os arquivos no GitHub Pages.
3. Entre como administrador e abra `Registrar ponto`.
4. Selecione a funcionária e clique no botão. O horário vem do servidor.


## V11
Antes de publicar, execute `supabase-v11-perfil-funcionario.sql` no SQL Editor. A versão adiciona status, foto otimizada, QR individual e indicadores operacionais no painel.
