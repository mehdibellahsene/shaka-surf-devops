#!/usr/bin/env bash
# Démo locale — sauvegarde PostgreSQL, miroir du script de prod (rôle Ansible
# backup, pg_backup.sh) : pg_dump -> gzip -> chiffrement AES-256 -> S3 (MinIO).
set -euo pipefail

# Valeurs par défaut = environnement de la démo locale UNIQUEMENT (jamais de
# vrais secrets ici ; en prod tout vient d'Ansible Vault / IAM).
export PGHOST="${PGHOST:-db}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-shaka}"
export PGPASSWORD="${PGPASSWORD:-demo}"                              # démo locale uniquement
export PGDATABASE="${PGDATABASE:-shakasurf}"
export S3_ENDPOINT="${S3_ENDPOINT:-http://s3:9000}"
export S3_BUCKET="${S3_BUCKET:-shaka-surf-backups}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-demo}"                # démo locale uniquement
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-demodemo123}" # démo locale uniquement
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-west-3}"
export BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-demo-passphrase}"     # démo locale uniquement

TS="$(date +%Y-%m-%d_%H%M%S)"
FILE="/tmp/${TS}.sql.gz.enc"
DEST="s3://${S3_BUCKET}/postgres/${TS}.sql.gz.enc"

echo "🌊 Sauvegarde de ${PGDATABASE}@${PGHOST}..."

# --clean --if-exists : le dump droppe puis recrée les objets, ce qui rend la
# restauration rejouable sur une base déjà peuplée (parfait pour la démo).
pg_dump --clean --if-exists "${PGDATABASE}" \
  | gzip \
  | openssl enc -aes-256-cbc -salt -pbkdf2 -pass env:BACKUP_PASSPHRASE -out "${FILE}"

echo "📤 Envoi vers ${DEST}..."
aws --endpoint-url "${S3_ENDPOINT}" s3 cp "${FILE}" "${DEST}"

# Purge locale immédiate : la rétention vit côté S3, comme en prod (lifecycle).
rm -f "${FILE}"

echo "✅ [$(date -Is)] Sauvegarde envoyée : ${DEST}"
echo "   À voir dans la console MinIO : http://localhost:9001 (demo / demodemo123)"
