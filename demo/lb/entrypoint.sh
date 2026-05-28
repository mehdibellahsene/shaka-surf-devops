#!/usr/bin/env bash
# Démo locale — entrypoint du load balancer.
# Génère un certificat TLS auto-signé (CN=localhost) au premier démarrage s'il
# n'existe pas encore, puis lance Nginx au premier plan. En production, c'est
# Let's Encrypt (certbot) qui fournit le certificat : ici on simule simplement
# la terminaison TLS du sujet.
set -euo pipefail

CERT_DIR="/etc/nginx/certs"
CERT="${CERT_DIR}/server.crt"
KEY="${CERT_DIR}/server.key"

if [[ ! -f "${CERT}" || ! -f "${KEY}" ]]; then
  echo "Génération du certificat auto-signé (CN=localhost)..."
  mkdir -p "${CERT_DIR}"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "${KEY}" -out "${CERT}" \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
  echo "Certificat écrit dans ${CERT_DIR}."
else
  echo "Certificat déjà présent dans ${CERT_DIR}, réutilisation."
fi

echo "Load balancer prêt : http://localhost:8080 (301) -> https://localhost:8443"
exec nginx -g "daemon off;"
