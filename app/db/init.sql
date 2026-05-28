-- Schema et donnees de demo de Shaka Surf, la plateforme de gestion pour
-- ecoles de surf (projet DevOps EFREI).
-- Script IDEMPOTENT : rejouable sans erreur (CREATE TABLE IF NOT EXISTS,
-- INSERT ... ON CONFLICT DO NOTHING).

-- Cours proposes par l'ecole (le planning du moniteur).
CREATE TABLE IF NOT EXISTS lessons (
    id         int PRIMARY KEY,
    title      text NOT NULL,
    level      text,
    instructor text,
    price_eur  int,
    capacity   int
);

-- Inscriptions d'eleves sur un cours (genere le chiffre d'affaires).
CREATE TABLE IF NOT EXISTS enrollments (
    id            serial PRIMARY KEY,
    student       text NOT NULL,
    lesson_id     int REFERENCES lessons(id),
    scheduled_for date,
    created_at    timestamptz DEFAULT now()
);

-- Catalogue de cours, ids fixes pour garantir l'idempotence.
INSERT INTO lessons (id, title, level, instructor, price_eur, capacity) VALUES
    (1, 'Initiation - cours collectif', 'Debutant',      'Lea Moreau',    45,  8),
    (2, 'Perfectionnement vague',       'Intermediaire', 'Tom Riviere',   60,  6),
    (3, 'Coaching competition',         'Confirme',      'Noa Castera',   90,  4),
    (4, 'Cours enfants - ecume',        'Debutant',      'Maya Dubois',   35, 10),
    (5, 'Stage week-end',               'Intermediaire', 'Hugo Lefevre', 150, 12),
    (6, 'Cours prive',                  'Tous niveaux',  'Ines Bonnet',   80,  1)
ON CONFLICT (id) DO NOTHING;

-- Inscriptions de demo, ids fixes : alimentent le tableau de bord des
-- l'ouverture (chiffre d'affaires, eleves, taux de remplissage).
INSERT INTO enrollments (id, student, lesson_id, scheduled_for) VALUES
    (1,  'Kelly Slater',    1, '2026-06-02'),
    (2,  'Justine Dupont',  5, '2026-06-06'),
    (3,  'Jeremy Flores',   3, '2026-06-07'),
    (4,  'Pauline Ado',     2, '2026-06-09'),
    (5,  'Joan Duru',       5, '2026-06-13'),
    (6,  'Maxime Huscenot', 2, '2026-06-14'),
    (7,  'Tessa Thyssen',   4, '2026-06-16'),
    (8,  'Marco Mignot',    1, '2026-06-18'),
    (9,  'Vahine Fierro',   3, '2026-06-20'),
    (10, 'Michel Bourez',   6, '2026-06-21')
ON CONFLICT (id) DO NOTHING;

-- La sequence du serial doit suivre les ids inseres manuellement.
SELECT setval(pg_get_serial_sequence('enrollments', 'id'),
              (SELECT COALESCE(MAX(id), 1) FROM enrollments));
