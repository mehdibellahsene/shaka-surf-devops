# Image du backend mock Shaka Surf — Node 20 minimal.
FROM node:20-alpine

WORKDIR /app

# Dépendances de production uniquement (express, pg).
COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./

# Le process ne tourne pas en root.
USER node

EXPOSE 9940
CMD ["node", "server.js"]
