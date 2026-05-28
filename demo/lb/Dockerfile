# Démo locale — load balancer (équivalent de la VM Nginx du sujet).
# openssl : génération du certificat auto-signé au démarrage (entrypoint.sh)
# bash    : scripts shell de la démo
FROM nginx:alpine

RUN apk add --no-cache openssl bash

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
