# Migrações SQL — orientação

Os arquivos SQL presentes no repositório formam um histórico incremental.
Funções repetidas são esperadas: versões mais novas substituem versões antigas
com `create or replace function`.

Em uma instalação já atualizada até RC5.49, a RC5.59 não exige SQL novo.

Não execute todos os arquivos antigos novamente em um banco de produção.
Para uma instalação limpa, consolide as migrações em uma base de homologação
antes de aplicar em produção.
