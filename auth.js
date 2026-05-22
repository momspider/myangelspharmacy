/* ═══════════════════════════════════════════════════════════════════
   auth.js — Angel's Pharmacy · Frontend Auth Module (Supabase edition)
   Replaces the old localStorage-based auth.
   Storage  : sessionStorage for access token (tab-scoped)
              localStorage  for refresh token (persists across tabs)
   ═══════════════════════════════════════════════════════════════════ */

const Auth = (() => {

  const API           = 'http://localhost:3000/api';  // change to your domain in production
  const ACCESS_KEY    = 'ap_access_token';
  const REFRESH_KEY   = 'ap_refresh_token';
  const USER_KEY      = 'ap_user';

  /* ── TOKEN STORAGE ─────────────────────────────────────────────── */

  function getAccessToken()  { return sessionStorage.getItem(ACCESS_KEY); }
  function getRefreshToken() { return localStorage.getItem(REFRESH_KEY); }

  function saveTokens(access_token, refresh_token) {
    sessionStorage.setItem(ACCESS_KEY, access_token);
    if (refresh_token) localStorage.setItem(REFRESH_KEY, refresh_token);
  }

  function clearTokens() {
    sessionStorage.removeItem(ACCESS_KEY);
    localStorage.removeItem(REFRESH_KEY);
    localStorage.removeItem(USER_KEY);
  }

  /* ── CACHED USER ───────────────────────────────────────────────── */

  function getCachedUser() {
    try { return JSON.parse(localStorage.getItem(USER_KEY)); }
    catch { return null; }
  }

  function saveUser(user) {
    localStorage.setItem(USER_KEY, JSON.stringify(user));
  }

  /* ── API HELPER ────────────────────────────────────────────────── */

  async function apiFetch(path, options = {}) {
    const token = getAccessToken();
    const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const res = await fetch(`${API}${path}`, { ...options, headers });

    // Token expired — try refreshing once
    if (res.status === 401) {
      const refreshed = await tryRefresh();
      if (refreshed) {
        headers['Authorization'] = `Bearer ${getAccessToken()}`;
        return fetch(`${API}${path}`, { ...options, headers });
      }
    }

    return res;
  }

  async function tryRefresh() {
    const refresh_token = getRefreshToken();
    if (!refresh_token) return false;

    try {
      const res  = await fetch(`${API}/auth/refresh`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ refresh_token }),
      });
      if (!res.ok) { clearTokens(); return false; }
      const { access_token, refresh_token: new_refresh } = await res.json();
      saveTokens(access_token, new_refresh);
      return true;
    } catch {
      clearTokens();
      return false;
    }
  }

  /* ── SIGN UP ───────────────────────────────────────────────────── */

  async function signUp(full_name, email, phone, password, confirmPassword) {
    full_name = full_name.trim();
    email     = email.trim().toLowerCase();

    if (full_name.length < 2)
      throw new Error('Full name must be at least 2 characters.');
    if (password.length < 6)
      throw new Error('Password must be at least 6 characters.');
    if (password !== confirmPassword)
      throw new Error('Passwords do not match. Please try again.');

    const res  = await fetch(`${API}/auth/signup`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ full_name, email, phone, password }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Sign up failed.');
    return data;
  }

  /* ── LOG IN ────────────────────────────────────────────────────── */

  async function logIn(email, password) {
    email = email.trim().toLowerCase();

    if (!email || !password)
      throw new Error('Email and password are required.');

    const res  = await fetch(`${API}/auth/login`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ email, password }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Login failed.');

    saveTokens(data.access_token, data.refresh_token);
    saveUser(data.user);
    return data.user;
  }

  /* ── LOG OUT ───────────────────────────────────────────────────── */

  async function logOut() {
    try {
      await apiFetch('/auth/logout', { method: 'POST' });
    } catch { /* ignore network errors on logout */ }
    clearTokens();
    window.location.replace('index.html');
  }

  /* ── GET SESSION (current user) ────────────────────────────────── */

  function getSession() {
    if (!getAccessToken()) return null;
    return getCachedUser();
  }

  /* ── REQUIRE AUTH ──────────────────────────────────────────────── */
  /* Call at the top of any protected page.
     Redirects to index.html immediately if no session exists.       */

  async function requireAuth() {
    if (!getAccessToken()) {
      // Try refresh before giving up
      const refreshed = await tryRefresh();
      if (!refreshed) {
        window.location.replace('index.html');
        return null;
      }
    }

    // Validate token is still good and refresh user data
    try {
      const res = await apiFetch('/auth/me');
      if (!res.ok) throw new Error();
      const user = await res.json();
      saveUser(user);
      return user;
    } catch {
      clearTokens();
      window.location.replace('index.html');
      return null;
    }
  }

  /* ── REQUIRE ADMIN ─────────────────────────────────────────────── */

  async function requireAdmin() {
    const user = await requireAuth();
    if (user && user.role !== 'admin') {
      window.location.replace('homepage.html');
      return null;
    }
    return user;
  }

  /* ── API FETCH (exported for other modules) ────────────────────── */
  /* Use this in homepage.js, admin.js etc. to make authenticated API calls:
     const res = await Auth.fetch('/medicines');
     const medicines = await res.json();                              */

  /* ── PUBLIC API ────────────────────────────────────────────────── */
  return {
    signUp,
    logIn,
    logOut,
    getSession,
    requireAuth,
    requireAdmin,
    fetch: apiFetch,   // authenticated fetch for use in other scripts
  };

})();
