#!/usr/bin/env bash
# Démo locale — entrypoint du conteneur backup.
#   1. attend que MinIO (le "S3" local) réponde ;
#   2. crée le bucket de sauvegardes s'il n'existe pas ;
#   3. installe la crontab (sauvegarde quotidienne à 02h00, comme en prod) ;
#   4. lance crond au premier plan.
set -euo pipefail

echo "⏳ Attente de MinIO (${S3_ENDPOINT})..."
until aws --endpoint-url "${S3_ENDPOINT}" s3 ls >/dev/null 2>&1; do
  sleep 2
done
echo "✅ MinIO est joignable."

if aws --endpoint-url "${S3_ENDPOINT}" s3 ls "s3://${S3_BUCKET}" >/dev/null 2>&1; then
  echo "🪣 Bucket s3://${S3_BUCKET} déjà présent."
else
  echo "🪣 Création du bucket s3://${S3_BUCKET}..."
  aws --endpoint-url "${S3_ENDPOINT}" s3 mb "s3://${S3_BUCKET}"
fi

# Même planification qu'en production (rôle Ansible backup : cron à 02h00).
# La sortie du job est redirigée vers les logs du conteneur (docker compose logs backup).
echo "0 2 * * * /usr/local/bin/backup >> /proc/1/fd/1 2>&1" | crontab -
echo "🕑 Cron installé : sauvegarde quotidienne à 02h00."
echo "💡 Sauvegarde manuelle   : docker compose exec backup backup"
echo "💡 Restauration manuelle : docker compose exec backup restore"

exec crond -f
