FROM node:18 AS builder

WORKDIR /app

# Install required dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set higher npm log level for debugging
ENV NPM_CONFIG_LOGLEVEL=verbose
ENV NODE_OPTIONS="--max-old-space-size=4096"

# Install Medusa CLI
RUN npm install -g @medusajs/medusa-cli@latest

# First, copy only package files and install dependencies
COPY package.json .
COPY package-lock.json* .
COPY yarn.lock* .

# Try yarn if available, otherwise fall back to npm
RUN (test -f yarn.lock && yarn install --frozen-lockfile --network-timeout 600000) || \
    (test -f package-lock.json && npm ci --network-timeout 600000) || \
    npm install --no-package-lock --network-timeout 600000

# Then copy the rest of the application code
COPY . .

# Build the application
RUN npm run build

# Final stage for smaller image
FROM node:18-slim

WORKDIR /app

# Install only production dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy built application from builder stage
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json

# Medusa may need these directories
COPY --from=builder /app/medusa-config.js* ./
COPY --from=builder /app/data ./data
COPY --from=builder /app/uploads ./uploads

# Set environment variables
ENV NODE_ENV=production
ENV PORT=9000

EXPOSE 9000

CMD ["node", "dist/main"]
