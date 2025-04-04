FROM node:18-slim

WORKDIR /app

# Install required dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Medusa CLI
RUN npm install -g @medusajs/medusa-cli

# Copy package.json and package-lock.json files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the rest of the application code
COPY . .

# Build the application
RUN npm run build

# Expose the port
EXPOSE 9000

# Command to run the application
CMD ["npm", "start"]
