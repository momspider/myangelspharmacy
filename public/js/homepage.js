/* ── ✅ Auth guard — async, uses real Supabase session ── */
let _currentUser = null;

(async () => {
    _currentUser = await Auth.requireAuth();
    if (!_currentUser) return; // requireAuth() redirects if no session

    /* Populate user greeting */
    const firstName = (_currentUser.full_name || _currentUser.email).split(' ')[0];
    const initial = firstName.charAt(0).toUpperCase();
    const avatar = document.getElementById('user-avatar');
    const nameEl = document.getElementById('user-name');
    if (avatar) { avatar.textContent = initial; avatar.title = _currentUser.full_name || ''; }
    if (nameEl) { nameEl.textContent = 'Hi, ' + firstName + '!'; nameEl.style.display = ''; }

    /* Load data now that we have a valid session */
    await loadMedicines();
    await loadMyOrders();
})();

document.getElementById('year').textContent = new Date().getFullYear();

const logoImg = document.getElementById('logo-img');
if (logoImg) {
    logoImg.onload = () => { logoImg.style.display = ''; const fb = document.getElementById('logo-fallback'); if (fb) fb.style.display = 'none'; };
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

/* ── ✅ Load medicines from real API ── */
async function loadMedicines(search = '', sameDayOnly = false) {
    const grid = document.getElementById('products');
    const counter = document.getElementById('results-counter');
    grid.innerHTML = '<div style="text-align:center;padding:32px;color:var(--muted);">Loading…</div>';

    try {
        let path = '/medicines?';
        if (search) path += `search=${encodeURIComponent(search)}&`;
        if (sameDayOnly) path += `same_day=true&`;
        const res = await Auth.fetch(path);
        const data = await res.json();

        if (!res.ok) throw new Error(data.error || 'Failed to load medicines.');

        counter.textContent = `${data.length} result${data.length !== 1 ? 's' : ''}`;

        if (data.length === 0) {
            grid.innerHTML = '<div style="text-align:center;padding:32px;color:var(--muted);">No medicines found.</div>';
            return;
        }

        grid.innerHTML = data.map(med => `
        <div class="product-card" role="listitem" data-id="${med.medicine_id}">
          <div class="product-img-wrap">
            ${med.image_url
                ? `<img src="${med.image_url}" alt="${med.name}" class="product-img" style="width:100%;height:140px;object-fit:cover;border-radius:10px;" onerror="this.style.display='none'" />`
                : `<div style="font-size:28px;text-align:center;">💊</div>`}
          </div>
          <div class="product-info">
            <div class="product-name">${med.name}</div>
            <div style="display:flex;gap:6px;flex-wrap:wrap;margin:4px 0 8px;">
              ${med.requires_rx ? '<span class="badge rx">Rx</span>' : '<span class="badge otc">OTC</span>'}
              ${med.same_day_available ? '<span class="badge safe">Same Day</span>' : ''}
              ${med.category ? `<span class="badge" style="background:var(--off-white);color:var(--muted);border:1px solid var(--border);">${med.category}</span>` : ''}
            </div>
            <div class="product-price">₱${parseFloat(med.unit_price).toFixed(2)}</div>
          </div>
          <button class="btn add-to-cart"
                  data-id="${med.medicine_id}"
                  data-name="${med.name}"
                  data-price="${med.unit_price}"
                  data-rx="${med.requires_rx}"
                  onclick="window._addToCart && window._addToCart(this)">
            Add to Cart
          </button>
        </div>
      `).join('');

    } catch (err) {
        grid.innerHTML = `<div style="text-align:center;padding:32px;color:var(--red);">⚠ ${err.message}</div>`;
    }
}

/* ── ✅ Load my orders from real API ── */
async function loadMyOrders() {
    const container = document.getElementById('my-orders');
    try {
        const res = await Auth.fetch('/orders');
        const data = await res.json();

        if (!res.ok || data.length === 0) {
            container.innerHTML = '<div class="small muted">No orders yet.</div>';
            return;
        }

        const statusColors = {
            pending: 'var(--muted)',
            confirmed: '#1565C0',
            ready: '#2e7d32',
            completed: '#4caf50',
            cancelled: 'var(--red)',
        };

        container.innerHTML = data.slice(0, 5).map(order => `
      <div style="padding:10px 0;border-bottom:1px solid var(--border);">
        <div style="display:flex;justify-content:space-between;align-items:center;">
          <div style="font-size:13px;font-weight:600;">${order.branches?.name || 'Branch'}</div>
          <span style="font-size:12px;font-weight:700;color:${statusColors[order.status] || 'var(--muted)'};">
            ${order.status.toUpperCase()}
          </span>
        </div>
        <div class="small muted">${new Date(order.placed_at).toLocaleDateString('en-PH')} · ₱${parseFloat(order.total_amount).toFixed(2)}</div>
      </div>
    `).join('');

        // Poll for status updates every 10 seconds
        setTimeout(loadMyOrders, 10000);

    } catch (err) {
        container.innerHTML = '<div class="small muted">Could not load orders.</div>';
    }
}

/* ── Search & filter listeners ── */
let searchTimer;
document.getElementById('site-search').addEventListener('input', e => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
        const sameDayOnly = document.getElementById('filter-sameday').checked;
        loadMedicines(e.target.value.trim(), sameDayOnly);
    }, 350);
});

document.getElementById('filter-sameday').addEventListener('change', () => {
    const search = document.getElementById('site-search').value.trim();
    const sameDayOnly = document.getElementById('filter-sameday').checked;
    loadMedicines(search, sameDayOnly);
});

/* ── Quick refill shortcut ── */
document.getElementById('quick-refill').addEventListener('click', () => {
    document.getElementById('site-search').focus();
});

/* ── Prescription upload — sends to real API ── */
document.getElementById('rx-file').addEventListener('change', async function () {
    const file = this.files[0];
    if (!file) return;

    // Show preview immediately
    const previewName = document.getElementById('preview-name');
    const previewTime = document.getElementById('preview-time');
    const previewImg = document.getElementById('preview-img');
    const uploadPrompt = document.getElementById('upload-prompt');
    const uploadPreview = document.getElementById('upload-preview');

    previewName.textContent = file.name;
    previewTime.textContent = new Date().toLocaleString('en-PH');
    if (file.type.startsWith('image/')) {
        previewImg.src = URL.createObjectURL(file);
        previewImg.style.display = '';
    } else {
        previewImg.style.display = 'none';
    }
    uploadPrompt.style.display = 'none';
    uploadPreview.style.display = 'flex';

    // Update status timeline
    document.getElementById('st-uploaded').style.opacity = '1';
    document.getElementById('dot-uploaded').style.background = 'var(--red)';
});

/* ── Request verification button ── */
document.getElementById('request-verification')?.addEventListener('click', async function () {
    const file = document.getElementById('rx-file').files[0];
    const branchEl = document.querySelector('input[name="branch"]:checked');

    if (!file) { showToast('Please select a prescription file first.'); return; }
    if (!branchEl) { showToast('Please select a branch first.'); return; }

    this.disabled = true;
    this.textContent = 'Uploading…';

    try {
        const branchMap = {
            punturin: "12a814e2-f9b9-42a7-87a1-f5a66bfc5904",
            malinta: "850afc97-c7d3-4cc9-b119-deedb07fd1ac"
        };

        const formData = new FormData();
        formData.append('prescription', file);
        formData.append('branch_id', branchMap[branchEl.value]);

        const token = sessionStorage.getItem('ap_access_token');
        const res = await fetch('/api/prescriptions', {
            method: 'POST',
            headers: token ? { Authorization: `Bearer ${token}` } : {},
            body: formData,
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Upload failed.');

        // Save prescription ID to state for placeOrder
        if (typeof state !== 'undefined') {
            state.prescription = state.prescription || {};
            state.prescription.id = data.prescription_id;
            state.prescription.status = 'pending';
        }

        showToast('✓ Prescription uploaded! Awaiting pharmacist verification.');
        this.textContent = '✓ Uploaded';

        // Poll for pharmacist verification every 5 seconds
        const prescriptionId = data.prescription_id;
        const pollInterval = setInterval(async () => {
            try {
                const statusRes = await Auth.fetch('/prescriptions');
                const prescriptions = await statusRes.json();
                const current = prescriptions.find(p => p.prescription_id === prescriptionId);
                if (current) {
                    if (current.status === 'verified') {
                        if (typeof state !== 'undefined') state.prescription.status = 'verified';
                        const verifiedEl = document.getElementById('st-verified');
                        const verifiedDot = document.getElementById('dot-verified');
                        if (verifiedEl) verifiedEl.style.opacity = '1';
                        if (verifiedDot) verifiedDot.style.background = 'var(--red)';
                        showToast('✓ Prescription verified by pharmacist!');
                        clearInterval(pollInterval);
                    } else if (current.status === 'rejected') {
                        if (typeof state !== 'undefined') state.prescription.status = 'rejected';
                        showToast('⚠ Prescription rejected: ' + (current.rejection_reason || 'No reason given.'));
                        clearInterval(pollInterval);
                    }
                }
            } catch { }
        }, 5000);

    } catch (err) {
        showToast('⚠ ' + err.message);
        this.disabled = false;
        this.textContent = 'Request Verification';
    }
});

/* ── Toast helper ── */
function showToast(msg, duration = 3000) {
    const t = document.getElementById('toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), duration);
}