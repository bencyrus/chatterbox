# Development stage
FROM node:20-alpine AS development

WORKDIR /app

COPY web/package*.json ./
RUN npm install

COPY web/ .
# Docs are outside web/; path alias resolves via DB_FIRST_DOCS_ROOT in compose
COPY docs/database-first /docs/database-first

ENV DB_FIRST_DOCS_ROOT=/docs/database-first

EXPOSE 5173

CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

# Production stage
FROM node:20-alpine AS production

WORKDIR /app

COPY web/package*.json ./
RUN npm install

COPY web/ .
COPY docs/database-first /docs/database-first

ENV DB_FIRST_DOCS_ROOT=/docs/database-first

RUN npm run build

RUN npm install -g serve

EXPOSE 5173

CMD ["serve", "-s", "dist", "-l", "5173"]
