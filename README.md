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
