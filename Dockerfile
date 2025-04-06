# Build stage
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies
RUN apk add --no-cache python3 make g++

# Copy package files
COPY package*.json ./

# Install all dependencies (including dev dependencies)


# Copy the rest of the application
COPY . .

# Build the application if needed (uncomment if you have a build step)
# RUN npm run build

# Production stage
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Set environment variables
ENV NODE_ENV production
ENV NPM_CONFIG_LOGLEVEL warn
ENV NODE_OPTIONS="--max-old-space-size=750"

# Install production system dependencies
RUN apk add --no-cache python3

# Install Medusa CLI globally
RUN npm install -g @medusajs/medusa-cli

# Copy only the necessary files from the builder stage
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/src ./src
COPY --from=builder /app/medusa-config.js ./

# Expose the port Medusa runs on
EXPOSE 9000

# Set up a healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget -q -O - http://localhost:9000/health || exit 1

# Start the Medusa server
CMD ["medusa", "start"]
