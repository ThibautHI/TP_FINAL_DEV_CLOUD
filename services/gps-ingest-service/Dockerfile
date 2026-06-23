# Étape 1 : Construction et installation des dépendances
FROM oven/bun:1-alpine AS builder

WORKDIR /usr/src/app

COPY package*.json ./

# Installer uniquement les dépendances de production
RUN bun install --production

# Étape 2 : Runtime final de production
FROM oven/bun:1-alpine

# Corriger les CVE de l'image de base Alpine en mettant à jour les paquets
RUN apk update && apk upgrade --no-cache

WORKDIR /usr/src/app

# Copier les dépendances installées et le code source
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY package.json ./
COPY server.js ./

ENV PORT=3001
EXPOSE 3001

# Exécuter l'application sous un utilisateur non-root par sécurité (exigence DevSecOps)
USER bun

CMD ["bun", "run", "server.js"]
