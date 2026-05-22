// lib/authMiddleware.js
// Verifies the Supabase JWT sent by the frontend in the Authorization header.
// Attaches req.user and req.supabaseClient to the request for downstream use.

import { supabase, supabaseAdmin } from './supabase.js';

export async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header.' });
  }

  const token = authHeader.split(' ')[1];

  // Verify the token against Supabase Auth
  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) {
    return res.status(401).json({ error: 'Invalid or expired session. Please log in again.' });
  }

  // Fetch the user's profile (role, branch, etc.)
  const { data: profile, error: profileError } = await supabaseAdmin
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single();

    console.log('profile:', profile, 'error:', profileError);

  req.user          = user;
  req.profile       = profile || {};
  req.accessToken   = token;
  next();
}

export async function requireAdmin(req, res, next) {
  await requireAuth(req, res, async () => {
    if (req.profile?.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required.' });
    }
    next();
  });
}

export async function requireStaff(req, res, next) {
  await requireAuth(req, res, async () => {
    if (!['admin', 'pharmacist'].includes(req.profile?.role)) {
      return res.status(403).json({ error: 'Staff access required.' });
    }
    next();
  });
}
