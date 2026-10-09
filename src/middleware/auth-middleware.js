// src/auth-middleware.js
// Verifies the Supabase JWT sent by the frontend in the Authorization header.
// Attaches req.user and req.supabaseClient to the request for downstream use.

import { supabaseAdmin } from '../config/supabase.js';

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
        .from('Profiles')
        .select('*, role')
        .eq('id', user.id)
        .single();

    if (profileError) {
        console.error('Authentication profile lookup failed:', profileError);
        return res.status(500).json({ error: 'Unable to load your profile.' });
    }

    req.user = user;
    req.profile = {
        ...profile,
        role: profile.role || 'customer',
    };
    req.accessToken = token;
    next();
}

export async function requireAdmin(req, res, next) {
    await requireAuth(req, res, async () => {
        if (req.profile?.role !== 'administrator') {
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
