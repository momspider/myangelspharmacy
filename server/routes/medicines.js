// routes/medicines.js
// GET  /api/medicines          — list all active medicines (public)
// GET  /api/medicines/:id      — single medicine detail (public)
// POST /api/medicines          — create medicine (admin only)
// PUT  /api/medicines/:id      — update medicine (admin only)
// DEL  /api/medicines/:id      — deactivate medicine (admin only)

import { Router } from 'express';
import { supabaseAdmin } from '../lib/supabase.js';
import { requireAdmin } from '../lib/authMiddleware.js';

const router = Router();

/* ── LIST ────────────────────────────────────────────────────────── */
router.get('/', async (req, res) => {
  const { search, category, requires_rx, same_day } = req.query;

  let query = supabaseAdmin
    .from('medicines')
    .select('*')
    .eq('is_active', true)
    .order('name');

  if (search)      query = query.ilike('name', `%${search}%`);
  if (category)    query = query.eq('category', category);
  if (requires_rx !== undefined) query = query.eq('requires_rx', requires_rx === 'true');
  if (same_day    !== undefined) query = query.eq('same_day_available', same_day === 'true');

  const { data, error } = await query;
  if (error) {
  console.error('Medicines error:', error);
  return res.status(500).json({ error: error.message });
}
  return res.json(data);
});

/* ── SINGLE ──────────────────────────────────────────────────────── */
router.get('/:id', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('medicines')
    .select('*')
    .eq('medicine_id', req.params.id)
    .eq('is_active', true)
    .single();

  if (error) return res.status(404).json({ error: 'Medicine not found.' });
  return res.json(data);
});

/* ── CREATE (admin) ──────────────────────────────────────────────── */
router.post('/', requireAdmin, async (req, res) => {
  const { name, sku, unit_price, category, requires_rx,
          same_day_available, supplier_verified, image_url } = req.body;

  if (!name || unit_price === undefined) {
    return res.status(400).json({ error: 'name and unit_price are required.' });
  }

  const { data, error } = await supabaseAdmin
    .from('medicines')
    .insert({ name, sku, unit_price, category, requires_rx,
              same_day_available, supplier_verified, image_url })
    .select()
    .single();

  if (error) return res.status(400).json({ error: error.message });
  return res.status(201).json(data);
});

/* ── UPDATE (admin) ──────────────────────────────────────────────── */
router.put('/:id', requireAdmin, async (req, res) => {
  const allowed = ['name','sku','unit_price','category','requires_rx',
                   'same_day_available','supplier_verified','image_url','is_active'];
  const updates = Object.fromEntries(
    Object.entries(req.body).filter(([k]) => allowed.includes(k))
  );

  const { data, error } = await supabaseAdmin
    .from('medicines')
    .update(updates)
    .eq('medicine_id', req.params.id)
    .select()
    .single();

  if (error) return res.status(400).json({ error: error.message });
  return res.json(data);
});

/* ── DEACTIVATE (admin) ──────────────────────────────────────────── */
router.delete('/:id', requireAdmin, async (req, res) => {
  const { error } = await supabaseAdmin
    .from('medicines')
    .update({ is_active: false })
    .eq('medicine_id', req.params.id);

  if (error) return res.status(400).json({ error: error.message });
  return res.json({ message: 'Medicine deactivated.' });
});

export default router;
