FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
COPY server/package.json ./server/package.json
RUN npm ci
COPY server ./server
RUN npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
COPY server/package.json ./server/package.json
RUN npm ci --omit=dev
COPY --from=build --chown=node:node /app/server/dist ./server/dist
COPY --chown=node:node server/src/db/schema.sql ./server/dist/db/schema.sql
COPY --chown=node:node data/gyms.public-verified.json ./data/gyms.public-verified.json
RUN mkdir -p /app/uploads && chown -R node:node /app/uploads
USER node
EXPOSE 3000
CMD ["node", "server/dist/index.js"]
