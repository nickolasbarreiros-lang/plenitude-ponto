# RC5.49 — pendência somente após a virada do dia

## Causa

A rotina utilizava `current_date`, que pode seguir o fuso da sessão do banco,
e registros já criados para o dia atual continuavam sendo exibidos.

## Correção

- usa a data no fuso cadastrado da empresa;
- cria pendência apenas quando `data_local < hoje`;
- resolve automaticamente pendências indevidas do dia atual e do futuro;
- filtros adicionais foram aplicados nas consultas do funcionário e do admin;
- o frontend também ignora qualquer pendência do dia atual como proteção extra.
