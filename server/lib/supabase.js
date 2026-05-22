// lib/supabase.js
// Two Supabase clients:
//   supabase      — uses publishable key, respects RLS (for user-context calls)
//   supabaseAdmin — uses secret key, bypasses RLS (for server-side admin ops)

import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

const SUPABASE_URL         = process.env.SUPABASE_URL;
const SUPABASE_PUBLISHABLE = process.env.SUPABASE_PUBLISHABLE_KEY;
const SUPABASE_SECRET      = process.env.SUPABASE_SECRET_KEY;

if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE || !SUPABASE_SECRET) {
  throw new Error('Missing Supabase environment variables. Check your .env file.');
}

// Public client — used when acting on behalf of a logged-in user.
// Pass the user's JWT via supabase.auth.setSession() before querying.
export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE, {
  auth: { persistSession: false },
});

// Admin client — bypasses RLS. Use ONLY on the server, never expose to frontend.
export const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SECRET, {
  auth: { persistSession: false, autoRefreshToken: false },
});
