const API = '';
let allMedicines = [];
let activeCategory = '';

/* ── On load ── */
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

/* ── Nav auth state ── */
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

/* ── Load medicines (public — no auth needed) ── */
async function loadMedicines() {
    try {
        const res = await fetch(`${API}/api/medicines`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Failed to load medicines.');

        allMedicines = data;

        /* Populate category filter and pills */
        const categories = [...new Set(data.map(m => m.category).filter(Boolean))].sort();
        const catFilter = document.getElementById('category-filter');
        const catPills = document.getElementById('category-pills');

        catFilter.innerHTML = '<option value="">All Categories</option>' +
            categories.map(c => `<option value="${c}">${c}</option>`).join('');

        catPills.innerHTML = `<button class="cat-pill active" onclick="setCategoryPill('', this)">All</button>` +
            categories.map(c =>
                `<button class="cat-pill" onclick="setCategoryPill('${c}', this)">${c}</button>`
            ).join('');

        renderMedicines(data);

    } catch (err) {
        document.getElementById('med-grid').innerHTML = `
      <div style="grid-column:1/-1;text-align:center;padding:48px;color:var(--red);">
        ⚠ ${err.message}
      </div>`;
        document.getElementById('results-count').textContent = 'Error loading medicines';
    }
}

function renderMedicines(list) {
    const grid = document.getElementById('med-grid');
    const count = document.getElementById('results-count');

    count.textContent = `${list.length} medicine${list.length !== 1 ? 's' : ''} found`;

    if (!list.length) {
        grid.innerHTML = `
      <div style="grid-column:1/-1;" class="empty-state">
        <div class="ico">🔍</div>
        <h3>No medicines found</h3>
        <p>Try adjusting your search or filters.</p>
      </div>`;
        return;
    }

    grid.innerHTML = list.map(med => {
        const stockBadge = med.same_day_available
            ? '<span class="stock-badge in-stock">● In Stock</span>'
            : '<span class="stock-badge low-stock">⏳ Next Day</span>';

        const typeBadge = med.requires_rx
            ? '<span class="badge rx">Rx</span>'
            : '<span class="badge otc">OTC</span>';

        const img = med.image_url
            ? `<img class="med-img" src="${med.image_url}" alt="${esc(med.name)}" onerror="this.parentElement.innerHTML='<div class=med-img-placeholder>💊</div>'" />`
            : `<div class="med-img-placeholder">💊</div>`;

        return `
      <div class="med-card">
        ${img}
        <div class="med-body">
          <div class="med-badges">
            ${typeBadge}
            ${stockBadge}
            ${med.category ? `<span class="badge" style="background:var(--off-white);color:var(--muted);border:1px solid var(--border);">${esc(med.category)}</span>` : ''}
          </div>
          <div class="med-name">${esc(med.name)}</div>
          ${med.sku ? `<div class="med-generic">SKU: ${esc(med.sku)}</div>` : ''}
          <div class="med-price">₱${parseFloat(med.unit_price).toFixed(2)}</div>
        </div>
        <div class="med-actions">
          <a href="medicine.html?id=${med.medicine_id}" class="btn-ghost med-actions">View Details</a>
          <button class="btn" onclick="handleAddToCart('${med.medicine_id}', '${esc(med.name)}', ${med.unit_price}, ${med.requires_rx})">
            Add to Cart
          </button>
        </div>
      </div>
    `;
    }).join('');
}

function applyFilters() {
    const search = document.getElementById('search-input').value.toLowerCase();
    const category = activeCategory || document.getElementById('category-filter').value;
    const type = document.getElementById('type-filter').value;
    const sameday = document.getElementById('sameday-filter').checked;

    let filtered = allMedicines.filter(m => {
        if (search && !m.name.toLowerCase().includes(search) && !(m.category || '').toLowerCase().includes(search)) return false;
        if (category && m.category !== category) return false;
        if (type === 'otc' && m.requires_rx) return false;
        if (type === 'rx' && !m.requires_rx) return false;
        if (sameday && !m.same_day_available) return false;
        return true;
    });

    renderMedicines(filtered);
}

function setCategoryPill(cat, btn) {
    activeCategory = cat;
    document.querySelectorAll('.cat-pill').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('category-filter').value = cat;
    applyFilters();
}

/* ── Search debounce ── */
let searchTimer;
document.getElementById('search-input').addEventListener('input', () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(applyFilters, 300);
});

/* ── Add to Cart — requires login ── */
function handleAddToCart(id, name, price, requiresRx) {
    const session = Auth.getSession();
    if (!session) {
        /* Save intended action and show login prompt */
        sessionStorage.setItem('ap_redirect_after_login', 'catalog.html');
        sessionStorage.setItem('ap_pending_cart', JSON.stringify({ id, name, price, requiresRx }));
        showLoginPrompt(`Please log in first to add <strong>${name}</strong> to your cart.`);
        return;
    }
    /* User is logged in — add to cart via backend.js cart system */
    if (window._addToCart) {
        window._addToCart({ dataset: { id, name, price, rx: requiresRx } });
    } else {
        showToast(`✓ ${name} added to cart!`);
    }
}

/* ── Login prompt ── */
function showLoginPrompt(msg) {
    document.getElementById('login-prompt-msg').innerHTML = msg;
    const redirectBtn = document.getElementById('login-redirect-btn');
    redirectBtn.href = `index.html?redirect=catalog.html`;
    document.getElementById('login-prompt').classList.add('open');
}
function closeLoginPrompt() { document.getElementById('login-prompt').classList.remove('open'); }
function handlePromptOverlay(e) { if (e.target === document.getElementById('login-prompt')) closeLoginPrompt(); }

/* ── Toast ── */
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

/* ── Boot ── */
loadMedicines();