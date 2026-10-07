document.getElementById('year').textContent = new Date().getFullYear();

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

const nav = document.querySelector('.site-nav');
window.addEventListener('scroll', () => {
    nav.classList.toggle('scrolled', window.scrollY > 20);
}, { passive: true });

/* ── Contact form — saves to real API ── */
document.getElementById('send-message').addEventListener('click', async function () {
    const name = document.getElementById('name').value.trim();
    const email = document.getElementById('email').value.trim();
    const msg = document.getElementById('msg').value.trim();
    const branch = document.getElementById('branch').value;
    const phone = document.getElementById('phone').value.trim();
    const fb = document.getElementById('form-feedback');
    const btn = this;

    fb.style.display = 'none';

    if (!name || !email || !msg) {
        fb.style.display = 'block';
        fb.style.color = 'var(--red)';
        fb.style.background = 'var(--red-light)';
        fb.style.borderColor = 'var(--red-mid)';
        fb.textContent = 'Please fill in all required fields.';
        return;
    }

    btn.disabled = true;
    btn.textContent = 'Sending…';

    try {
        const res = await fetch('/api/admin/contacts', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ full_name: name, email, phone, branch, message: msg }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Failed to send message.');

        fb.style.display = 'block';
        fb.style.color = '#1e7d32';
        fb.style.background = '#e8f5e9';
        fb.style.borderColor = '#a5d6a7';
        fb.textContent = '✓ Message sent! We\'ll get back to you within 24 hours.';

        document.getElementById('name').value = '';
        document.getElementById('email').value = '';
        document.getElementById('phone').value = '';
        document.getElementById('msg').value = '';
        document.getElementById('branch').value = '';
    } catch (err) {
        fb.style.display = 'block';
        fb.style.color = 'var(--red)';
        fb.style.background = 'var(--red-light)';
        fb.style.borderColor = 'var(--red-mid)';
        fb.textContent = '⚠ ' + err.message;
    } finally {
        btn.disabled = false;
        btn.textContent = 'Send Message';
    }
});