// server.js — Angel's Pharmacy Express API
// import './src/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';

import authRoutes from './src/routes/auth.js';
import medicinesRoutes from './src/routes/medicines.js';
import ordersRoutes from './src/routes/orders.js';
import prescriptionsRoutes from './src/routes/prescriptions.js';
import adminRoutes from './src/routes/admin.js';

import path from 'node:path';
import { fileURLToPath } from 'node:url';

const app = express();
app.set('trust proxy', 1);
const PORT = process.env.PORT || 3000;
const HOSTNAME = 'localhost';

/* ── SECURITY MIDDLEWARE ─────────────────────────────────────────── */
app.use(helmet({
    contentSecurityPolicy: false
}));

// app.use((req, res, next) => {
//     // Capture the absolute hostname requested by the browser
//     const host = req.get('host');

//     if (host === 'angelspharmacy.local') {
//         // Perform an absolute HTTP redirection to another service entirely
//         return res.redirect(301, 'http://localhost:3000/angels-pharmacy-system');
//     }

//     next();
// });

app.listen(80, () => console.log('Proxy listener active on port 80'));

app.use(cors({
    origin: (origin, callback) => {
        if (!origin) return callback(null, true);
        const allowed = (process.env.ALLOWED_ORIGIN || '').split(',').map(o => o.trim());
        if (allowed.includes(origin)) return callback(null, true);
        if (process.env.NODE_ENV === 'development' &&
            (origin.includes('localhost') || origin.includes('127.0.0.1') || origin.includes('.local'))) {
            return callback(null, true);
        }
        callback(new Error('Not allowed by CORS'));
    },
    credentials: true,
}));

// Global rate limit — 200 requests per 15 minutes per IP
app.use(rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 200,
    message: { error: 'Too many requests. Please try again later.' },
}));

// Stricter limit on auth endpoints
app.use('/api/auth', rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 20,
    message: { error: 'Too many auth attempts. Please wait 15 minutes.' },
}));

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

/* ── ROUTES ──────────────────────────────────────────────────────── */
app.use('/api/auth', authRoutes);
app.use('/api/medicines', medicinesRoutes);
app.use('/api/orders', ordersRoutes);
app.use('/api/prescriptions', prescriptionsRoutes);
app.use('/api/admin', adminRoutes);

/* ── STATIC FILES ────────────────────────────────────────────────── */
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

app.use(express.static(path.join(__dirname, 'public')));

app.get('/', (_req, res, next) => {
    console.log(_req.path);
    if (_req.path.startsWith('/api')) return next();
    res.sendFile(path.join(__dirname, '/public/index.html'));
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
    console.log("Internal server error!");
    console.error(err);
    res.status(500).json({ error: 'Internal server error.' });
});

app.listen(PORT, () => {
    console.log(`Server running on path ${__dirname}`);
    console.log(`Angel's Pharmacy API running on http://${HOSTNAME}:${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV}`);
});
