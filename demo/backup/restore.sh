#!/usr/bin/env bash
# Démo locale — restauration PostgreSQL, miroir du script de prod (rôle Ansible
# backup, pg_restore.sh) : liste s3://$S3_BUCKET/postgres/, prend la sauvegarde
# la PLUS RÉCENTE, la télécharge, la déchiffre, gunzip puis rejoue le SQL.
set -euo pipefail

# Valeurs par défaut = environnement de la démo locale UNIQUEMENT (jamais de
# vrais secrets ici ; en prod tout vient d'Ansible Vault / IAM).
export PGHOST="${PGHOST:-db}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-shaka}"
export PGPASSWORD="${PGPASSWORD:-demo}" # démo locale uniquement
export PGDATABASE="${PGDATABASE:-shakasurf}"
export S3_ENDPOINT="${S3_ENDPOINT:-http://s3:9000}"
export S3_BUCKET="${S3_BUCKET:-shaka-surf-backups}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-demo}" # démo locale uniquement
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-demodemo123}" # démo locale uniquement
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-west-3}"
export BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-demo-passphrase}" # démo locale uniquement

echo "Recherche de la sauvegarde la plus récente dans s3://${S3_BUCKET}/postgres/..."

# Tri lexical = tri chronologique grâce à l'horodatage AAAA-MM-JJ_HHMMSS.
LATEST="$(aws --endpoint-url "${S3_ENDPOINT}" s3 ls "s3://${S3_BUCKET}/postgres/" \
  | sort | tail -n 1 | awk '{print $4}')"

if [[ -z "${LATEST}" ]]; then
  echo "Aucune sauvegarde trouvée dans s3://${S3_BUCKET}/postgres/." >&2
  echo "Lancez d'abord : docker compose exec backup backup" >&2
  exit 1
fi

LOCAL="/tmp/${LATEST}"
echo "Sauvegarde retenue : ${LATEST}"
aws --endpoint-url "${S3_ENDPOINT}" s3 cp "s3://${S3_BUCKET}/postgres/${LATEST}" "${LOCAL}"

echo "Déchiffrement puis restauration dans ${PGDATABASE}@${PGHOST}..."
openssl enc -d -aes-256-cbc -pbkdf2 -pass env:BACKUP_PASSPHRASE -in "${LOCAL}" \
  | gunzip \
  | psql --quiet -v ON_ERROR_STOP=1 "${PGDATABASE}"

rm -f "${LOCAL}"
echo "[$(date -Is)] Restauration de ${PGDATABASE} terminée depuis ${LATEST}."
