# ---------- Build Stage ----------
FROM node:20-alpine AS builder

WORKDIR /app

# Copy only package files first (layer caching)
COPY package*.json ./

# Clean, reproducible install
RUN npm ci

# Copy source code
COPY src ./src

# ---------- Runtime Stage ----------
FROM node:20-alpine

WORKDIR /app

# Copy only needed files from builder
COPY --from=builder /app /app

# Expose app port
EXPOSE 3000

# Start the app
CMD ["node", "src/index.js"]
