FROM node:18 AS builder

WORKDIR /app

# Install required dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*



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
