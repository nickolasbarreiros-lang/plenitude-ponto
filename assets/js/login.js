(async function () {
  'use strict';

  const form = document.getElementById('login-form');
  const email = document.getElementById('email');
  const senha = document.getElementById('senha');
  const mostrar = document.getElementById('mostrar-senha');
  const submit = form.querySelector('button[type="submit"]');
  const feedback = document.getElementById('login-feedback');
  const forgotPassword = document.getElementById('forgot-password');

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



  forgotPassword?.addEventListener('click', async () => {
    const address = email.value.trim();
    if (!address) {
      setFeedback('Informe seu e-mail para receber o link de recuperação.', 'error');
      email.focus();
      return;
    }
    forgotPassword.disabled = true;
    forgotPassword.textContent = 'Enviando...';
    setFeedback('Solicitando recuperação de senha...', 'loading');
    try {
      await window.PlenitudeAuth.requestPasswordReset(address);
      setFeedback('Link enviado. Verifique sua caixa de entrada e também a pasta de spam.', 'success');
    } catch (error) {
      setFeedback(window.PlenitudeAuth.friendlyAuthError(error), 'error');
    } finally {
      forgotPassword.disabled = false;
      forgotPassword.textContent = 'Esqueci minha senha';
    }
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    setFeedback('Entrando...', 'loading');
    submit.disabled = true;
    submit.textContent = 'Entrando...';

    try {
      await window.PlenitudeAuth.signIn(email.value.trim(), senha.value);
      const context = await window.PlenitudeAuth.getAccessContext(true);
      const params = new URLSearchParams(location.search);
      const retorno = params.get('retorno');
      const adminPages = ['admin.html','funcionarios.html','jornada.html','calendario.html','relatorios.html','configuracoes.html','ajustes.html','auditoria.html','backup.html','fechamento.html'];
      const safeReturn = retorno && /^[a-z0-9_-]+\.html$/i.test(retorno);
      if (safeReturn && (context.profile.papel === 'administrador' || !adminPages.includes(retorno))) location.replace(retorno);
      else location.replace(window.PlenitudeAuth.homeForRole(context.profile.papel));
    } catch (error) {
      setFeedback(window.PlenitudeAuth.friendlyAuthError(error), 'error');
      senha.focus();
      senha.select();
    } finally {
      submit.disabled = false;
      submit.textContent = 'Entrar no painel';
    }
  });
})();
