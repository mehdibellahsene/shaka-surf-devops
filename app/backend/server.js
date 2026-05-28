// Backend Shaka Surf — plateforme de gestion pour ecoles de surf (projet DevOps EFREI).
// API minimaliste : Express + PostgreSQL (pg), rien d'autre.
// Toutes les variables d'environnement ont une valeur par defaut :
// l'application demarre sans aucun fichier .env.

const os = require('os');
const express = require('express');
const { Pool } = require('pg');

const PORT = parseInt(process.env.PORT || '9940', 10);
const INSTANCE_NAME = process.env.INSTANCE_NAME || os.hostname();

// Pool de connexions PostgreSQL. Le timeout court permet a /api/health
// de repondre rapidement meme quand la base est injoignable.
const pool = new Pool({
  host: process.env.DB_HOST || 'db',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME || 'shakasurf',
  user: process.env.DB_USER || 'shaka',
  password: process.env.DB_PASSWORD || 'shaka', // defaut du mock — en prod : .env template depuis Ansible Vault
  connectionTimeoutMillis: 2000,
});

// Indispensable : sans ce handler, la perte d'une connexion inactive
// (ex. redemarrage de PostgreSQL) ferait crasher le process Node.
pool.on('error', (err) => {
  console.error('[pool pg] connexion perdue :', err.message);
});

const app = express();
app.use(express.json());

// Erreur "metier" (donnee invalide, cours inexistant…) vs base injoignable.
function estErreurDonnees(err) {
  // Classes SQLSTATE 22 (donnee invalide) et 23 (violation de contrainte).
  return typeof err.code === 'string' && (err.code.startsWith('22') || err.code.startsWith('23'));
}

// Reponse 503 homogene quand la base de donnees ne repond pas.
function repondreDbInjoignable(res, err) {
  console.error('[db] erreur :', err.message);
  res.status(503).json({ error: 'base de donnees injoignable' });
}

// Identite de l'instance — sert a visualiser le round-robin du load balancer.
app.get('/api/whoami', (_req, res) => {
  res.json({ instance: INSTANCE_NAME });
});

// Sante de la chaine : teste la base avec un SELECT 1, sans jamais crasher.
app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', instance: INSTANCE_NAME, db: 'up' });
  } catch {
    res.json({ status: 'degraded', instance: INSTANCE_NAME, db: 'down' });
  }
});

// Tableau de bord : metriques calculees en direct depuis PostgreSQL.
app.get('/api/dashboard', async (_req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT
         (SELECT COALESCE(SUM(l.price_eur), 0)
            FROM enrollments e JOIN lessons l ON l.id = e.lesson_id) AS revenue_eur,
         (SELECT COUNT(*) FROM enrollments)                          AS students,
         (SELECT COUNT(*) FROM lessons)                              AS lessons,
         (SELECT COALESCE(SUM(capacity), 0) FROM lessons)            AS capacity_total`
    );
    const d = rows[0];
    const capacity = parseInt(d.capacity_total, 10) || 0;
    const students = parseInt(d.students, 10) || 0;
    res.json({
      revenue_eur: parseInt(d.revenue_eur, 10),
      students,
      lessons: parseInt(d.lessons, 10),
      fill_rate: capacity ? Math.round((students / capacity) * 100) : 0,
    });
  } catch (err) {
    repondreDbInjoignable(res, err);
  }
});

// Planning : cours proposes par l'ecole (donnees chargees par db/init.sql).
app.get('/api/lessons', async (_req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, title, level, instructor, price_eur, capacity FROM lessons ORDER BY id'
    );
    res.json(rows);
  } catch (err) {
    repondreDbInjoignable(res, err);
  }
});

// Inscriptions, avec le titre du cours joint pour l'affichage.
app.get('/api/enrollments', async (_req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT e.id,
              e.student,
              to_char(e.scheduled_for, 'YYYY-MM-DD') AS scheduled_for,
              e.created_at,
              l.title       AS lesson_title,
              l.instructor  AS lesson_instructor
         FROM enrollments e
         LEFT JOIN lessons l ON l.id = e.lesson_id
        ORDER BY e.created_at DESC
        LIMIT 50`
    );
    res.json(rows);
  } catch (err) {
    repondreDbInjoignable(res, err);
  }
});

// Creation d'une inscription : { student, lesson_id, scheduled_for }.
app.post('/api/enrollments', async (req, res) => {
  const { student, lesson_id, scheduled_for } = req.body || {};
  if (!student || !lesson_id) {
    return res.status(400).json({ error: 'champs requis : student, lesson_id' });
  }
  try {
    const { rows } = await pool.query(
      `INSERT INTO enrollments (student, lesson_id, scheduled_for)
       VALUES ($1, $2, $3)
       RETURNING id, student, lesson_id, to_char(scheduled_for, 'YYYY-MM-DD') AS scheduled_for`,
      [student, lesson_id, scheduled_for || null]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    if (estErreurDonnees(err)) {
      return res.status(400).json({ error: 'donnees invalides (cours inconnu ou date incorrecte)' });
    }
    repondreDbInjoignable(res, err);
  }
});

app.listen(PORT, () => {
  console.log(`Backend Shaka Surf — instance ${INSTANCE_NAME} — port ${PORT}`);
});
