# Étape 1 : Construction et dépendances
FROM oven/bun:1-alpine AS builder
WORKDIR /usr/src/app
COPY package*.json ./
RUN bun install --production

# Étape 2 : Runtime
FROM oven/bun:1-alpine
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY package.json ./
COPY server.js ./

ENV PORT=3003
EXPOSE 3003
USER bun
CMD ["bun", "run", "server.js"]
