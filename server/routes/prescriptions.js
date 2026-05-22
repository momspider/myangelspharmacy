// routes/prescriptions.js
// POST /api/prescriptions         — upload prescription file (auth required)
// GET  /api/prescriptions         — get my prescriptions (auth required)
// GET  /api/prescriptions/pending — all pending (staff only)
// PATCH /api/prescriptions/:id    — verify or reject (staff only)

import { Router } from 'express';
import multer from 'multer';
import { supabaseAdmin } from '../lib/supabase.js';
import { requireAuth, requireStaff } from '../lib/authMiddleware.js';

const router  = Router();
// Store file in memory so we can upload to Supabase Storage
const upload  = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

/* ── UPLOAD PRESCRIPTION ─────────────────────────────────────────── */
router.post('/', requireAuth, upload.single('prescription'), async (req, res) => {
  const file = req.file;
  if (!file) return res.status(400).json({ error: 'No file uploaded.' });

  const { branch_id } = req.body;
  if (!branch_id) return res.status(400).json({ error: 'branch_id is required.' });

  const allowed = ['image/jpeg','image/png','image/webp','application/pdf'];
  if (!allowed.includes(file.mimetype)) {
    return res.status(400).json({ error: 'Only JPG, PNG, WEBP, and PDF files are allowed.' });
  }

  // Upload to Supabase Storage: prescriptions/{user_id}/{timestamp}-{filename}
  const storagePath = `${req.user.id}/${Date.now()}-${file.originalname}`;
  const { error: uploadErr } = await supabaseAdmin.storage
    .from('prescriptions')
    .upload(storagePath, file.buffer, {
      contentType: file.mimetype,
      upsert: false,
    });

  if (uploadErr) return res.status(500).json({ error: uploadErr.message });

  // Save prescription record
  const { data, error } = await supabaseAdmin
    .from('prescriptions')
    .insert({
      user_id:   req.user.id,
      branch_id,
      file_path: storagePath,
      file_name: file.originalname,
      status:    'pending',
      // ocr_result will be added later when OCR service is integrated
    })
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });

  return res.status(201).json({
    message: 'Prescription uploaded successfully. A pharmacist will review it shortly.',
    prescription_id: data.prescription_id,
    status: 'pending',
  });
});

/* ── GET MY PRESCRIPTIONS ────────────────────────────────────────── */
router.get('/', requireAuth, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('prescriptions')
    .select('prescription_id, file_name, status, uploaded_at, reviewed_at, rejection_reason, branches(name)')
    .eq('user_id', req.user.id)
    .order('uploaded_at', { ascending: false });

  if (error) return res.status(500).json({ error: error.message });
  return res.json(data);
});

/* ── GET PENDING PRESCRIPTIONS (staff) ───────────────────────────── */
router.get('/pending', requireStaff, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('prescriptions')
    .select(`
      prescription_id, file_name, file_path, status, uploaded_at, user_id,
      branches ( name )
    `)
    .eq('status', 'pending')
    .order('uploaded_at', { ascending: true });  // oldest first

  if (error) return res.status(500).json({ error: error.message });
  return res.json(data);
});

/* ── GET SIGNED URL (staff — to view the file) ───────────────────── */
router.get('/:id/file', requireStaff, async (req, res) => {
  const { data: presc, error: prescErr } = await supabaseAdmin
    .from('prescriptions')
    .select('file_path')
    .eq('prescription_id', req.params.id)
    .single();

  if (prescErr) return res.status(404).json({ error: 'Prescription not found.' });

  const { data, error } = await supabaseAdmin.storage
    .from('prescriptions')
    .createSignedUrl(presc.file_path, 60 * 10); // 10-minute signed URL

  if (error) return res.status(500).json({ error: error.message });
  return res.json({ url: data.signedUrl });
});

/* ── VERIFY OR REJECT (staff) ────────────────────────────────────── */
router.patch('/:id', requireStaff, async (req, res) => {
  const { status, rejection_reason } = req.body;

  if (!['verified','rejected'].includes(status)) {
    return res.status(400).json({ error: 'Status must be "verified" or "rejected".' });
  }
  if (status === 'rejected' && !rejection_reason) {
    return res.status(400).json({ error: 'rejection_reason is required when rejecting.' });
  }

  const { data, error } = await supabaseAdmin
    .from('prescriptions')
    .update({
      status,
      rejection_reason: rejection_reason || null,
      reviewed_by:      req.user.id,
      reviewed_at:      new Date().toISOString(),
    })
    .eq('prescription_id', req.params.id)
    .select()
    .single();

  if (error) return res.status(400).json({ error: error.message });
  return res.json({ message: `Prescription ${status}.`, prescription: data });
});

export default router;
