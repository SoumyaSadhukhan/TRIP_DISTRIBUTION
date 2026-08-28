// server/server.js
const express = require('express');
const cors = require('cors');
require('dotenv').config();
const { getPool } = require('./db');
const authRoutes = require('./routes/authRoutes');
const tripRoutes = require('./routes/tripRoutes');
const friendsRoutes = require('./routes/friendsRoutes');
const notificationRoutes = require('./routes/notificationRoutes');

const app = express();
const PORT = process.env.PORT || 5000;

// Middlewares
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Request logger
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl}`);
  next();
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/trips', tripRoutes);
app.use('/api/friends', friendsRoutes);
app.use('/api/notifications', notificationRoutes);

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', database: 'SPLIT_BILL_DB', timestamp: new Date().toISOString() });
});

// Root welcome
app.get('/', (req, res) => {
  res.send('<h3>EquiTrip (SPLIT_BILL_DB) Collaboration API Server is running.</h3>');
});

// Start Server
async function startServer() {
  try {
    console.log('Connecting to SQL Server database SPLIT_BILL_DB...');
    await getPool();
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`====================================================`);
      console.log(`🚀 EquiTrip API Server is listening on http://localhost:${PORT}`);
      console.log(`🚀 Network / Emulator access: http://10.0.2.2:${PORT}`);
      console.log(`====================================================`);
    });
  } catch (err) {
    console.error('Failed to initialize database or start server:', err);
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`EquiTrip API Server started on port ${PORT} (Database pending connection).`);
    });
  }
}

startServer();
