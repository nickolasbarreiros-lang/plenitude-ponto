(function () {
  'use strict';

  const config = window.PLENITUDE_SUPABASE;
  if (!config?.url || !config?.publishableKey) {
    throw new Error('Configuração do Supabase ausente.');
  }
  if (!window.supabase?.createClient) {
    throw new Error('Biblioteca do Supabase não foi carregada.');
  }

  const client = window.supabase.createClient(config.url, config.publishableKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: 'plenitude-ponto-auth'
    }
  });

  async function getSession() {
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    return data.session;
  }

  async function requireSession() {
    const session = await getSession();
    if (!session) {
      const current = encodeURIComponent(location.pathname.split('/').pop() || 'admin.html');
      location.replace(`index.html?retorno=${current}`);
      return null;
    }
    return session;
  }

  async function redirectIfAuthenticated() {
    const session = await getSession();
    if (session) location.replace('admin.html');
    return session;
  }

  async function signIn(email, password) {
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  }

  async function signOut() {
    const { error } = await client.auth.signOut({ scope: 'local' });
    if (error) throw error;
    location.replace('index.html');
  }

  function friendlyAuthError(error) {
    const message = String(error?.message || '').toLowerCase();
    if (message.includes('invalid login credentials')) return 'E-mail ou senha incorretos.';
    if (message.includes('email not confirmed')) return 'Confirme seu e-mail antes de entrar.';
    if (message.includes('too many requests')) return 'Muitas tentativas. Aguarde alguns minutos.';
    if (message.includes('failed to fetch')) return 'Não foi possível conectar ao servidor. Confira a internet.';
    return error?.message || 'Não foi possível realizar o login.';
  }

  client.auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_OUT' && !location.pathname.endsWith('/index.html') && !location.pathname.endsWith('/')) {
      location.replace('index.html');
    }
  });

  window.PlenitudeAuth = Object.freeze({
    client,
    getSession,
    requireSession,
    redirectIfAuthenticated,
    signIn,
    signOut,
    friendlyAuthError
  });
})();
