# Lab 6: Complex Multi-Container Application

## Objective

Build and deploy a complete 3-tier application using Docker Compose.
This demonstrates advanced concepts like custom builds, network segmentation, health checks, and production-ready configurations.

## Prerequisites

- Completed Labs 1-5
- Understanding of Docker Compose basics
- Basic knowledge of React, Node.js, and PostgreSQL (helpful but not required)

## Application Architecture

This lab creates a production-like 3-tier Todo application:

### Frontend (React + Nginx)

- **Technology**: React.js served by Nginx
- **Purpose**: User interface for todo management
- **Network**: Connected to frontend-network
- **Port**: 3000 (host) → 80 (container)

### Backend (Node.js API)

- **Technology**: Express.js REST API
- **Purpose**: Business logic and database interaction
- **Network**: Connected to both frontend-network and backend-network
- **Port**: 3001 (host) → 3000 (container)

### Database (PostgreSQL)

- **Technology**: PostgreSQL 13
- **Purpose**: Data persistence
- **Network**: Connected to backend-network only (security isolation)
- **Port**: Internal only (not exposed to host)

## Project Structure

Create the following directory structure:

```plaintext
todo-app/
├── docker-compose.yml
├── frontend/
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── package.json
│   └── src/
│       └── (React app files)
├── backend/
│   ├── Dockerfile
│   ├── package.json
│   └── src/
│       └── (Node.js API files)
└── database/
    └── init.sql
```

## Lab Setup

### 1. Create Project Structure

```bash
mkdir todo-app
cd todo-app

# Create service directories
mkdir frontend backend database

# Copy the provided docker-compose.yml to the root directory
# Copy the provided Dockerfiles to respective directories
```

### 2. Frontend Configuration Files

Create `frontend/nginx.conf`:

Create `frontend/package.json`:

### 3. Backend Configuration Files

Create `backend/package.json`

Create `backend/src/server.js`

### 4. Database Configuration

Create `database/init.sql`

## Lab Exercises

### Exercise 1: Build and Deploy the Application

1. **Verify project structure:**

   ```bash
   # From todo-app directory
   tree .
   ```

2. **Build and start all services:**

   ```bash
   docker compose build
   docker compose up -d
   ```

3. **Monitor the build and startup process:**

   ```bash
   docker compose logs -f
   ```

4. **Verify all services are healthy:**

   ```bash
   docker compose ps
   ```

5. **Test the application:**
   - Frontend: <http://localhost:3000>
   - Backend API: <http://localhost:3001/health>
   - Database: Internal only (test via backend)

### Exercise 2: Network Segmentation Analysis

1. **Examine network configuration:**

   ```bash
   # List networks created by compose
   docker network ls | grep todo-app

   # Inspect frontend network
   docker network inspect todo-app_frontend-network

   # Inspect backend network
   docker network inspect todo-app_backend-network
   ```

2. **Test network isolation:**

   ```bash
   # Frontend can reach backend
   docker compose exec frontend ping backend

   # Backend can reach database
   docker compose exec backend ping database

   # Frontend CANNOT reach database (should fail)
   docker compose exec frontend ping database
   ```

3. **Understand security implications:**
   - Frontend and database are isolated
   - Only backend can access database
   - Follows principle of least privilege

### Exercise 3: Health Checks and Dependencies

1. **Monitor health status:**

   ```bash
   # View health check status
   docker compose ps

   # Watch health checks in real-time
   watch docker compose ps
   ```

2. **Test dependency startup order:**

   ```bash
   # Stop all services
   docker compose down

   # Start and observe startup order
   docker compose up
   # Notice: database starts first, then backend waits for health, then frontend
   ```

3. **Simulate database failure:**

   ```bash
   # Stop database container
   docker compose stop database

   # Observe backend health checks failing
   docker compose logs backend

   # Restart database
   docker compose start database
   ```

### Exercise 4: Scaling and Load Testing

1. **Scale backend services:**

   ```bash
   # Scale backend to 3 instances
   docker compose up -d --scale backend=3
   ```

2. **Verify load distribution:**

   ```bash
   # Check running containers
   docker compose ps

   # Monitor logs from all backend instances
   docker compose logs backend
   ```

3. **Test API load:**

   ```bash
   # Create multiple todos to test load distribution
   for i in {1..10}; do
     curl -X POST http://localhost:3001/todos \
       -H "Content-Type: application/json" \
       -d "{\"title\":\"Test Todo $i\"}"
   done
   ```

### Exercise 5: Data Persistence and Backup

1. **Test data persistence:**

   ```bash
   # Add some todos via the web interface
   # Then stop all services
   docker compose down

   # Restart services
   docker compose up -d

   # Verify data is still there
   ```

2. **Backup database:**

   ```bash
   # Create database backup
   docker compose exec database pg_dump -U todouser todoapp > backup.sql
   ```

3. **Volume management:**

   ```bash
   # List volumes
   docker volume ls | grep todo-app

   # Inspect database volume
   docker volume inspect todo-app_postgres_data
   ```

## Advanced Concepts Demonstrated

### Multi-Stage Docker Builds

- Frontend Dockerfile uses multi-stage build
- Build stage: Compiles React application
- Production stage: Serves with optimized nginx

### Network Segmentation

- Frontend network: Frontend ↔ Backend communication
- Backend network: Backend ↔ Database communication
- Database isolated from frontend (security)

### Health Checks

- Database: PostgreSQL connection check
- Backend: HTTP health endpoint
- Dependency management: Backend waits for healthy database

### Configuration Management

- Environment variables for database connection
- Secrets management considerations
- Service discovery via DNS

## Troubleshooting

### Build Failures

```bash
# Check build logs
docker compose build --no-cache

# Build specific service
docker compose build backend

# Verbose output
docker compose build --progress=plain
```

### Service Communication Issues

```bash
# Check network connectivity
docker compose exec frontend nslookup backend
docker compose exec backend nslookup database

# Check port bindings
docker compose port backend 3000
```

### Database Connection Problems

```bash
# Check database logs
docker compose logs database

# Test database connection manually
docker compose exec backend psql -h database -U todouser -d todoapp
```

### Performance Issues

```bash
# Monitor resource usage
docker stats $(docker compose ps -q)

# Check container limits
docker inspect $(docker compose ps -q backend)
```

## Production Considerations

This lab demonstrates several production-ready practices:

1. **Security**: Network segmentation, non-root users
2. **Reliability**: Health checks, dependency management
3. **Performance**: Multi-stage builds, resource optimization
4. **Monitoring**: Health endpoints, logging
5. **Scalability**: Service scaling capabilities

## Clean Up

### Stop Services

```bash
docker compose down
```

### Remove All Data

```bash
docker compose down -v
```

### Remove Images

```bash
docker compose down --rmi all
```

## Learning Outcomes

By completing this lab, you should understand:

- [ ] Multi-stage Docker builds for optimization
- [ ] Network segmentation for security
- [ ] Health checks and dependency management
- [ ] Service scaling with Docker Compose
- [ ] Production-ready configuration patterns
- [ ] Database integration and persistence
- [ ] API gateway patterns with nginx

## Next Steps

This lab demonstrates the capabilities and complexity of multi-container applications. In Lab 7, we'll explore the limitations of this single-host approach and understand why orchestration platforms like Kubernetes are necessary for production deployments.

## Resources

- [Docker Compose Networking](https://docs.docker.com/compose/networking/)
- [Multi-stage Builds](https://docs.docker.com/develop/dev-best-practices/)
- [Health Checks in Compose](https://docs.docker.com/compose/compose-file/compose-file-v3/#healthcheck)
- [PostgreSQL Docker Image](https://hub.docker.com/_/postgres)
