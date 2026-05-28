# Frontend statique du mock Shaka Surf, servi par Nginx.
# L'entrypoint officiel de l'image applique envsubst sur les fichiers de
# /etc/nginx/templates/*.template au démarrage : seules les variables
# présentes dans l'environnement (ici API_HOST) sont substituées.
FROM nginx:alpine

# Hôte du backend, substitué dans default.conf.template au démarrage.
ENV API_HOST=api

COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY html /usr/share/nginx/html
