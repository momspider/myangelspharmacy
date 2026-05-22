// routes/orders.js
// POST /api/orders              — place a new order (auth required)
// GET  /api/orders              — get current user's orders (auth required)
// GET  /api/orders/:id          — single order detail (auth required)
// PATCH /api/orders/:id/status  — update order status (staff only)

import { Router } from 'express';
import { supabaseAdmin } from '../lib/supabase.js';
import { requireAuth, requireStaff } from '../lib/authMiddleware.js';

const router = Router();

/* ── PLACE ORDER ─────────────────────────────────────────────────── */
router.post('/', requireAuth, async (req, res) => {
  const { branch_id, items, prescription_id, notes } = req.body;
  // items: [{ medicine_id, quantity }]

  if (!branch_id || !items || items.length === 0) {
    return res.status(400).json({ error: 'branch_id and items are required.' });
  }

  // Fetch medicine prices from DB (never trust client-sent prices)
  const medicineIds = items.map(i => i.medicine_id);
  const { data: medicines, error: medErr } = await supabaseAdmin
    .from('medicines')
    .select('medicine_id, unit_price, requires_rx, is_active')
    .in('medicine_id', medicineIds);

  if (medErr) return res.status(500).json({ error: medErr.message });

  // Validate all medicines exist and are active
  for (const item of items) {
    const med = medicines.find(m => m.medicine_id === item.medicine_id);
    if (!med || !med.is_active) {
      return res.status(400).json({ error: `Medicine ${item.medicine_id} is unavailable.` });
    }
    // If any item requires Rx, a prescription must be provided
    if (med.requires_rx && !prescription_id) {
      return res.status(400).json({
        error: `${med.name || item.medicine_id} requires a verified prescription.`
      });
    }
  }

  // Calculate total
  const total_amount = items.reduce((sum, item) => {
    const med = medicines.find(m => m.medicine_id === item.medicine_id);
    return sum + (med.unit_price * item.quantity);
  }, 0);

  // Create the order
  const { data: order, error: orderErr } = await supabaseAdmin
    .from('orders')
    .insert({
      user_id: req.user.id,
      branch_id,
      total_amount,
      prescription_id: prescription_id || null,
      notes: notes || null,
      status: 'pending',
    })
    .select()
    .single();

  if (orderErr) return res.status(500).json({ error: orderErr.message });

  // Insert order items
  const orderItems = items.map(item => {
    const med = medicines.find(m => m.medicine_id === item.medicine_id);
    return {
      order_id:   order.order_id,
      medicine_id: item.medicine_id,
      quantity:   item.quantity,
      unit_price: med.unit_price,
    };
  });

  const { error: itemsErr } = await supabaseAdmin.from('order_items').insert(orderItems);
  if (itemsErr) return res.status(500).json({ error: itemsErr.message });

  return res.status(201).json({
    message: 'Order placed successfully.',
    order_id: order.order_id,
    total_amount,
    status: 'pending',
  });
});

/* ── GET MY ORDERS ───────────────────────────────────────────────── */
router.get('/', requireAuth, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('orders')
    .select(`
      order_id, status, total_amount, placed_at, ready_at, completed_at, notes,
      branches ( name ),
      order_items (
        quantity, unit_price, subtotal,
        medicines ( name, image_url )
      )
    `)
    .eq('user_id', req.user.id)
    .order('placed_at', { ascending: false });

  if (error) return res.status(500).json({ error: error.message });
  return res.json(data);
});

/* ── GET SINGLE ORDER ────────────────────────────────────────────── */
router.get('/:id', requireAuth, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('orders')
    .select(`
      *, branches ( name ),
      order_items ( *, medicines ( name, image_url, requires_rx ) ),
      prescriptions ( status, file_path )
    `)
    .eq('order_id', req.params.id)
    .eq('user_id', req.user.id)   // customers can only see their own
    .single();

  if (error) return res.status(404).json({ error: 'Order not found.' });
  return res.json(data);
});

/* ── UPDATE ORDER STATUS (staff) ─────────────────────────────────── */
router.patch('/:id/status', requireStaff, async (req, res) => {
  const { status } = req.body;
  const validStatuses = ['pending','confirmed','ready','completed','cancelled'];

  if (!validStatuses.includes(status)) {
    return res.status(400).json({ error: `Status must be one of: ${validStatuses.join(', ')}` });
  }

  const updates = { status };
  if (status === 'ready')     updates.ready_at     = new Date().toISOString();
  if (status === 'completed') updates.completed_at = new Date().toISOString();

  const { data, error } = await supabaseAdmin
    .from('orders')
    .update(updates)
    .eq('order_id', req.params.id)
    .select()
    .single();

  if (error) return res.status(400).json({ error: error.message });

  // If completed, log the sale
  if (status === 'completed') {
    const { data: items } = await supabaseAdmin
      .from('order_items')
      .select('medicine_id, quantity, unit_price')
      .eq('order_id', req.params.id);

    if (items) {
      const salesRows = items.map(item => ({
        order_id:    req.params.id,
        branch_id:   data.branch_id,
        medicine_id: item.medicine_id,
        quantity:    item.quantity,
        unit_price:  item.unit_price,
      }));
      await supabaseAdmin.from('sales').insert(salesRows);
    }
  }

  return res.json({ message: `Order status updated to "${status}".`, order: data });
});

/* ── GET ALL ORDERS (staff) ──────────────────────────────────────── */
router.get('/admin/all', requireStaff, async (req, res) => {
  const { status, branch_id } = req.query;

  let query = supabaseAdmin
    .from('orders')
    .select(`
      order_id, status, total_amount, placed_at, ready_at, user_id,
      branches ( name ),
      order_items ( quantity, medicines ( name ) )
    `)
    .order('placed_at', { ascending: false });

  if (status)    query = query.eq('status', status);
  if (branch_id) query = query.eq('branch_id', branch_id);

  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  return res.json(data);
});

export default router;
