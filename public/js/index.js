/* ── Redirect if already logged in ── */
(async () => {
    const session = Auth.getSession();
    if (session) {
        const params = new URLSearchParams(window.location.search);
        const redirect = params.get('redirect');
        if (redirect) window.location.replace(redirect);
        else window.location.replace(session.role === 'admin' ? 'admin.html' : 'homepage.html');
    }
    const params = new URLSearchParams(window.location.search);
    if (params.get('signup') === '1') openModal('signup');
    if (params.get('redirect')) openModal('login');
})();

document.getElementById('yr').textContent = new Date().getFullYear();

const logoImg = document.getElementById('logo-img');
if (logoImg) {
    logoImg.onload = () => { logoImg.style.display = ''; document.getElementById('logo-fallback').style.display = 'none'; };
    logoImg.onerror = () => { logoImg.style.display = 'none'; };
}

const toggle = document.querySelector('.nav-toggle');
const menu = document.getElementById('nav-menu');
if (toggle && menu) {
    toggle.addEventListener('click', () => {
        const open = !menu.hidden;
        menu.hidden = open;
        toggle.setAttribute('aria-expanded', String(!open));
    });
}

/* ── Scroll reveal ── */
const observer = new IntersectionObserver(entries => {
    entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('visible'); observer.unobserve(e.target); } });
}, { threshold: 0.12 });
document.querySelectorAll('.reveal').forEach(el => observer.observe(el));

/* ── Nav scroll effect ── */
window.addEventListener('scroll', () => {
    document.querySelector('.site-nav').classList.toggle('scrolled', window.scrollY > 20);
}, { passive: true });

/* ── Modal helpers ── */
function openModal(tab) {
    if (event) event.preventDefault();
    clearAuthMessages();
    document.getElementById('modal-overlay').classList.add('open');
    switchTab(tab || 'login');
    document.getElementById(tab === 'signup' ? 'signup-name' : 'login-email').focus();
}
function closeModal() {
    document.getElementById('modal-overlay').classList.remove('open');
    clearAuthMessages();
}
function handleOverlayClick(e) { if (e.target === document.getElementById('modal-overlay')) closeModal(); }
function switchTab(tab) {
    clearAuthMessages();
    ['login', 'signup'].forEach(t => {
        document.getElementById('tab-' + t).classList.toggle('active', t === tab);
        document.getElementById('panel-' + t).classList.toggle('active', t === tab);
    });
    document.getElementById('modal-sub').textContent =
        tab === 'login' ? 'Sign in to your account' : 'Create your free account';
}
function showError(panelId, msg) {
    const el = document.getElementById(panelId + '-error');
    if (el) { el.textContent = msg; el.style.display = 'block'; }
}
function showSuccess(panelId, msg) {
    const el = document.getElementById(panelId + '-success');
    if (el) { el.textContent = msg; el.style.display = 'block'; }
}
function clearAuthMessages() {
    ['login-error', 'login-success', 'signup-error', 'signup-success'].forEach(id => {
        const el = document.getElementById(id);
        if (el) { el.textContent = ''; el.style.display = 'none'; }
    });
}
function setLoading(btnId, loading) {
    const btn = document.getElementById(btnId);
    if (!btn) return;
    btn.disabled = loading;
    btn.textContent = loading
        ? (btnId === 'login-btn' ? 'Signing in…' : 'Creating account…')
        : (btnId === 'login-btn' ? 'Log In →' : 'Create Account →');
}


document.querySelectorAll('.show-pass-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const input = document.getElementById(btn.dataset.target);
        if (!input) return;
        const isHidden = input.type === 'password';
        input.type = isHidden ? 'text' : 'password';
        btn.textContent = isHidden ? 'Hide' : 'Show';
    });
});

document.getElementById('login-pass').addEventListener('keydown', e => { if (e.key === 'Enter') handleLogin(); });
document.getElementById('signup-confirm').addEventListener('keydown', e => { if (e.key === 'Enter') handleSignup(); });
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });