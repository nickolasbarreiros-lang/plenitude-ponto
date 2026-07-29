(function () {
  'use strict';

  const config = window.PLENITUDE_SUPABASE;
  if (!config?.url || !config?.publishableKey) throw new Error('Configuração do Supabase ausente.');
  if (!window.supabase?.createClient) throw new Error('Biblioteca do Supabase não foi carregada.');

  const client = window.supabase.createClient(config.url, config.publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: 'plenitude-ponto-auth' }
  });

  let cachedAccess = null;

  async function getSession() {
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    return data.session;
  }

  async function getAccessContext(force = false) {
    if (cachedAccess && !force) return cachedAccess;
    const session = await getSession();
    if (!session) return null;
    const { data, error } = await client
      .from('perfis')
      .select('id,nome,papel,empresa_id,ativo')
      .eq('id', session.user.id)
      .single();
    if (error) throw error;
    if (!data?.ativo) throw new Error('Esta conta está inativa.');
    cachedAccess = { session, profile: data };
    return cachedAccess;
  }

  function homeForRole(role) { return role === 'administrador' ? 'admin.html' : 'ponto.html'; }

  async function requireAccess(options = {}) {
    const { roles = null, redirect = true } = options;
    const context = await getAccessContext();
    if (!context) {
      if (redirect) {
        const current = encodeURIComponent(location.pathname.split('/').pop() || 'admin.html');
        location.replace(`index.html?retorno=${current}`);
      }
      return null;
    }
    if (Array.isArray(roles) && roles.length && !roles.includes(context.profile.papel)) {
      if (redirect) location.replace(homeForRole(context.profile.papel));
      return null;
    }
    return context;
  }

  async function requireSession() {
    const context = await requireAccess();
    return context?.session || null;
  }

  async function redirectIfAuthenticated() {
    const context = await getAccessContext();
    if (context) location.replace(homeForRole(context.profile.papel));
    return context?.session || null;
  }

  async function signIn(email, password) {
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw error;
    cachedAccess = null;
    return data;
  }

  async function signOut() {
    cachedAccess = null;
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
    if (message.includes('inativa')) return 'Esta conta está inativa.';
    return error?.message || 'Não foi possível realizar o login.';
  }

  client.auth.onAuthStateChange((event) => {
    cachedAccess = null;
    if (event === 'SIGNED_OUT' && !location.pathname.endsWith('/index.html') && !location.pathname.endsWith('/')) location.replace('index.html');
  });

  window.PlenitudeAuth = Object.freeze({
    client, getSession, getAccessContext, requireAccess, requireSession,
    redirectIfAuthenticated, homeForRole, signIn, signOut, friendlyAuthError
  });
})();
