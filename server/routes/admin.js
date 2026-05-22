// routes/admin.js
// All routes require admin or staff role.
// GET  /api/admin/dashboard        — summary stats
// GET  /api/admin/inventory        — stock levels across branches
// POST /api/admin/inventory        — update stock
// GET  /api/admin/sales            — sales log
// GET  /api/admin/contacts         — contact form submissions
// PATCH /api/admin/contacts/:id    — mark as read
// POST /api/admin/users/:id/role   — change user role (admin only)

import { Router } from 'express';
import { supabaseAdmin } from '../lib/supabase.js';
import { requireStaff, requireAdmin } from '../lib/authMiddleware.js';

const router = Router();

/* ── DASHBOARD STATS ─────────────────────────────────────────────── */
router.get('/dashboard', requireStaff, async (req, res) => {
  const [orders, prescriptions, inventory, sales] = await Promise.all([
    supabaseAdmin.from('orders').select('status', { count: 'exact' }),
    supabaseAdmin.from('prescriptions').select('status', { count: 'exact' }).eq('status', 'pending'),
    supabaseAdmin.from('inventory').select('stock_quantity, reorder_level'),
    supabaseAdmin.from('sales').select('unit_price, quantity')
      .gte('sale_timestamp', new Date(Date.now() - 30 * 86400000).toISOString()), // last 30 days
  ]);

  const orderCounts = {};
  (orders.data || []).forEach(o => {
    orderCounts[o.status] = (orderCounts[o.status] || 0) + 1;
  });

  const lowStock = (inventory.data || []).filter(
    i => i.stock_quantity <= i.reorder_level
  ).length;

  const revenue30d = (sales.data || []).reduce(
    (sum, s) => sum + (s.unit_price * s.quantity), 0
  );

  return res.json({
    orders: orderCounts,
    pending_prescriptions: prescriptions.count || 0,
    low_stock_items: lowStock,
    revenue_last_30_days: revenue30d.toFixed(2),
  });
});

/* ── INVENTORY ───────────────────────────────────────────────────── */
router.get('/inventory', requireStaff, async (req, res) => {
  const { branch_id } = req.query;

  let query = supabaseAdmin
    .from('inventory')
    .select(`
      inventory_id, stock_quantity, reorder_level, updated_at,
      branches ( name ),
      medicines ( medicine_id, name, sku, unit_price, category )
    `)
    .order('stock_quantity', { ascending: true });

  if (branch_id) query = query.eq('branch_id', branch_id);

  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  return res.json(data);
});

router.post('/inventory', requireAdmin, async (req, res) => {
  const { branch_id, medicine_id, stock_quantity, reorder_level } = req.body;

  if (!branch_id || !medicine_id || stock_quantity === undefined) {
    return res.status(400).json({ error: 'branch_id, medicine_id, stock_quantity required.' });
  }

  const { data, error } = await supabaseAdmin
    .from('inventory')
    .upsert({ branch_id, medicine_id, stock_quantity, reorder_level: reorder_level ?? 10 },
             { onConflict: 'branch_id,medicine_id' })
    .select()
    .single();

  if (error) return res.status(400).json({ error: error.message });
  return res.json(data);
});

/* ── SALES LOG ───────────────────────────────────────────────────── */
router.get('/sales', requireStaff, async (req, res) => {
  const { branch_id, from, to } = req.query;

  let query = supabaseAdmin
    .from('sales')
    .select(`
      sale_id, quantity, unit_price, sale_timestamp,
      branches ( name ),
      medicines ( name, category )
    `)
    .order('sale_timestamp', { ascending: false })
    .limit(500);

  if (branch_id) query = query.eq('branch_id', branch_id);
  if (from)      query = query.gte('sale_timestamp', from);
  if (to)        query = query.lte('sale_timestamp', to);

  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  return res.json(data);
});

/* ── CONTACT MESSAGES ────────────────────────────────────────────── */
router.get('/contacts', requireAdmin, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('contact_messages')
    .select('*')
    .order('submitted_at', { ascending: false });

  if (error) return res.status(500).json({ error: error.message });
  return res.json(data);
});

router.patch('/contacts/:id', requireAdmin, async (req, res) => {
  const { error } = await supabaseAdmin
    .from('contact_messages')
    .update({ is_read: true })
    .eq('message_id', req.params.id);

  if (error) return res.status(400).json({ error: error.message });
  return res.json({ message: 'Marked as read.' });
});

/* ── CHANGE USER ROLE (admin only) ───────────────────────────────── */
router.post('/users/:id/role', requireAdmin, async (req, res) => {
  const { role } = req.body;
  const validRoles = ['customer', 'pharmacist', 'admin'];

  if (!validRoles.includes(role)) {
    return res.status(400).json({ error: `Role must be one of: ${validRoles.join(', ')}` });
  }

  const { error } = await supabaseAdmin
    .from('profiles')
    .update({ role })
    .eq('id', req.params.id);

  if (error) return res.status(400).json({ error: error.message });
  return res.json({ message: `User role updated to "${role}".` });
});

/* ── USERS LIST (admin only) ─────────────────────────────────────── */
router.get('/users', requireAdmin, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('profiles')
    .select('id, full_name, phone, role, branch_id, created_at');

  if (error) return res.status(500).json({ error: error.message });

  // Get emails from auth.users
  const { data: authUsers, error: authErr } = await supabaseAdmin.auth.admin.listUsers();
  if (authErr) return res.status(500).json({ error: authErr.message });

  const emailMap = {};
  authUsers.users.forEach(u => { emailMap[u.id] = u.email; });

  const merged = (data || []).map(p => ({
    ...p,
    email: emailMap[p.id] || '—',
  }));

  return res.json(merged);
});

/* ── BRANCHES LIST (public) ──────────────────────────────────────── */
router.get('/branches', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('branches')
    .select('*')
    .eq('is_active', true)
    .order('name');

  if (error) return res.status(500).json({ error: error.message });
  return res.json(data);
});

/* ── CONTACT FORM SUBMIT (public — no auth) ──────────────────────── */
router.post('/contacts', async (req, res) => {
  const { full_name, email, phone, branch, message } = req.body;
  if (!full_name || !email || !message) {
    return res.status(400).json({ error: 'full_name, email, and message are required.' });
  }

  const { error } = await supabaseAdmin
    .from('contact_messages')
    .insert({ full_name, email, phone: phone || null, branch: branch || null, message });

  if (error) return res.status(500).json({ error: error.message });
  return res.status(201).json({ message: 'Message sent successfully.' });
});

export default router;
