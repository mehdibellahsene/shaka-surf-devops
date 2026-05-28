-- Schéma et données de démo du mock Shaka Surf (projet DevOps EFREI).
-- Script IDEMPOTENT : rejouable autant de fois que nécessaire sans erreur
-- (CREATE TABLE IF NOT EXISTS, INSERT ... ON CONFLICT DO NOTHING).

CREATE TABLE IF NOT EXISTS spots (
    id          int PRIMARY KEY,
    name        text,
    level       text,
    wave_height text,
    emoji       text
);

CREATE TABLE IF NOT EXISTS bookings (
    id         serial PRIMARY KEY,
    name       text NOT NULL,
    spot_id    int REFERENCES spots(id),
    booked_for date,
    created_at timestamptz DEFAULT now()
);

-- Jeu de données : 6 spots, ids fixes pour garantir l'idempotence.
INSERT INTO spots (id, name, level, wave_height, emoji) VALUES
    (1, 'Hossegor',                    'Confirmé',      '1,5 - 3 m',   '🏆'),
    (2, 'Biarritz - Côte des Basques', 'Débutant',      '0,5 - 1 m',   '🏄'),
    (3, 'Lacanau',                     'Intermédiaire', '1 - 2 m',     '☀️'),
    (4, 'La Torche',                   'Intermédiaire', '1 - 2,5 m',   '🌬️'),
    (5, 'Anglet',                      'Débutant',      '0,5 - 1,5 m', '🐚'),
    (6, 'Nazaré',                      'Légende',       '10 - 30 m',   '🌊')
ON CONFLICT (id) DO NOTHING;
