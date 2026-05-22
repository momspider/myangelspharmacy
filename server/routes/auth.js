// routes/auth.js
// POST /api/auth/signup  — create account
// POST /api/auth/login   — get session tokens
// POST /api/auth/logout  — invalidate session
// GET  /api/auth/me      — get current user + profile

import { Router } from 'express';
import { supabase, supabaseAdmin } from '../lib/supabase.js';
import { requireAuth } from '../lib/authMiddleware.js';

const router = Router();

/* ── SIGN UP ─────────────────────────────────────────────────────── */
router.post('/signup', async (req, res) => {
  const { full_name, email, phone, password } = req.body;

  if (!full_name || !email || !password) {
    return res.status(400).json({ error: 'full_name, email, and password are required.' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters.' });
  }

  const { data, error } = await supabase.auth.signUp({
    email: email.trim().toLowerCase(),
    password,
    options: {
      data: { full_name: full_name.trim(), phone: phone?.trim() || '' },
    },
  });

  if (error) return res.status(400).json({ error: error.message });

  // Profile row is created automatically by the DB trigger (handle_new_user)
  return res.status(201).json({
    message: 'Account created. Please check your email to confirm your address.',
    user: {
      id:    data.user.id,
      email: data.user.email,
    },
  });
});

/* ── LOG IN ──────────────────────────────────────────────────────── */
router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required.' });
  }

  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim().toLowerCase(),
    password,
  });

  if (error) return res.status(401).json({ error: error.message });

  // Fetch the profile so the frontend knows the user's role immediately
  const { data: profile } = await supabaseAdmin
    .from('profiles')
    .select('full_name, phone, role, branch_id')
    .eq('id', data.user.id)
    .single();

  return res.json({
    access_token:  data.session.access_token,
    refresh_token: data.session.refresh_token,
    user: {
      id:    data.user.id,
      email: data.user.email,
      ...profile,
    },
  });
});

/* ── REFRESH TOKEN ───────────────────────────────────────────────── */
router.post('/refresh', async (req, res) => {
  const { refresh_token } = req.body;
  if (!refresh_token) {
    return res.status(400).json({ error: 'refresh_token is required.' });
  }

  const { data, error } = await supabase.auth.refreshSession({ refresh_token });
  if (error) return res.status(401).json({ error: error.message });

  return res.json({
    access_token:  data.session.access_token,
    refresh_token: data.session.refresh_token,
  });
});

/* ── LOG OUT ─────────────────────────────────────────────────────── */
router.post('/logout', requireAuth, async (req, res) => {
  // Invalidate the token on Supabase's side
  await supabaseAdmin.auth.admin.signOut(req.accessToken);
  return res.json({ message: 'Logged out successfully.' });
});

/* ── ME (current user) ───────────────────────────────────────────── */
router.get('/me', requireAuth, async (req, res) => {
  const { data: profile } = await supabaseAdmin
    .from('profiles')
    .select('full_name, phone, role, branch_id')
    .eq('id', req.user.id)
    .single();

  return res.json({
    id:    req.user.id,
    email: req.user.email,
    ...profile,
  });
});

/* ── UPDATE PROFILE ──────────────────────────────────────────────── */
router.patch('/me', requireAuth, async (req, res) => {
  const { full_name, phone } = req.body;
  const updates = {};
  if (full_name) updates.full_name = full_name.trim();
  if (phone)     updates.phone     = phone.trim();

  const { error } = await supabaseAdmin
    .from('profiles')
    .update(updates)
    .eq('id', req.user.id);

  if (error) return res.status(400).json({ error: error.message });
  return res.json({ message: 'Profile updated.' });
});

export default router;
