// server.js — Angel's Pharmacy Express API
// import './src/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';

import path from 'node:path';
import { fileURLToPath } from 'node:url';

/* -- SERVER CONFIGURATION -------------------------------------------------- */
const app = express();
app.set('trust proxy', 1);
const PORT = process.env.PORT || 3000;
const HOSTNAME = 'localhost';

/* -- SECURITY MIDDLEWARE --------------------------------------------------- */
// app.use(helmet({
//     contentSecurityPolicy: false
// }));

// const allowedOrigins = (process.env.ALLOWED_ORIGIN || '')
//     .split(',')
//     .map((origin) => origin.trim())
//     .filter(Boolean);

// app.use(cors({
//     origin: (origin, callback) => {
//         if (!origin) return callback(null, true);

//         const isLocalDevOrigin = process.env.NODE_ENV === 'development' &&
//             (origin.includes('localhost') || origin.includes('127.0.0.1') || origin.includes('.local'));

//         if (isLocalDevOrigin || allowedOrigins.includes(origin)) {
//             return callback(null, true);
//         }

//         console.log(`Blocked CORS origin: ${origin}`);
//         return callback(null, false);
//     },
//     credentials: true,
// }));

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
// app.use(express.urlencoded({ extended: true }));

/* -- ROUTES ---------------------------------------------------------------- */
import authRoutes from './src/routes/auth.js';
import medicinesRoutes from './src/routes/medicines.js';
import ordersRoutes from './src/routes/orders.js';
import prescriptionsRoutes from './src/routes/prescriptions.js';
import adminRoutes from './src/routes/admin.js';

app.use('/api/auth', authRoutes);
app.use('/api/medicines', medicinesRoutes);
app.use('/api/orders', ordersRoutes);
app.use('/api/prescriptions', prescriptionsRoutes);
app.use('/api/admin', adminRoutes);

/* -- STATIC FILES ---------------------------------------------------------- */
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

app.use(express.static(path.join(__dirname, 'public')));

app.get('/', (req, res, next) => {
    if (req.path.startsWith('/api')) return next();
    res.sendFile(path.join(__dirname, '/public/index.html'));
});

/* -- HEALTH CHECK ---------------------------------------------------------- */
app.get('/api/health', (req, res) => {
    res.json({
        status: 'ok',
        project: "Angel's Pharmacy",
        time: new Date().toISOString()
    });
});

/* -- 404 ------------------------------------------------------------------- */
app.use((req, res) => {
    res.status(404).json({ error: 'Route not found.' });
});

/* -- ERROR HANDLER --------------------------------------------------------- */
app.use((err, req, res, next) => {
    console.log("Internal server error!");
    console.error(err);
    res.status(500).json({ error: 'Internal server error.' });
});

app.listen(PORT, () => {
    console.log(`Server running on path ${__dirname}`);
    console.log(`Angel's Pharmacy API running on http://${HOSTNAME}:${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV}`);
});
