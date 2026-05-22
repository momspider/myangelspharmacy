// server.js — Angel's Pharmacy Express API
import 'dotenv/config';
import express     from 'express';
import cors        from 'cors';
import helmet      from 'helmet';
import rateLimit   from 'express-rate-limit';

import authRoutes          from './routes/auth.js';
import medicinesRoutes     from './routes/medicines.js';
import ordersRoutes        from './routes/orders.js';
import prescriptionsRoutes from './routes/prescriptions.js';
import adminRoutes         from './routes/admin.js';

import path from 'path';
import { fileURLToPath } from 'url';

const app  = express();
const PORT = process.env.PORT || 3000;

/* ── SECURITY MIDDLEWARE ─────────────────────────────────────────── */
app.use(helmet());

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true);
    const allowed = (process.env.ALLOWED_ORIGIN || '').split(',').map(o => o.trim());
    if (allowed.includes(origin)) return callback(null, true);
    if (process.env.NODE_ENV === 'development' &&
       (origin.includes('localhost') || origin.includes('127.0.0.1'))) {
      return callback(null, true);
    }
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
}));

// Global rate limit — 200 requests per 15 minutes per IP
app.use(rateLimit({
  windowMs: 15 * 60 * 1000,
  max:      200,
  message:  { error: 'Too many requests. Please try again later.' },
}));

// Stricter limit on auth endpoints
app.use('/api/auth', rateLimit({
  windowMs: 15 * 60 * 1000,
  max:      20,
  message:  { error: 'Too many auth attempts. Please wait 15 minutes.' },
}));

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

/* ── ROUTES ──────────────────────────────────────────────────────── */
app.use('/api/auth',          authRoutes);
app.use('/api/medicines',     medicinesRoutes);
app.use('/api/orders',        ordersRoutes);
app.use('/api/prescriptions', prescriptionsRoutes);
app.use('/api/admin',         adminRoutes);

/* ── STATIC FILES ────────────────────────────────────────────────── */
const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);

app.use(express.static(path.join(__dirname, '..')));

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, '..', 'index.html'));
});

/* ── HEALTH CHECK ────────────────────────────────────────────────── */
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', project: "Angel's Pharmacy", time: new Date().toISOString() });
});

/* ── 404 ─────────────────────────────────────────────────────────── */
app.use((_req, res) => {
  res.status(404).json({ error: 'Route not found.' });
});

/* ── ERROR HANDLER ───────────────────────────────────────────────── */
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal server error.' });
});

app.listen(PORT, () => {
  console.log(`Angel's Pharmacy API running on http://localhost:${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});
