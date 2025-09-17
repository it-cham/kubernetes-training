# Lab 5: First Docker Compose Application

## Objective

Create and deploy a multi-container WordPress application using Docker Compose.
This demonstrates service definitions, networking, and volume management.

## Prerequisites

- Completed Lab 1: Docker Installation
- Basic understanding of YAML syntax
- Docker and Docker Compose installed and verified

## Application Architecture

This lab creates a simple two-tier web application:

- **WordPress**: Web application container (PHP/Apache)
- **MySQL**: Database container
- **Shared Network**: Allows containers to communicate
- **Persistent Storage**: Database and WordPress files persist across restarts

## Lab Setup

### 1. Create Project Directory

```bash
mkdir wordpress-app
cd wordpress-app
```

### 2. Create Docker Compose File

Create a file named `docker-compose.yml` in your project directory with the provided configuration.

## Understanding the Configuration

### Service Definitions

**WordPress Service:**

```yaml
wordpress:
  image: wordpress:latest          # Use official WordPress image
  ports:
    - "8080:80"                    # Map host port 8080 to container port 80
  environment:                     # Configuration via environment variables
    WORDPRESS_DB_HOST: mysql       # Database hostname (service name)
    WORDPRESS_DB_USER: wordpress   # Database username
    WORDPRESS_DB_PASSWORD: wordpress_password
    WORDPRESS_DB_NAME: wordpress   # Database name
  depends_on:                      # Ensure MySQL starts before WordPress
    - mysql
  volumes:
    - wordpress_data:/var/www/html # Persist WordPress files
```

**MySQL Service:**

```yaml
mysql:
  image: mysql:8.4.6               # Use MySQL 8.4.6 (latest stable LTS version)
  environment:                     # MySQL configuration
    MYSQL_DATABASE: wordpress      # Create database named 'wordpress'
    MYSQL_USER: wordpress          # Create user 'wordpress'
    MYSQL_PASSWORD: wordpress_password  # Set user password
    MYSQL_ROOT_PASSWORD: root_password   # Set root password
  volumes:
    - mysql_data:/var/lib/mysql    # Persist database files
```

### Key Concepts Explained

**Inter-Service Communication:**

- Services communicate using service names as hostnames
- WordPress connects to MySQL using hostname "mysql"
- Docker Compose creates a default network for all services

**Environment Variables:**

- Configure applications without rebuilding images
- WordPress reads database connection info from environment
- MySQL creates database and user based on environment variables

**Volume Persistence:**

- Named volumes store data outside containers
- Data survives container stops, restarts, and updates
- Volumes are managed by Docker

## Lab Exercises

### Exercise 1: Deploy the Application

1. **Start the application stack:**

   ```bash
   docker compose up -d
   ```

2. **Verify containers are running:**

   ```bash
   docker compose ps
   ```

   Expected output shows both services running:

   ```plaintext
   Name                    State    Ports
   wordpress-app_mysql_1       Up      3306/tcp
   wordpress-app_wordpress_1   Up      0.0.0.0:8080->80/tcp
   ```

3. **Check application logs:**

   ```bash
   docker compose logs wordpress
   docker compose logs mysql
   ```

4. **Access WordPress:**
   - Open browser to <http://localhost:8080>
   - Complete WordPress installation wizard
   - Create admin account and test functionality

### Exercise 2: Explore Service Communication

1. **Test inter-service connectivity:**

   ```bash
   # Access WordPress container
   docker compose exec wordpress bash

   # Test connection to MySQL (inside WordPress container)
   ping mysql

   # Test MySQL connection (if mysql client available)
   mysql -h mysql -u wordpress -p wordpress
   # Enter password: wordpress_password

   # Exit containers
   exit
   ```

2. **Examine network configuration:**

   ```bash
   # List Docker networks
   docker network ls

   # Inspect the application network
   docker network inspect wordpress-app_default
   ```

### Exercise 3: Data Persistence Testing

1. **Create test content:**
   - In WordPress admin, create a test page or blog post
   - Add some content and publish

2. **Stop and restart containers:**

   ```bash
   docker compose down
   docker compose up -d
   ```

3. **Verify data persistence:**
   - Access <http://localhost:8080>
   - Confirm your content is still there
   - Database connections work immediately (no reconfiguration needed)

### Exercise 4: Scaling and Management

1. **View container resource usage:**

   ```bash
   docker stats $(docker compose ps -q)
   ```

2. **Scale WordPress (multiple instances):**

   ```bash
   docker compose up -d --scale wordpress=2
   ```

   Note: This will fail because both containers try to bind to port 8080. This demonstrates single-host limitations we'll explore in later labs.

3. **Return to single instance:**

   ```bash
   docker compose up -d --scale wordpress=1
   ```

### Exercise 5: Configuration Management

1. **Update WordPress configuration:**
   Edit `docker-compose.yml` to add environment variable:

   ```yaml
   wordpress:
     # ... existing configuration ...
     environment:
       # ... existing environment vars ...
       WORDPRESS_DEBUG: 1
   ```

2. **Apply configuration changes:**

   ```bash
   docker compose up -d
   ```

   Docker Compose detects changes and recreates affected containers.

3. **Verify configuration:**
   Check WordPress logs for debug information:

   ```bash
   docker compose logs wordpress
   ```

## Common Commands Reference

### Application Lifecycle

```bash
# Start services
docker compose up -d

# Stop services (containers removed)
docker compose down

# Stop services (keep containers)
docker compose stop

# Start stopped services
docker compose start

# Restart services
docker compose restart
```

### Monitoring and Debugging

```bash
# View service status
docker compose ps

# View logs (all services)
docker compose logs

# View logs (specific service)
docker compose logs wordpress

# Follow logs in real-time
docker compose logs -f

# Execute commands in running container
docker compose exec wordpress bash
```

### Volume and Network Management

```bash
# List volumes created by compose
docker volume ls

# Remove application and volumes
docker compose down -v

# View networks
docker network ls
```

## Troubleshooting

### Common Issues

**Port Already in Use:**

```bash
Error: bind: address already in use
```

Solution: Change host port in docker-compose.yml:

```yaml
ports:
  - "8081:80"  # Use different port
```

**Database Connection Failed:**

- Check that MySQL container is running: `docker compose ps`
- Verify environment variables match between WordPress and MySQL
- Check logs: `docker compose logs mysql`

**WordPress Installation Wizard Loops:**

- Ensure volumes are properly mounted
- Check file permissions in WordPress container
- Verify database credentials are correct

**Containers Won't Start:**

```bash
# Check for syntax errors
docker compose config

# View detailed error messages
docker compose up
```

### Health Checks

```bash
# Test WordPress is responding
curl http://localhost:8080

# Test MySQL is accessible (from WordPress container)
docker compose exec wordpress mysql -h mysql -u wordpress -p
```

## Clean Up

### Remove Application (Keep Data)

```bash
docker compose down
```

### Remove Application and Data

```bash
docker compose down -v
```

### Remove Images

```bash
docker rmi wordpress:latest mysql:8.4.6
```

## Learning Outcomes

By completing this lab, you should understand:

- [ ] How to define multi-container applications with Docker Compose
- [ ] Service-to-service communication using service names
- [ ] Environment variable configuration for containers
- [ ] Volume management for data persistence
- [ ] Basic Docker Compose commands and workflow
- [ ] How depends_on controls startup order
- [ ] Difference between `down` and `stop` commands

## Advanced Challenges (Optional)

1. **Add phpMyAdmin:**
   Add a phpMyAdmin service to manage the MySQL database via web interface.

2. **Environment File:**
   Create a `.env` file to externalize environment variables.

3. **Custom Network:**
   Define a custom network instead of using the default.

4. **Health Checks:**
   Add health check configurations for both services.

## Next Steps

This lab introduced Docker Compose basics with a simple two-tier application. In Lab 6, we'll build a more complex three-tier application with custom builds, advanced networking, and production considerations.

## Resources

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [WordPress Docker Image](https://hub.docker.com/_/wordpress)
- [MySQL Docker Image](https://hub.docker.com/_/mysql)
- [Compose File Reference](https://docs.docker.com/compose/compose-file/)
