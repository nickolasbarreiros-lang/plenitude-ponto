# Auditoria RC5.83 — arquivos baixados do repositório

## Resultado

O ZIP baixado contém uma única estrutura válida na raiz:

- `admin.html`
- `sw.js`
- `assets/js/app.js`

Não foi encontrada pasta `docs`, segunda cópia do site ou outro `admin.html` concorrente.

Todos os 20 HTMLs do pacote apontavam para `v=1.0.0-rc5.82` e o Service Worker usava `plenitude-ponto-rc5-82`.

Também estavam presentes:

- `companyPolicies()` em `database.js`;
- RPC `politicas_empresa_admin`;
- leitura de `companyPolicies.tolerancia_entrada_minutos` no painel;
- ausência do fallback antigo `profile.tolerancia_entrada_minutos || 15`.

Portanto, o ZIP do repositório já continha a RC5.82. O navegador mostrar RC5.81 indica publicação anterior ainda servida pelo GitHub Pages ou cache HTTP/Service Worker antigo, não mistura de arquivos dentro deste ZIP.

## Reforço RC5.83

- todos os recursos alterados para RC5.83;
- meta `plenitude-build=RC5.83` em todas as páginas;
- Service Worker usa `cache: no-store` na busca online;
- caches antigos `plenitude-ponto-*` são apagados automaticamente;
- console informa explicitamente RC5.83;
- a correção da tolerância de 10 minutos foi preservada.

Não exige SQL novo se `supabase-rc5-82-politicas-empresa.sql` já foi executado.
