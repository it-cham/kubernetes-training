# Lab 6 Extension: Production Docker Optimization

## Overview

This guide demonstrates core Docker optimizations to transform development configurations into production-ready deployments, focusing on image efficiency, security basics, and operational reliability.

## Key Production Improvements

### 1. Multi-Stage Docker Builds

**Development Problem:**

- Large images with build tools and dev dependencies
- Source code and build artifacts in production images

**Production Solution:**

```dockerfile
# Build stage - Contains build dependencies
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Production stage - Only runtime files
FROM nginx:alpine AS production
COPY --from=builder /app/build /usr/share/nginx/html
```

**Benefits:**

- **Image size:** 60-80% smaller images
- **Security:** No build tools in production
- **Performance:** Faster deployments

### 2. Non-Root User Security

**Development (runs as root):**

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY . .
CMD ["npm", "start"]
```

**Production (runs as non-root):**

```dockerfile
FROM node:18-alpine
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs
WORKDIR /usr/src/app
COPY --chown=nodejs:nodejs . .
USER nodejs
```

**Security Benefits:**

- Prevents privilege escalation attacks
- Limits impact of container compromise
- Industry security compliance

### 3. Health Checks and Dependencies

**Development:**

```yaml
services:
  backend:
    image: myapp:dev
    depends_on:
      - database
```

**Production:**

```yaml
services:
  backend:
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) }).on('error', () => process.exit(1))"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s
    depends_on:
      database:
        condition: service_healthy
```

**Operational Benefits:**

- Automatic unhealthy container replacement
- Proper startup sequencing
- Load balancer integration ready

### 4. Resource Management

**Production Configuration:**

```yaml
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

**Benefits:**

- Predictable resource usage
- Prevents resource exhaustion
- Better cost control

### 5. Security Hardening

**Docker Compose Security:**

```yaml
services:
  backend:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=100m
    user: "1001:1001"
```

**Security Benefits:**

- **no-new-privileges:** Prevents privilege escalation
- **read_only:** Immutable container filesystem
- **tmpfs:** Secure temporary storage
- **user:** Explicit non-root user

### 6. Network Segmentation

**Development (single network):**

```yaml
services:
  frontend:
    depends_on: [backend]
  backend:
    depends_on: [database]
  database:
```

**Production (isolated networks):**

```yaml
services:
  frontend:
    networks: [frontend-network]
  backend:
    networks: [frontend-network, backend-network]
  database:
    networks: [backend-network]

networks:
  frontend-network:
  backend-network:
```

**Security Benefits:**

- Frontend cannot directly access database
- Attack surface reduction
- Clear service boundaries

### 7. Secrets Management

**Development (environment variables):**

```yaml
environment:
  - DATABASE_URL=postgresql://user:pass@db:5432/app
```

**Production (Docker secrets):**

```yaml
environment:
  - DATABASE_URL_FILE=/run/secrets/db_url
secrets:
  - db_url
secrets:
  db_url:
    external: true
```

**Security Benefits:**

- Secrets not in container images
- Runtime secret injection
- Easier secret rotation

## Before vs After Comparison

| Aspect | Development | Production | Improvement |
|---------|------------|------------|-------------|
| Frontend Image | 450MB | 85MB | 81% smaller |
| Backend Image | 380MB | 65MB | 83% smaller |
| User | root | non-root | Security compliance |
| Health Checks | None | Comprehensive | Auto-recovery |
| Networks | Single | Segmented | Attack isolation |
| Resources | Unlimited | Controlled | Predictable performance |

## Image Size Optimization

### Dockerfile Best Practices

1. **Use multi-stage builds** to separate build and runtime
2. **Install only production dependencies** in final stage
3. **Use Alpine base images** for smaller footprint
4. **Clean up package caches** after installation
5. **Copy only necessary files** to production stage

```dockerfile
# Good - Optimized layers
FROM node:18-alpine AS builder
RUN apk add --no-cache python3 make g++
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

FROM node:18-alpine AS production
RUN apk add --no-cache dumb-init
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
```

## Security Checklist

### Container Security

- [ ] Non-root user configured
- [ ] no-new-privileges enabled
- [ ] Read-only filesystem where possible
- [ ] Minimal base image used
- [ ] Security updates applied

### Compose Security

- [ ] Secrets externalized
- [ ] Network segmentation implemented
- [ ] Resource limits configured
- [ ] Health checks defined
- [ ] Restart policies set

## Common Pitfalls and Solutions

### Issue: Large Image Sizes

**Problem:** Development images with build tools
**Solution:** Multi-stage builds with minimal production stage

### Issue: Container Runs as Root

**Problem:** Default container user is root
**Solution:** Create and use non-root user in Dockerfile

### Issue: Services Start in Wrong Order

**Problem:** Database not ready when app starts
**Solution:** Use `condition: service_healthy` dependencies

### Issue: Secrets in Environment Variables

**Problem:** Sensitive data visible in `docker inspect`
**Solution:** Use Docker secrets with file-based injection

### Issue: Resource Exhaustion

**Problem:** Containers consume all available resources
**Solution:** Set memory and CPU limits in deploy section

## Quick Migration Guide

### Step 1: Optimize Images

- Add multi-stage builds to Dockerfiles
- Create non-root users
- Add health check endpoints to applications

### Step 2: Update Compose File

- Add health checks and proper dependencies
- Configure resource limits
- Implement network segmentation
- Externalize secrets

### Step 3: Test Production Build

```bash
# Build production images
docker comose -f docker-compose.prod.yml build

# Deploy and verify
docker comose -f docker-compose.prod.yml up -d
docker comose -f docker-compose.prod.yml ps

# Check health status
docker comose -f docker-compose.prod.yml logs
```

### Step 4: Validate Optimizations

```bash
# Check image sizes
docker images | grep todo-app

# Verify non-root users
docker comose exec backend id
docker comose exec frontend id

# Test network isolation
docker comose exec frontend ping database  # Should fail
```

This systematic approach provides production-ready containers while maintaining the simplicity needed for learning and development workflows.
