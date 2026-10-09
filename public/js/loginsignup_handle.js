/* ── Login ── */
async function handleLogin() {
    clearAuthMessages();
    const email = document.getElementById('login-email').value;
    const pass = document.getElementById('login-pass').value;
    setLoading('login-btn', true);
    try {
        const user = await Auth.logIn(email, pass);
        const params = new URLSearchParams(window.location.search);
        const redirect = params.get('redirect') || sessionStorage.getItem('ap_redirect_after_login');
        sessionStorage.removeItem('ap_redirect_after_login');
        if (redirect) window.location.replace(redirect);
        else window.location.replace(['admin', 'pharmacist'].includes(user.role) ? 'admin.html' : 'homepage.html');
    } catch (err) {
        showError('login', err.message);
        setLoading('login-btn', false);
    }
}

/* ── Signup ── */
async function handleSignup() {
    clearAuthMessages();
    const name = document.getElementById('signup-name').value;
    const email = document.getElementById('signup-email').value;
    const phone = document.getElementById('signup-phone').value;
    const pass = document.getElementById('signup-pass').value;
    const confirm = document.getElementById('signup-confirm').value;
    setLoading('signup-btn', true);
    try {
        await Auth.signUp(name, email, phone, pass, confirm);
        showSuccess('signup', '✓ Account created! Check your email to confirm your address before logging in.');
        setLoading('signup-btn', false);
    } catch (err) {
        showError('signup', err.message);
        setLoading('signup-btn', false);
    }
}