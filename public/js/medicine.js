const API = '';
let _medicine = null;

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

/* ── Nav auth ── */
function renderNavAuth() {
    const session = Auth.getSession();
    const navAuth = document.getElementById('nav-auth');
    if (session) {
        const initial = (session.full_name || session.email).charAt(0).toUpperCase();
        navAuth.innerHTML = `
      <div style="width:32px;height:32px;border-radius:99px;background:linear-gradient(135deg,var(--red),var(--red-dark));color:white;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:13px;">${initial}</div>
      <a href="${['admin', 'pharmacist'].includes(session.role) ? 'admin.html' : 'homepage.html'}" class="btn" style="font-size:12px;padding:7px 14px;">My Account</a>
    `;
    } else {
        navAuth.innerHTML = `
      <a href="index.html" class="btn-ghost" style="font-size:13px;">Log In</a>
      <a href="index.html?signup=1" class="btn" style="font-size:13px;">Sign Up</a>
    `;
    }
}
renderNavAuth();

/* ── Load medicine by ID from URL ── */
async function loadMedicine() {
    const params = new URLSearchParams(window.location.search);
    const id = params.get('id');

    if (!id) {
        document.getElementById('detail-content').innerHTML = `
      <div style="text-align:center;padding:60px;color:var(--red);">
        ⚠ No medicine specified. <a href="catalog.html" style="color:var(--red);">Go back to catalog</a>
      </div>`;
        return;
    }

    try {
        const res = await fetch(`${API}/api/medicines/${id}`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Medicine not found.');

        _medicine = data;
        document.title = `${data.name} — Angel's Pharmacy`;
        document.getElementById('breadcrumb-name').textContent = data.name;
        renderDetail(data);

    } catch (err) {
        document.getElementById('detail-content').innerHTML = `
      <div style="text-align:center;padding:60px;color:var(--red);">
        ⚠ ${err.message}. <a href="catalog.html" style="color:var(--red);">Go back to catalog</a>
      </div>`;
    }
}

function renderDetail(med) {
    const img = med.image_url
        ? `<img class="detail-img" src="${med.image_url}" alt="${esc(med.name)}" onerror="this.parentElement.innerHTML='<div class=detail-img-placeholder>💊</div>'" />`
        : `<div class="detail-img-placeholder">💊</div>`;

    const typeBadge = med.requires_rx
        ? '<span class="badge rx">Rx — Prescription Required</span>'
        : '<span class="badge otc">OTC — No Prescription Needed</span>';

    const stockBadge = med.same_day_available
        ? '<span class="badge safe">✓ Same-day Available</span>'
        : '<span class="badge" style="background:#fff3e0;color:#b45309;">⏳ Next Business Day</span>';

    const rxNotice = med.requires_rx ? `
    <div class="rx-notice">
      <div class="ico">⚠️</div>
      <p><strong>Prescription Required.</strong> This medicine requires a valid prescription from a licensed physician. You will need to upload your prescription after logging in. A pharmacist will verify it before your order is prepared.</p>
    </div>` : '';

    document.getElementById('detail-content').innerHTML = `
    <div class="detail-grid">
      <div>
        <div class="detail-img-wrap">${img}</div>
      </div>
      <div class="detail-info">
        <div class="detail-header">
          <div class="detail-badges">
            ${typeBadge}
            ${stockBadge}
          </div>
          <h1 class="detail-name">${esc(med.name)}</h1>
          ${med.sku ? `<div class="detail-sku">SKU: ${esc(med.sku)}</div>` : ''}
          <div class="detail-price">₱${parseFloat(med.unit_price).toFixed(2)}</div>
          ${rxNotice}
          <div class="detail-actions" style="margin-top:${med.requires_rx ? '16px' : '0'};">
            <button class="btn" onclick="handleAddToCart()">🛒 Add to Cart</button>
            <a href="catalog.html" class="btn-ghost">← Back to Catalog</a>
          </div>
        </div>

        <div class="detail-card">
          <h3>Product Information</h3>
          ${med.category ? `
          <div class="detail-row">
            <span class="label">Category</span>
            <span class="value">${esc(med.category)}</span>
          </div>` : ''}
          <div class="detail-row">
            <span class="label">Type</span>
            <span class="value">${med.requires_rx ? 'Prescription (Rx)' : 'Over-the-Counter (OTC)'}</span>
          </div>
          <div class="detail-row">
            <span class="label">Availability</span>
            <span class="value">${med.same_day_available ? 'Same-day pick-up' : 'Next business day'}</span>
          </div>
          <div class="detail-row">
            <span class="label">Supplier Verified</span>
            <span class="value">${med.supplier_verified ? '✓ Yes' : '—'}</span>
          </div>
          ${med.sku ? `
          <div class="detail-row">
            <span class="label">SKU</span>
            <span class="value">${esc(med.sku)}</span>
          </div>` : ''}
          <div class="detail-row">
            <span class="label">Price</span>
            <span class="value" style="color:var(--red);font-size:15px;">₱${parseFloat(med.unit_price).toFixed(2)}</span>
          </div>
        </div>

        <div class="detail-card">
          <h3>Pick-up Information</h3>
          <div class="detail-row">
            <span class="label">Punturin Branch</span>
            <span class="value">Valenzuela City</span>
          </div>
          <div class="detail-row">
            <span class="label">Malinta Branch</span>
            <span class="value">Valenzuela City</span>
          </div>
          <div class="detail-row">
            <span class="label">Hours (Mon–Fri)</span>
            <span class="value">8:00 AM – 6:00 PM</span>
          </div>
          <div class="detail-row">
            <span class="label">Hours (Saturday)</span>
            <span class="value">8:00 AM – 12:00 PM</span>
          </div>
        </div>
      </div>
    </div>
  `;
}

/* ── Add to Cart — requires login ── */
function handleAddToCart() {
    const session = Auth.getSession();
    if (!session) {
        const currentPage = `medicine.html?id=${new URLSearchParams(window.location.search).get('id')}`;
        sessionStorage.setItem('ap_redirect_after_login', currentPage);
        if (_medicine) {
            sessionStorage.setItem('ap_pending_cart', JSON.stringify({
                id: _medicine.medicine_id,
                name: _medicine.name,
                price: _medicine.unit_price,
                requiresRx: _medicine.requires_rx,
            }));
        }
        document.getElementById('login-prompt-msg').innerHTML =
            _medicine
                ? `Please log in to add <strong>${esc(_medicine.name)}</strong> to your cart.`
                : 'Please log in to add items to your cart.';
        document.getElementById('login-redirect-btn').href =
            `index.html?redirect=${encodeURIComponent(currentPage)}`;
        document.getElementById('login-prompt').classList.add('open');
        return;
    }
    showToast(`✓ ${_medicine?.name || 'Medicine'} added to cart!`);
}

function closeLoginPrompt() { document.getElementById('login-prompt').classList.remove('open'); }
function handlePromptOverlay(e) { if (e.target === document.getElementById('login-prompt')) closeLoginPrompt(); }

function showToast(msg, duration = 3000) {
    const t = document.getElementById('toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), duration);
}

function esc(s) {
    if (!s) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

loadMedicine();