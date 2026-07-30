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


## V12 — Storage e acesso do funcionário
Antes de publicar, execute `supabase-v12-storage-acesso.sql` no SQL Editor. A foto passa a ser armazenada em bucket privado. Para vincular o login da funcionária, crie a usuária em Authentication → Users e informe o mesmo e-mail na tela Funcionário.


## V13 — Dados 100% no Supabase

- Configurações da empresa e nome do administrador salvos no Supabase.
- Calendário e ocorrências salvos na tabela `ocorrencias`.
- Backup JSON gerado diretamente das tabelas do banco.
- Removido o armazenamento local de dados operacionais.
- O `localStorage` permanece apenas para a preferência visual de tema claro/escuro.
- Nenhum novo script SQL é necessário para esta versão.

## V14 — acesso individual da funcionária

- Redirecionamento automático por papel: administrador para `admin.html` e funcionário para `ponto.html`.
- Bloqueio das páginas administrativas para contas com papel `funcionario`.
- Tela de ponto identifica automaticamente o funcionário vinculado ao usuário autenticado.
- Funcionário registra o próprio ponto pela função segura `registrar_ponto()`.
- Resumo pessoal com saldo de hoje, semana e mês, além de perfil básico.
- Conta ainda não vinculada recebe uma mensagem clara e não consegue registrar ponto.

Nenhum novo SQL é necessário nesta versão. Antes do primeiro acesso da funcionária, crie a conta dela em Authentication > Users e use o botão "Vincular conta de acesso" no cadastro do funcionário.

## V17 — Banco de horas automático

Antes de publicar esta versão, execute `supabase-v17-banco-horas.sql` no SQL Editor do Supabase. O módulo calcula jornada prevista, horas trabalhadas, créditos, débitos, faltas, pendências e ocorrências aprovadas para o administrador e para a sessão por matrícula + PIN.


## V18 — Ajustes de ponto
- Funcionário solicita marcação esquecida por matrícula/PIN.
- Administrador aprova ou rejeita em Ajustes.
- Aprovação cria marcação ajustada com horário solicitado e auditoria.
- Execute `supabase-v18-ajustes-ponto.sql` antes de publicar.


## V19
Políticas configuráveis, tolerância de entrada padrão de 15 minutos, preservação do horário real e alertas de intervalo.


## V20 — Espelho de ponto mensal

- Cabeçalho A4 com dados da empresa, funcionário e competência.
- Apuração diária e totais mensais.
- Campos para assinatura do funcionário e da empresa.
- Botão **Imprimir / Salvar PDF**, usando a impressão nativa do navegador.
- Layout de impressão A4 em orientação paisagem.
- Não exige nova migração SQL: utiliza os dados e funções já instalados na V19.

## V21 — Dashboard inteligente

- Indicadores de atrasos, ajustes pendentes e saldo mensal.
- Central de notificações operacionais.
- Gráfico da jornada dos últimos 30 dias por funcionário.
- Seletor rápido de funcionário no painel.
- Utiliza apenas estruturas já existentes no Supabase; não exige nova migração SQL.

## V22 — Auditoria e segurança

1. Execute `supabase-v22-auditoria-seguranca.sql` no SQL Editor do Supabase.
2. Publique os arquivos desta versão.
3. A nova tela **Auditoria** permite filtrar, consultar detalhes e exportar CSV.
4. Logins, logouts e alterações críticas são gravados com horário do servidor.
5. A tabela de auditoria só pode ser lida por administradores da mesma empresa.


## V23 — Backup e exportações

- Backup completo em ZIP com CSVs, JSON, manifesto e diagnóstico de integridade.
- Exportações individuais de funcionários, jornadas, marcações, ocorrências, banco de horas, ajustes e auditoria.
- Validação segura de arquivo JSON sem restauração automática.
- Não requer novo SQL; utiliza as políticas e funções da V22.
