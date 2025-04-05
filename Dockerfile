FROM node:18-alpine

WORKDIR /app

# Copy package files first for better caching
COPY package.json package-lock.json ./

# Increase Node memory limit and use ci for cleaner installs
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN npm ci

# Then copy the rest of the app
COPY . .

# Build if needed
RUN npm run build

# Environment settings
ENV NODE_ENV=production
ENV PORT=9000

EXPOSE 9000

CMD ["npm", "start"]
