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
COPY --from=build /app/server/dist ./server/dist
COPY server/src/db/schema.sql ./server/dist/db/schema.sql
EXPOSE 3000
CMD ["node", "server/dist/index.js"]
