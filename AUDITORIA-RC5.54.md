# RC5.54 — campo de mês totalmente clicável

O navegador não abria o seletor ao clicar no texto do `input type="month"`.

A correção adiciona um botão transparente sobre toda a área do campo. Qualquer
clique no campo chama `showPicker()` dentro do próprio gesto do usuário.

O ícone nativo continua visível, mas deixa de ser o único ponto clicável.
