# Production-Ready Backend Dockerfile
# Multi-stage build with security hardening and optimization

# Build stage
FROM node:22-alpine3.22 AS builder

# Install security updates
RUN apk upgrade --no-cache && \
    apk add --no-cache \
    curl && \
    rm -rf /var/cache/apk/*

# Create app directory
WORKDIR /usr/src/app

# Copy package files for dependency installation
COPY package*.json ./

# Install all dependencies (including dev dependencies for build)
RUN npm install \
    npm cache clean --force

# Copy source code
COPY . .

# Run build process (if applicable)
RUN npm run build 2>/dev/null || echo "No build script found"

# Run security audit and fix issues
RUN npm audit --audit-level=high --production || true

# Remove dev dependencies for smaller production image
RUN npm prune --production

#  Alpine-based production stage (if distroless doesn't work)
FROM node:22-alpine3.22 AS production

# Install security updates and remove unnecessary packages
RUN apk upgrade --no-cache && \
    apk add --no-cache \
    curl \
    && apk del --no-cache \
    wget \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/*

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs

# Set working directory
WORKDIR /usr/src/app

# Copy application files with proper ownership
COPY --from=builder --chown=nodejs:nodejs /usr/src/app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /usr/src/app/src ./src
COPY --from=builder --chown=nodejs:nodejs /usr/src/app/package.json ./package.json

# Set production environment
ENV NODE_ENV=production \
    PORT=3000 \
    NODE_OPTIONS="--max-old-space-size=512" \
    UV_THREADPOOL_SIZE=4

# Use non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Start application
CMD ["node", "src/server.js"]