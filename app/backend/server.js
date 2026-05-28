// Backend mock Shaka Surf — projet DevOps EFREI.
// API minimaliste : Express + PostgreSQL (pg), rien d'autre.
// Toutes les variables d'environnement ont une valeur par défaut :
// l'application démarre sans aucun fichier .env.

const os = require('os');
const express = require('express');
const { Pool } = require('pg');

const PORT = parseInt(process.env.PORT || '9940', 10);
const INSTANCE_NAME = process.env.INSTANCE_NAME || os.hostname();

// Pool de connexions PostgreSQL. Le timeout court permet à /api/health
// de répondre rapidement même quand la base est injoignable.
const pool = new Pool({
  host: process.env.DB_HOST || 'db',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME || 'shakasurf',
  user: process.env.DB_USER || 'shaka',
  password: process.env.DB_PASSWORD || 'shaka', // défaut du mock — en prod : .env templaté depuis Ansible Vault
  connectionTimeoutMillis: 2000,
});

// Indispensable : sans ce handler, la perte d'une connexion inactive
// (ex. redémarrage de PostgreSQL) ferait crasher le process Node.
pool.on('error', (err) => {
  console.error('[pool pg] connexion perdue :', err.message);
});

const app = express();
app.use(express.json());

// Erreur "métier" (donnée invalide, spot inexistant…) vs base injoignable.
function estErreurDonnees(err) {
  // Classes SQLSTATE 22 (donnée invalide) et 23 (violation de contrainte).
  return typeof err.code === 'string' && (err.code.startsWith('22') || err.code.startsWith('23'));
}

// Réponse 503 homogène quand la base de données ne répond pas.
function repondreDbInjoignable(res, err) {
  console.error('[db] erreur :', err.message);
  res.status(503).json({ error: 'base de données injoignable' });
}

// Identité de l'instance — sert à visualiser le round-robin du load balancer.
app.get('/api/whoami', (_req, res) => {
  res.json({ instance: INSTANCE_NAME });
});

// Santé de la chaîne : teste la base avec un SELECT 1, sans jamais crasher.
app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', instance: INSTANCE_NAME, db: 'up' });
  } catch {
    res.json({ status: 'degraded', instance: INSTANCE_NAME, db: 'down' });
  }
});

// Liste des spots de surf (données chargées par db/init.sql).
app.get('/api/spots', async (_req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, name, level, wave_height, emoji FROM spots ORDER BY id'
    );
    res.json(rows);
  } catch (err) {
    repondreDbInjoignable(res, err);
  }
});

// Liste des réservations, avec le nom du spot joint pour l'affichage.
app.get('/api/bookings', async (_req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT b.id,
              b.name,
              to_char(b.booked_for, 'YYYY-MM-DD') AS booked_for,
              b.created_at,
              s.name  AS spot_name,
              s.emoji AS spot_emoji
         FROM bookings b
         LEFT JOIN spots s ON s.id = b.spot_id
        ORDER BY b.created_at DESC
        LIMIT 50`
    );
    res.json(rows);
  } catch (err) {
    repondreDbInjoignable(res, err);
  }
});

// Création d'une réservation : { name, spot_id, booked_for }.
app.post('/api/bookings', async (req, res) => {
  const { name, spot_id, booked_for } = req.body || {};
  if (!name || !spot_id) {
    return res.status(400).json({ error: 'champs requis : name, spot_id' });
  }
  try {
    const { rows } = await pool.query(
      `INSERT INTO bookings (name, spot_id, booked_for)
       VALUES ($1, $2, $3)
       RETURNING id, name, spot_id, to_char(booked_for, 'YYYY-MM-DD') AS booked_for`,
      [name, spot_id, booked_for || null]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    if (estErreurDonnees(err)) {
      return res.status(400).json({ error: 'données invalides (spot inconnu ou date incorrecte)' });
    }
    repondreDbInjoignable(res, err);
  }
});

app.listen(PORT, () => {
  console.log(`Backend Shaka Surf (mock) — instance ${INSTANCE_NAME} — port ${PORT}`);
});
