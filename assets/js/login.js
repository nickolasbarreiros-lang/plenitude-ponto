(async function () {
  'use strict';

  const form = document.getElementById('login-form');
  const email = document.getElementById('email');
  const senha = document.getElementById('senha');
  const mostrar = document.getElementById('mostrar-senha');
  const submit = form.querySelector('button[type="submit"]');
  const feedback = document.getElementById('login-feedback');

  function setFeedback(message = '', type = '') {
    feedback.textContent = message;
    feedback.className = `login-feedback${type ? ` ${type}` : ''}`;
  }

  mostrar.addEventListener('click', () => {
    const visible = senha.type === 'password';
    senha.type = visible ? 'text' : 'password';
    mostrar.textContent = visible ? 'Ocultar' : 'Mostrar';
  });

  try {
    const session = await window.PlenitudeAuth.redirectIfAuthenticated();
    if (session) return;
  } catch (error) {
    setFeedback('Não foi possível verificar a sessão.', 'error');
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    setFeedback('Entrando...', 'loading');
    submit.disabled = true;
    submit.textContent = 'Entrando...';

    try {
      await window.PlenitudeAuth.signIn(email.value.trim(), senha.value);
      const params = new URLSearchParams(location.search);
      const retorno = params.get('retorno');
      location.replace(retorno && /^[a-z0-9_-]+\.html$/i.test(retorno) ? retorno : 'admin.html');
    } catch (error) {
      setFeedback(window.PlenitudeAuth.friendlyAuthError(error), 'error');
      senha.focus();
      senha.select();
    } finally {
      submit.disabled = false;
      submit.textContent = 'Entrar no sistema';
    }
  });
})();
