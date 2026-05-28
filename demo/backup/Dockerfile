# Démo locale — conteneur de sauvegarde (équivalent du cron pg_dump installé
# par le rôle Ansible "backup" sur la VM base de données).
# Base postgres:15-alpine pour disposer de pg_dump/psql en version 15,
# alignée avec le serveur PostgreSQL de la démo.
FROM postgres:15-alpine

# aws-cli : envoi vers MinIO (API S3) · openssl : chiffrement · bash : scripts
RUN apk add --no-cache aws-cli openssl bash

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Les scripts sont installés sous les noms courts "backup" et "restore" :
#   docker compose exec backup backup
#   docker compose exec backup restore
COPY backup.sh /usr/local/bin/backup
COPY restore.sh /usr/local/bin/restore
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/backup /usr/local/bin/restore

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
