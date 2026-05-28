# Mock applicatif Shaka Surf

Application **factice** qui remplace la vraie application Shaka Surf pour le
projet DevOps EFREI. Son seul but est de **rendre visible la chaîne de
déploiement** : load balancer -> VMs applicatives -> PostgreSQL -> backups S3
(badge d'instance, visualiseur de round-robin, panneau de santé, mode dégradé
quand la base est down). Les vraies fonctionnalités métier sont hors périmètre.

## Contenu

| Dossier / fichier | Rôle |
|----------------------|------|
| `backend/` | API Node 20 (Express + pg), port 9940 — `/api/whoami`, `/api/health`, `/api/spots`, `/api/bookings` |
| `frontend/` | Front statique (vanilla JS) servi par nginx:alpine, proxy `/api/` vers le backend |
| `db/init.sql` | Schéma + seed (6 spots), **idempotent** |
| `docker-compose.yml` | Compose d'**une** VM applicative (`web` + `api`, **sans** service `db`) |

Toutes les variables d'environnement du backend ont une valeur par défaut :
l'application démarre sans `.env`.

## Déploiement

- **Production simulée (Ansible)** : le rôle `app` copie ce dossier sur chaque
  VM applicative, templatise un `.env` (`DB_HOST`, mot de passe issu du vault,
  `INSTANCE_NAME`…) puis lance `docker compose up --build`. PostgreSQL est sur
  une VM dédiée — d'où l'absence de service `db` dans le compose de ce dossier.
  Le schéma `db/init.sql` est appliqué par le rôle `database`.
- **Démo locale** : le `docker-compose.yml` à la **racine du dépôt** réutilise
  `frontend/` et `backend/` pour simuler toute l'architecture (lb, app1/app2,
  db, MinIO, backup) sur un seul poste.
