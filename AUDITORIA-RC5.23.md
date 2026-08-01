# RC5.23

O registro offline era salvo no IndexedDB, mas o fluxo parava em
`ReferenceError: toast is not defined`.

A função toast vinha de app.js, removido corretamente da página do ponto.
Agora ponto-pin.js possui seu próprio sistema de notificações.

A tela recarrega a jornada local antes de mostrar a confirmação, evitando que
a marcação permaneça visualmente na etapa anterior.
