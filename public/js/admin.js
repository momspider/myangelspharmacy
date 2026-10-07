const API = '';

let _adminUser = null;
let _branches = [];
let _medicines = [];
let posCart = [];

/* ── Boot ── */
(async () => {
    // Allow both admin and pharmacist (staff) roles
    _adminUser = await Auth.requireAuth();
    if (!_adminUser) return;

    if (!['admin', 'pharmacist'].includes(_adminUser.role)) {
        window.location.replace('homepage.html');
        return;
    }

    const isAdmin = _adminUser.role === 'admin';

    // Hide admin-only elements for staff
    if (!isAdmin) {
        document.querySelectorAll('.admin-only').forEach(el => el.style.display = 'none');
        document.getElementById('topbar-pill').textContent = '💊 Staff Access';
        document.getElementById('panel-role-label').textContent = 'Staff Panel';
    }

    const name = _adminUser.full_name || _adminUser.email;
    document.getElementById('admin-avatar').textContent = name.charAt(0).toUpperCase();
    document.getElementById('admin-name').textContent = name;
    document.getElementById('admin-email').textContent = isAdmin ? 'Administrator' : 'Staff / Pharmacist';
    document.getElementById('settings-email').textContent = _adminUser.email;
    document.getElementById('settings-role').textContent = isAdmin ? 'Administrator' : 'Staff / Pharmacist';

    await Promise.all([loadDashboard(), loadBranches()]);
    if (isAdmin) { loadUsers(); loadProducts(); }
    loadPrescriptions();
    loadOrders();
})();

/* ── DASHBOARD ── */
async function loadDashboard() {
    try {
        const res = await Auth.fetch(`${API}/admin/dashboard`);
        const data = await res.json();
        if (!res.ok) return;
        const orders = data.orders || {};
        const total = Object.values(orders).reduce((s, v) => s + v, 0);
        document.getElementById('stat-orders').textContent = total;
        document.getElementById('stat-pending').textContent = data.pending_prescriptions ?? '—';
        document.getElementById('stat-lowstock').textContent = data.low_stock_items ?? '—';
        document.getElementById('stat-revenue').textContent = '₱' + parseFloat(data.revenue_last_30_days || 0).toLocaleString('en-PH', { minimumFractionDigits: 2 });
    } catch { }

    try {
        const res = await Auth.fetch(`${API}/orders/admin/all`);
        const data = await res.json();
        if (!res.ok || !data.length) {
            document.getElementById('activity-feed').innerHTML = '<div style="padding:24px;text-align:center;color:var(--muted);">No recent activity.</div>';
            return;
        }
        document.getElementById('activity-feed').innerHTML = data.slice(0, 5).map(o => `
      <div class="activity-item">
        <div class="activity-dot">📦</div>
        <div>
          <div class="activity-text"><strong>Order ${o.order_id.slice(0, 8)}…</strong> — ${o.profiles?.full_name || 'Customer'} · ${o.branches?.name || ''}</div>
          <div class="activity-time">${new Date(o.placed_at).toLocaleString('en-PH')} · ₱${parseFloat(o.total_amount).toFixed(2)} · <strong>${o.status}</strong></div>
        </div>
      </div>
    `).join('');
    } catch { }
}

/* ── BRANCHES ── */
async function loadBranches() {
    try {
        const res = await Auth.fetch(`${API}/admin/inventory`);
        const data = await res.json();
        if (res.ok && data.length) {
            const seen = new Set();
            _branches = data
                .filter(i => { if (seen.has(i.branches?.name)) return false; seen.add(i.branches?.name); return true; })
                .map(i => ({ id: i.branch_id, name: i.branches?.name }));
        }
    } catch { }

    if (!_branches.length) {
        try {
            const res = await Auth.fetch(`${API}/admin/branches`);
            const data = await res.json();
            if (res.ok && data.length) {
                _branches = data.map(b => ({ id: b.branch_id, name: b.name, address: b.address, city: b.city }));
            }
        } catch { }
    }

    renderBranchSelect();
    renderBranchesPanel();
}

function renderBranchSelect() {
    const sel = document.getElementById('pos-branch');
    sel.innerHTML = '<option value="">Select branch…</option>' +
        _branches.map(b => `<option value="${b.id}">${b.name}</option>`).join('');
}

function renderBranchesPanel() {
    const grid = document.getElementById('branches-grid');
    if (!_branches.length) {
        grid.innerHTML = '<div class="card"><p class="muted">No branch data available.</p></div>';
        return;
    }
    const now = new Date();
    const phHour = parseInt(new Intl.DateTimeFormat('en-PH', { hour: 'numeric', hour12: false, timeZone: 'Asia/Manila' }).format(now));
    const phDay = new Intl.DateTimeFormat('en-PH', { weekday: 'short', timeZone: 'Asia/Manila' }).format(now);
    const isSat = phDay === 'Sat', isSun = phDay === 'Sun';
    let isOpen, hoursLabel;
    const satLabel = '8:00 AM – 12:00 PM', weekLabel = '8:00 AM – 6:00 PM';
    if (isSun) { isOpen = false; hoursLabel = 'Closed today (Sunday)'; }
    else if (isSat) { isOpen = phHour >= 8 && phHour < 12; hoursLabel = satLabel; }
    else { isOpen = phHour >= 8 && phHour < 18; hoursLabel = weekLabel; }

    grid.innerHTML = _branches.map(b => `
    <div class="card">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
        <div>
          <h3 style="margin:0 0 3px;font-size:16px;font-family:'Playfair Display',serif;color:var(--red);">🏥 ${esc(b.name)}</h3>
          <div class="muted" style="font-size:12px;">${esc(b.city || 'Valenzuela City')}</div>
        </div>
        <span class="status-pill ${isOpen ? 'verified' : 'inactive'}">${isOpen ? '● Open Now' : '○ Closed'}</span>
      </div>
      <div class="info-row"><div class="info-icon">📍</div><div><div class="info-label">Address</div><div class="info-value">${esc(b.address || 'Valenzuela City')}</div></div></div>
      <div class="info-row"><div class="info-icon">🕐</div><div><div class="info-label">Today's Hours</div><div class="info-value">${hoursLabel}</div></div></div>
      <div class="info-row"><div class="info-icon">📅</div><div><div class="info-label">Mon–Fri</div><div class="info-value">${weekLabel}</div></div></div>
      <div class="info-row"><div class="info-icon">📅</div><div><div class="info-label">Saturday</div><div class="info-value">${satLabel}</div></div></div>
      <div class="info-row"><div class="info-icon">🚫</div><div><div class="info-label">Sunday</div><div class="info-value">Closed</div></div></div>
    </div>
  `).join('');
}

/* ── USERS ── */
async function loadUsers() {
    const tbody = document.getElementById('users-tbody');
    const label = document.getElementById('user-count-label');
    try {
        const res = await Auth.fetch('/admin/users');
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);

        document.getElementById('stat-users').textContent = data.length;
        label.textContent = `${data.length} registered users`;

        if (!data.length) {
            tbody.innerHTML = '<tr><td colspan="7" style="padding:24px;text-align:center;color:var(--muted);">No users yet.</td></tr>';
            return;
        }

        tbody.innerHTML = data.map((u, i) => `
      <tr>
        <td class="muted">${i + 1}</td>
        <td><strong>${esc(u.full_name || '—')}</strong></td>
        <td class="muted">${esc(u.email)}</td>
        <td class="muted">${esc(u.phone || '—')}</td>
        <td>${statusPill(u.role)}</td>
        <td class="muted">${new Date(u.created_at).toLocaleDateString('en-PH')}</td>
        <td>
          ${u.role === 'customer' ? `<button class="row-action" onclick="changeUserRole('${u.id}', 'pharmacist')">Make Staff</button>` : ''}
          ${u.role === 'pharmacist' ? `<button class="row-action" onclick="changeUserRole('${u.id}', 'admin')">Make Admin</button><button class="row-action danger" onclick="changeUserRole('${u.id}', 'customer')">Revoke</button>` : ''}
          ${u.role === 'admin' ? `<button class="row-action danger" onclick="changeUserRole('${u.id}', 'customer')">Revoke</button>` : ''}
        </td>
      </tr>
    `).join('');
    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="7" style="padding:24px;text-align:center;color:var(--red);">⚠ ${err.message}</td></tr>`;
    }
}

async function changeUserRole(userId, role) {
    const labels = { pharmacist: 'Staff / Pharmacist', admin: 'Administrator', customer: 'Customer' };
    if (!confirm(`Change this user's role to "${labels[role] || role}"?`)) return;
    const res = await Auth.fetch(`/admin/users/${userId}/role`, {
        method: 'POST',
        body: JSON.stringify({ role }),
    });
    if (res.ok) { showToast(`✓ Role updated to ${labels[role] || role}.`); loadUsers(); }
    else { const d = await res.json(); showToast('⚠ ' + d.error); }
}

/* ── PRODUCTS ── */
async function loadProducts() {
    try {
        const res = await Auth.fetch(`${API}/medicines`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);

        _medicines = data;
        document.getElementById('stat-products').textContent = data.length;

        const tbody = document.getElementById('products-tbody');
        tbody.innerHTML = data.map(p => `
      <tr>
        <td><strong>${esc(p.name)}</strong></td>
        <td>₱${parseFloat(p.unit_price).toFixed(2)}</td>
        <td>${p.requires_rx ? '<span class="status-pill pending">Rx</span>' : '<span class="status-pill verified">OTC</span>'}</td>
        <td>${p.same_day_available ? '✅ Yes' : '⏳ No'}</td>
        <td class="muted">${esc(p.category || '—')}</td>
        <td>${p.is_active ? '<span class="status-pill active">Active</span>' : '<span class="status-pill inactive">Inactive</span>'}</td>
        <td>
          <button class="row-action" onclick="openEditModal('${p.medicine_id}')">Edit</button>
          <button class="row-action danger" onclick="deactivateProduct('${p.medicine_id}', '${esc(p.name)}')">Remove</button>
        </td>
      </tr>
    `).join('');

        renderPosProducts();
    } catch (err) {
        document.getElementById('products-tbody').innerHTML =
            `<tr><td colspan="7" style="padding:24px;text-align:center;color:var(--red);">⚠ ${err.message}</td></tr>`;
    }
}

async function deactivateProduct(id, name) {
    if (!confirm(`Deactivate "${name}"? It will no longer appear in the catalogue.`)) return;
    const res = await Auth.fetch(`${API}/medicines/${id}`, { method: 'DELETE' });
    if (res.ok) { showToast('Product deactivated.'); loadProducts(); }
    else { const d = await res.json(); showToast('⚠ ' + d.error); }
}

/* ── PRESCRIPTIONS ── */
async function loadPrescriptions() {
    try {
        const res = await Auth.fetch(`${API}/prescriptions/pending`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);

        document.getElementById('rx-count-label').textContent = `${data.length} pending`;
        document.getElementById('stat-pending').textContent = data.length;

        const tbody = document.getElementById('rx-tbody');
        if (!data.length) {
            tbody.innerHTML = '<tr><td colspan="6" style="padding:24px;text-align:center;color:var(--muted);">✓ No pending prescriptions.</td></tr>';
            return;
        }
        tbody.innerHTML = data.map(r => `
      <tr>
        <td><strong>${esc(r.profiles?.full_name || '—')}</strong><br><span class="muted">${esc(r.profiles?.phone || '')}</span></td>
        <td class="muted">${esc(r.file_name || r.prescription_id.slice(0, 8) + '…')}</td>
        <td>${esc(r.branches?.name || '—')}</td>
        <td class="muted">${new Date(r.uploaded_at).toLocaleString('en-PH')}</td>
        <td>${statusPill(r.status)}</td>
        <td>
          <button class="row-action" onclick="viewRxFile('${r.prescription_id}')">View</button>
          <button class="row-action" onclick="approveRx('${r.prescription_id}')">Approve</button>
          <button class="row-action danger" onclick="rejectRx('${r.prescription_id}')">Reject</button>
        </td>
      </tr>
    `).join('');
    } catch (err) {
        document.getElementById('rx-tbody').innerHTML =
            `<tr><td colspan="6" style="padding:24px;text-align:center;color:var(--red);">⚠ ${err.message}</td></tr>`;
    }
}

async function viewRxFile(id) {
    const res = await Auth.fetch(`${API}/prescriptions/${id}/file`);
    const data = await res.json();
    if (res.ok) window.open(data.url, '_blank');
    else showToast('⚠ Could not load file.');
}

async function approveRx(id) {
    if (!confirm('Approve this prescription?')) return;
    const res = await Auth.fetch(`${API}/prescriptions/${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ status: 'verified' }),
    });
    if (res.ok) { showToast('✓ Prescription approved!'); loadPrescriptions(); }
    else { const d = await res.json(); showToast('⚠ ' + d.error); }
}

async function rejectRx(id) {
    const reason = prompt('Reason for rejection:');
    if (!reason) return;
    const res = await Auth.fetch(`${API}/prescriptions/${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ status: 'rejected', rejection_reason: reason }),
    });
    if (res.ok) { showToast('Prescription rejected.'); loadPrescriptions(); }
    else { const d = await res.json(); showToast('⚠ ' + d.error); }
}

/* ── ORDERS ── */
async function loadOrders() {
    const status = document.getElementById('order-status-filter')?.value || '';
    try {
        let url = `${API}/orders/admin/all`;
        if (status) url += `?status=${status}`;
        const res = await Auth.fetch(url);
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);

        const tbody = document.getElementById('orders-tbody');
        if (!data.length) {
            tbody.innerHTML = '<tr><td colspan="7" style="padding:24px;text-align:center;color:var(--muted);">No orders found.</td></tr>';
            return;
        }
        tbody.innerHTML = data.map(o => `
      <tr>
        <td class="muted"><strong>${o.order_id.slice(0, 8)}…</strong></td>
        <td>${esc(o.profiles?.full_name || '—')}<br><span class="muted" style="font-size:11px;">${esc(o.profiles?.phone || '')}</span></td>
        <td>${esc(o.branches?.name || '—')}</td>
        <td>₱${parseFloat(o.total_amount).toFixed(2)}</td>
        <td class="muted">${new Date(o.placed_at).toLocaleString('en-PH')}</td>
        <td>${statusPill(o.status)}</td>
        <td>
          ${o.status === 'pending' ? `<button class="row-action" onclick="updateOrderStatus('${o.order_id}','confirmed')">Confirm</button>` : ''}
          ${o.status === 'confirmed' ? `<button class="row-action" onclick="updateOrderStatus('${o.order_id}','ready')">Mark Ready</button>` : ''}
          ${o.status === 'ready' ? `<button class="row-action" onclick="updateOrderStatus('${o.order_id}','completed')">Complete</button>` : ''}
          ${['pending', 'confirmed'].includes(o.status) ? `<button class="row-action danger" onclick="updateOrderStatus('${o.order_id}','cancelled')">Cancel</button>` : ''}
        </td>
      </tr>
    `).join('');
    } catch (err) {
        document.getElementById('orders-tbody').innerHTML =
            `<tr><td colspan="7" style="padding:24px;text-align:center;color:var(--red);">⚠ ${err.message}</td></tr>`;
    }
}

async function updateOrderStatus(id, status) {
    const res = await Auth.fetch(`${API}/orders/${id}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status }),
    });
    if (res.ok) { showToast(`✓ Order marked as ${status}.`); loadOrders(); loadDashboard(); }
    else { const d = await res.json(); showToast('⚠ ' + d.error); }
}

/* ── POS ── */
function renderPosProducts(filter = '') {
    const grid = document.getElementById('pos-products-grid');
    const list = _medicines.filter(m =>
        m.is_active && (!filter || m.name.toLowerCase().includes(filter.toLowerCase()))
    );
    if (!list.length) {
        grid.innerHTML = '<div style="grid-column:1/-1;padding:32px;text-align:center;color:var(--muted);">No medicines found.</div>';
        return;
    }
    grid.innerHTML = list.map(m => `
    <button class="pos-product-btn ${m.requires_rx ? 'rx-item' : ''}"
            onclick="addToPosCart('${m.medicine_id}', ${JSON.stringify(m.name).replace(/'/g, "\\'")} , ${m.unit_price}, ${m.requires_rx})">
      <span class="pos-product-badge ${m.requires_rx ? 'status-pill pending' : 'status-pill verified'}">${m.requires_rx ? 'Rx' : 'OTC'}</span>
      <span class="pos-product-name">${esc(m.name)}</span>
      <span class="pos-product-price">₱${parseFloat(m.unit_price).toFixed(2)}</span>
    </button>
  `).join('');
}

function filterPosProducts(val) { renderPosProducts(val); }

function addToPosCart(id, name, price, requiresRx) {
    const existing = posCart.find(i => i.id === id);
    if (existing) { existing.qty++; }
    else { posCart.push({ id, name, price: parseFloat(price), requiresRx, qty: 1 }); }
    renderPosCart();
}

function renderPosCart() {
    const container = document.getElementById('pos-cart-items');
    const countEl = document.getElementById('pos-item-count');
    const totalEl = document.getElementById('pos-total');

    if (!posCart.length) {
        container.innerHTML = '<div class="pos-empty">No items added yet.<br>Click a product to add it.</div>';
        countEl.textContent = '0 items';
        totalEl.textContent = '₱0.00';
        return;
    }

    const total = posCart.reduce((s, i) => s + i.price * i.qty, 0);
    countEl.textContent = `${posCart.reduce((s, i) => s + i.qty, 0)} items`;
    totalEl.textContent = `₱${total.toFixed(2)}`;

    container.innerHTML = posCart.map(item => `
    <div class="pos-cart-item">
      <div style="flex:1;">
        <div class="pos-item-name">${esc(item.name)} ${item.requiresRx ? '<span style="font-size:10px;color:var(--red);">Rx</span>' : ''}</div>
        <div class="pos-item-price">₱${item.price.toFixed(2)} each</div>
      </div>
      <button class="pos-qty-btn" onclick="changePosQty('${item.id}', -1)">−</button>
      <span class="pos-qty">${item.qty}</span>
      <button class="pos-qty-btn" onclick="changePosQty('${item.id}', 1)">+</button>
    </div>
  `).join('');
}

function changePosQty(id, delta) {
    const item = posCart.find(i => i.id === id);
    if (!item) return;
    item.qty += delta;
    if (item.qty <= 0) posCart = posCart.filter(i => i.id !== id);
    renderPosCart();
}

function clearPosCart() {
    posCart = [];
    document.querySelectorAll('.pos-payment-btn').forEach(b => b.classList.remove('selected'));
    renderPosCart();
}



async function processSale() {
    if (!posCart.length) { showToast('⚠ Add items to the cart first.'); return; }
    const branchId = document.getElementById('pos-branch').value;
    if (!branchId) { showToast('⚠ Select a branch.'); return; }

    const btn = document.getElementById('pos-process-btn');
    btn.disabled = true; btn.textContent = 'Processing…';

    try {
        const items = posCart.map(i => ({ medicine_id: i.id, quantity: i.qty }));
        const res = await Auth.fetch(`${API}/orders`, {
            method: 'POST',
            body: JSON.stringify({ branch_id: branchId, items, notes: 'POS walk-in sale · Payment at pick-up' }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);

        await Auth.fetch(`${API}/orders/${data.order_id}/status`, {
            method: 'PATCH',
            body: JSON.stringify({ status: 'completed' }),
        });

        showReceipt(data.order_id, branchId);
        clearPosCart();
        loadDashboard();
    } catch (err) {
        showToast('⚠ ' + err.message);
    } finally {
        btn.disabled = false; btn.textContent = 'Process Sale →';
    }
}

function showReceipt(orderId, branchId) {
    const branch = _branches.find(b => b.id === branchId);
    const total = posCart.reduce((s, i) => s + i.price * i.qty, 0);
    const now = new Date().toLocaleString('en-PH');
    const items = [...posCart];

    document.getElementById('receipt-body').innerHTML = `
    <div class="receipt-row" style="border:none;padding-bottom:4px;"><span style="color:var(--muted);">Branch</span><span>${esc(branch?.name || 'Branch')}</span></div>
    <div class="receipt-row" style="border:none;padding-bottom:4px;"><span style="color:var(--muted);">Date &amp; Time</span><span>${now}</span></div>
    <div class="receipt-row" style="border:none;padding-bottom:4px;"><span style="color:var(--muted);">Payment</span><span>To be collected at pick-up</span></div>
    <div class="receipt-row" style="border:none;padding-bottom:4px;"><span style="color:var(--muted);">Order ID</span><span style="font-size:11px;">${orderId.slice(0, 8)}…</span></div>
    <div style="border-top:1px dashed var(--border);margin:10px 0;"></div>
    ${items.map(i => `<div class="receipt-row"><span>${esc(i.name)} × ${i.qty}</span><span>₱${(i.price * i.qty).toFixed(2)}</span></div>`).join('')}
    <div style="border-top:2px solid var(--border);margin:10px 0;"></div>
    <div class="receipt-total"><span>TOTAL</span><span>₱${total.toFixed(2)}</span></div>
    <div style="text-align:center;margin-top:16px;font-size:12px;color:var(--muted);">Thank you for your purchase!<br>Angel's Pharmacy — Valenzuela City</div>
  `;
    document.getElementById('receipt-overlay').classList.add('open');
}

function closeReceipt() { document.getElementById('receipt-overlay').classList.remove('open'); }
function printReceipt() { window.print(); }

/* ── EDIT PRODUCT MODAL ── */
function openAddProductModal() {
    document.getElementById('edit-id').value = '';
    document.getElementById('edit-name').value = '';
    document.getElementById('edit-price').value = '';
    document.getElementById('edit-rx').value = 'false';
    document.getElementById('edit-sameday').value = 'true';
    document.getElementById('edit-title').textContent = 'Add New Product';
    document.getElementById('edit-overlay').classList.add('open');
}

function openEditModal(id) {
    const p = _medicines.find(m => m.medicine_id === id);
    if (!p) return;
    document.getElementById('edit-id').value = id;
    document.getElementById('edit-name').value = p.name;
    document.getElementById('edit-price').value = p.unit_price;
    document.getElementById('edit-rx').value = String(p.requires_rx);
    document.getElementById('edit-sameday').value = String(p.same_day_available);
    document.getElementById('edit-title').textContent = 'Edit — ' + p.name;
    document.getElementById('edit-overlay').classList.add('open');
}

function closeEditModal() { document.getElementById('edit-overlay').classList.remove('open'); }
function handleEditOverlay(e) { if (e.target === document.getElementById('edit-overlay')) closeEditModal(); }

async function saveEdit() {
    const id = document.getElementById('edit-id').value;
    const body = {
        name: document.getElementById('edit-name').value.trim(),
        unit_price: parseFloat(document.getElementById('edit-price').value),
        requires_rx: document.getElementById('edit-rx').value === 'true',
        same_day_available: document.getElementById('edit-sameday').value === 'true',
    };

    if (id) {
        const res = await Auth.fetch(`${API}/medicines/${id}`, { method: 'PUT', body: JSON.stringify(body) });
        if (res.ok) { showToast('✓ Product updated.'); closeEditModal(); loadProducts(); }
        else { const d = await res.json(); showToast('⚠ ' + d.error); }
    } else {
        const res = await Auth.fetch(`${API}/medicines`, { method: 'POST', body: JSON.stringify(body) });
        if (res.ok) { showToast('✓ Product added.'); closeEditModal(); loadProducts(); }
        else { const d = await res.json(); showToast('⚠ ' + d.error); }
    }
}

/* ── PANEL SWITCHING ── */
const panelTitles = {
    dashboard: 'Dashboard', pos: '🧾 Point of Sale',
    users: 'Users', products: 'Products',
    prescriptions: 'Prescriptions', orders: 'Orders',
    branches: 'Branches', settings: 'Settings',
};

function switchPanel(name, btn) {
    document.querySelectorAll('.admin-panel').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.sidebar-link').forEach(l => l.classList.remove('active'));
    const panel = document.getElementById('panel-' + name);
    if (panel) panel.classList.add('active');
    if (btn) btn.classList.add('active');
    document.getElementById('topbar-title').textContent = panelTitles[name] || name;
    document.getElementById('sidebar').classList.remove('open');
    if (name === 'prescriptions') loadPrescriptions();
    if (name === 'orders') loadOrders();
    if (name === 'pos') renderPosProducts();
}

function toggleSidebar() { document.getElementById('sidebar').classList.toggle('open'); }

/* ── HELPERS ── */
function statusPill(s) {
    const map = {
        pending: ['pending', '⏳ Pending'],
        confirmed: ['ready', '✓ Confirmed'],
        verified: ['verified', '✓ Verified'],
        ready: ['ready', '📦 Ready'],
        completed: ['completed', '✅ Completed'],
        cancelled: ['cancelled', '✕ Cancelled'],
        active: ['active', '● Active'],
        inactive: ['inactive', '✕ Inactive'],
        rejected: ['cancelled', '✕ Rejected'],
        admin: ['verified', '🛡️ Admin'],
        pharmacist: ['ready', '💊 Staff'],
        customer: ['inactive', '👤 Customer'],
    };
    const [cls, label] = map[s] || ['inactive', s];
    return `<span class="status-pill ${cls}">${label}</span>`;
}

function esc(s) {
    if (s == null) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

function showToast(msg, duration = 3500) {
    const t = document.getElementById('toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), duration);
}