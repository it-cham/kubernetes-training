# Lab 4: Container Storage Management

## Objective

Master Docker volume management and understand data persistence strategies.
Learn to share data between containers and/or the host system using volumes and bind mounts.

## Prerequisites

- Completed Lab 3: Container Networking & Communication
- Understanding of file systems and directory structures
- Docker installed and running

## Learning Goals

By the end of this lab, you will:

- Understand container filesystem limitations
- Create and manage Docker volumes
- Use bind mounts for development workflows
- Share data between multiple containers
- Implement data persistence strategies
- Backup and restore container data

## Storage Concepts Overview

### Container Filesystem

- **Ephemeral**: Data disappears when container is removed
- **Layered**: Based on image layers plus writable container layer
- **Isolated**: Each container has its own filesystem view

### Volume Types

1. **Named Volumes**: Managed by Docker, stored in Docker area
2. **Anonymous Volumes**: Created automatically, harder to manage
3. **Bind Mounts**: Mount host directory into container
4. **tmpfs Mounts**: Temporary filesystem in memory (Linux only)

## Lab Exercises

### Exercise 1: Demonstrate Ephemeral Container Storage

1. **Create container and add data:**

   ```bash
   # Start Ubuntu container
   docker run -it --name temp-storage ubuntu bash

   # Inside container, create some data
   echo "This is temporary data" > /tmp/important.txt
   echo "Application settings" > /app/config.txt
   mkdir -p /data
   echo "User data" > /data/user-info.txt

   # List created files
   ls -la /tmp/important.txt /app/config.txt /data/user-info.txt

   # Exit container
   exit
   ```

2. **Restart container and check data:**

   ```bash
   # Start the same container
   docker start temp-storage
   docker exec -it temp-storage bash

   # Check if data still exists
   cat /tmp/important.txt    # Still there
   cat /app/config.txt       # Still there
   cat /data/user-info.txt   # Still there

   exit
   ```

3. **Remove container and demonstrate data loss:**

   ```bash
   # Remove container
   docker rm temp-storage

   # Start new container with same image
   docker run -it --name new-container ubuntu bash

   # Try to access previous data
   ls /tmp/important.txt     # File not found
   ls /app/config.txt        # File not found
   ls /data/user-info.txt    # File not found

   exit
   docker rm new-container
   ```

### Exercise 2: Named Volumes for Data Persistence

1. **Create named volume:**

   ```bash
   # Create volume
   docker volume create my-persistent-data

   # List volumes
   docker volume ls

   # Inspect volume details
   docker volume inspect my-persistent-data
   ```

2. **Use volume in container:**

   ```bash
   # Mount volume to /data directory
   docker run -it --name vol-test -v my-persistent-data:/data ubuntu bash

   # Create data in mounted volume
   echo "Persistent application data" > /data/app-data.txt
   echo "Configuration settings" > /data/config.json
   mkdir -p /data/logs
   echo "$(date): Application started" > /data/logs/app.log

   # Verify data exists
   ls -la /data/
   cat /data/app-data.txt

   exit
   ```

3. **Test data persistence across container lifecycle:**

   ```bash
   # Remove container (but not volume)
   docker rm vol-test

   # Create new container with same volume
   docker run -it --name vol-test2 -v my-persistent-data:/data ubuntu bash

   # Check if data persists
   ls -la /data/
   cat /data/app-data.txt     # Data is still there!
   cat /data/logs/app.log

   # Add more data
   echo "$(date): New container started" >> /data/logs/app.log

   exit
   docker rm vol-test2
   ```

### Exercise 3: Bind Mounts for Development

1. **Create host directory and files:**

   ```bash
   # Create project directory on host
   mkdir -p ~/docker-lab/webapp
   cd ~/docker-lab/webapp

   # Create sample web files
   cat > index.html << EOF
   <!DOCTYPE html>
   <html>
   <head><title>Docker Volume Demo</title></head>
   <body>
       <h1>Hello from Docker Volume!</h1>
       <p>This file is mounted from the host system.</p>
   </body>
   </html>
   EOF

   cat > style.css << EOF
   body {
       font-family: Arial, sans-serif;
       background-color: #f0f0f0;
       margin: 40px;
   }
   h1 { color: #333; }
   EOF
   ```

2. **Mount host directory into container:**

   ```bash
   # Start web server with bind mount
   docker run -d --name dev-server \
     -p 8080:80 \
     -v $(pwd):/usr/share/nginx/html \
     nginx
   ```

3. **Test live file editing:**

   ```bash
   # Check website
   curl http://localhost:8080
   # Or open browser: http://localhost:8080

   # Edit file on host
   echo "<p><strong>Updated from host!</strong></p>" >> index.html

   # Check website again (changes appear immediately)
   curl http://localhost:8080
   ```

4. **Compare with copying files:**

   ```bash
   # Stop bind mount server
   docker stop dev-server
   docker rm dev-server

   # Create server by copying files (traditional approach)
   docker run -d --name copy-server -p 8081:80 nginx
   docker cp index.html copy-server:/usr/share/nginx/html/
   docker cp style.css copy-server:/usr/share/nginx/html/

   # Edit host file
   echo "<p>This change won't appear in copy-server</p>" >> index.html

   # Compare outputs
   curl http://localhost:8081  # Old version
   cat index.html              # New version

   docker stop copy-server
   docker rm copy-server
   ```

### Exercise 4: Volume Sharing Between Containers

1. **Create shared volume:**

   ```bash
   docker volume create shared-storage
   ```

2. **Producer container (writes data):**

   ```bash
   # Start producer container
   docker run -d --name producer \
     -v shared-storage:/shared \
     ubuntu bash -c "
       while true; do
         echo \"$(date): Message from producer\" >> /shared/messages.log
         sleep 5
       done
     "
   ```

3. **Consumer container (reads data):**

   ```bash
   # Start consumer container
   docker run -d --name consumer \
     -v shared-storage:/shared \
     ubuntu bash -c "
       while true; do
         echo \"=== Latest messages ===\"
         tail -n 5 /shared/messages.log 2>/dev/null || echo \"No messages yet\"
         sleep 10
       done
     "

   # Watch consumer output
   docker logs -f consumer
   ```

4. **Interactive consumer for real-time monitoring:**

   ```bash
   # Start interactive monitoring container
   docker run -it --name monitor \
     -v shared-storage:/shared \
     ubuntu bash

   # Inside container, monitor the shared file
   tail -f /shared/messages.log

   # In another terminal, check producer logs
   # docker logs producer

   # Exit monitoring
   exit
   ```

5. **Clean up shared containers:**

   ```bash
   docker stop producer consumer monitor
   docker rm producer consumer monitor
   ```

### Exercise 5: Database Data Persistence

1. **Deploy database without volume (data loss scenario):**

   ```bash
   # Start MySQL without volume
   docker run -d --name mysql-temp \
     -e MYSQL_ROOT_PASSWORD=rootpass \
     -e MYSQL_DATABASE=testdb \
     -e MYSQL_USER=testuser \
     -e MYSQL_PASSWORD=testpass \
     mysql:8.0

   # Wait for database to initialize
   sleep 30

   # Add some data
   docker exec -it mysql-temp mysql -u testuser -ptestpass testdb -e "
     CREATE TABLE users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50));
     INSERT INTO users (name) VALUES ('Alice'), ('Bob'), ('Charlie');
     SELECT * FROM users;
   "

   # Remove container
   docker stop mysql-temp
   docker rm mysql-temp

   # Data is lost!
   ```

2. **Deploy database with persistent volume:**

   ```bash
   # Create volume for database
   docker volume create mysql-data

   # Start MySQL with volume
   docker run -d --name mysql-persistent \
     -e MYSQL_ROOT_PASSWORD=rootpass \
     -e MYSQL_DATABASE=testdb \
     -e MYSQL_USER=testuser \
     -e MYSQL_PASSWORD=testpass \
     -v mysql-data:/var/lib/mysql \
     mysql:8.0

   # Wait for initialization
   sleep 30

   # Add data
   docker exec -it mysql-persistent mysql -u testuser -ptestpass testdb -e "
     CREATE TABLE products (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50), price DECIMAL(10,2));
     INSERT INTO products (name, price) VALUES ('Laptop', 999.99), ('Mouse', 29.99), ('Keyboard', 79.99);
     SELECT * FROM products;
   "
   ```

3. **Test database persistence:**

   ```bash
   # Stop and remove container
   docker stop mysql-persistent
   docker rm mysql-persistent

   # Start new container with same volume
   docker run -d --name mysql-restored \
     -e MYSQL_ROOT_PASSWORD=rootpass \
     -e MYSQL_DATABASE=testdb \
     -e MYSQL_USER=testuser \
     -e MYSQL_PASSWORD=testpass \
     -v mysql-data:/var/lib/mysql \
     mysql:8.0

   # Wait for startup
   sleep 20

   # Check if data persists
   docker exec -it mysql-restored mysql -u testuser -ptestpass testdb -e "
     SELECT * FROM products;
   "

   # Data should still be there!
   ```

### Exercise 6: Volume Backup and Restore

1. **Create backup of volume data:**

   ```bash
   # Create backup using temporary container
   docker run --rm \
     -v mysql-data:/source:ro \
     -v $(pwd):/backup \
     ubuntu tar czf /backup/mysql-backup-$(date +%Y%m%d).tar.gz -C /source .

   # Verify backup file
   ls -lh mysql-backup-*.tar.gz
   ```

2. **Restore volume from backup:**

   ```bash
   # Create new volume for restore test
   docker volume create mysql-restored

   # Restore backup to new volume
   docker run --rm \
     -v mysql-restored:/target \
     -v $(pwd):/backup \
     ubuntu bash -c "cd /target && tar xzf /backup/mysql-backup-*.tar.gz"

   # Test restored volume
   docker run -d --name mysql-from-backup \
     -e MYSQL_ROOT_PASSWORD=rootpass \
     -v mysql-restored:/var/lib/mysql \
     mysql:8.0

   sleep 20

   # Verify restored data
   docker exec -it mysql-from-backup mysql -u testuser -ptestpass testdb -e "
     SELECT * FROM products;
   " || echo "Backup restore successful - data intact!"
   ```

## Volume Management Commands

### Essential Volume Commands

| Command                 | Purpose               | Example                        |
| ----------------------- | --------------------- | ------------------------------ |
| `docker volume create`  | Create named volume   | `docker volume create mydata`  |
| `docker volume ls`      | List volumes          | `docker volume ls`             |
| `docker volume inspect` | Volume details        | `docker volume inspect mydata` |
| `docker volume rm`      | Remove volume         | `docker volume rm mydata`      |
| `docker volume prune`   | Remove unused volumes | `docker volume prune`          |

### Container Volume Commands

| Command          | Purpose                   | Example                                                |
| ---------------- | ------------------------- | ------------------------------------------------------ |
| `-v name:/path`  | Mount named volume        | `docker run -v mydata:/data ubuntu`                    |
| `-v /host:/path` | Bind mount host directory | `docker run -v $(pwd):/app ubuntu`                     |
| `--mount`        | Detailed mount syntax     | `docker run --mount source=mydata,target=/data ubuntu` |

### Advanced Mount Options

```bash
# Read-only volume mount
docker run -v mydata:/data:ro ubuntu

# Bind mount with specific options
docker run --mount type=bind,source=$(pwd),target=/app,readonly ubuntu

# tmpfs mount (memory-based, Linux only)
docker run --mount type=tmpfs,target=/tmp ubuntu
```

## Storage Patterns and Best Practices

### Development Pattern

```bash
# Bind mount source code for live editing
docker run -it --name devenv \
  -v $(pwd)/src:/workspace/src \
  -v $(pwd)/config:/workspace/config:ro \
  -p 3000:3000 \
  node:18 bash
```

### Database Pattern

```bash
# Separate volume for data persistence
docker run -d --name appdb \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=myapp \
  postgres:13
```

### Backup Pattern

```bash
# Regular backup with timestamp
docker run --rm \
  -v myapp-data:/source:ro \
  -v /backups:/backup \
  ubuntu tar czf /backup/myapp-$(date +%Y%m%d-%H%M).tar.gz -C /source .
```

### Multi-Container Data Sharing

```bash
# Shared volume across application stack
docker volume create app-shared
docker run -d --name web -v app-shared:/var/www/html nginx
docker run -d --name worker -v app-shared:/workdir myapp:worker
```

## Troubleshooting

### Common Issues

**Permission Denied Errors:**

```bash
# Fix permissions for bind mount
sudo chown -R $(id -u):$(id -g) /host/directory

# Or use user mapping
docker run --user $(id -u):$(id -g) -v $(pwd):/app ubuntu
```

**Volume Not Found:**

```bash
# Check if volume exists
docker volume ls | grep volume-name

# Create if missing
docker volume create volume-name
```

**Disk Space Issues:**

```bash
# Check Docker disk usage
docker system df

# Clean up unused volumes
docker volume prune

# Remove specific volume
docker volume rm volume-name
```

**Mount Point Conflicts:**

```bash
# Check existing mounts
docker inspect container-name --format='{{json .Mounts}}'

# Use different mount point
docker run -v mydata:/app/data ubuntu  # instead of /data
```

### Diagnostic Commands

```bash
# List all mounts for a container
docker inspect <container> --format='{{json .Mounts}}' | jq

# Check volume usage
docker system df -v

# Find containers using specific volume
docker ps -a --filter volume=mydata

# Check host location of volume
docker volume inspect mydata --format='{{.Mountpoint}}'
```

## Performance Considerations

### Volume Performance Comparison

1. **Named Volumes**: Best performance, Docker-managed
2. **Bind Mounts**: Good for development, may have performance overhead on Windows/macOS
3. **tmpfs**: Fastest (memory), but temporary

### Optimization Tips

```bash
# Use delegated consistency for better performance on macOS
docker run -v $(pwd):/app:delegated myapp

# Use cached consistency for read-heavy workloads
docker run -v $(pwd):/app:cached myapp

# Avoid deep directory structures in bind mounts
# Good: -v $(pwd)/src:/app/src
# Bad:  -v $(pwd):/app (if $(pwd) has many nested directories)
```

## Clean Up

### Remove All Lab Resources

```bash
# Stop all containers
docker stop $(docker ps -aq)

# Remove containers
docker rm $(docker ps -aq)

# Remove volumes created in lab
docker volume rm my-persistent-data shared-storage mysql-data mysql-restored

# Remove backup files
rm -f mysql-backup-*.tar.gz

# Clean up development directory
rm -rf ~/docker-lab/webapp

# Verify cleanup
docker volume ls
docker ps -a
```

## Learning Outcomes Checklist

By completing this lab, you should understand:

- [ ] Container filesystem limitations and ephemeral nature
- [ ] Difference between named volumes and bind mounts
- [ ] Data persistence across container lifecycle
- [ ] Volume sharing between multiple containers
- [ ] Database data persistence strategies
- [ ] Volume backup and restore procedures
- [ ] Performance implications of different mount types
- [ ] Common storage patterns for development and production

## Real-World Applications

### Development Workflow

- Source code bind mounts for live editing
- Configuration file mounts for testing
- Database volumes for development data persistence

### Production Deployment

- Named volumes for application data
- Database volumes with backup strategies
- Log volumes for centralized logging
- Configuration volumes for environment-specific settings

### Data Pipeline

- Shared volumes between processing stages
- Input/output volumes for batch processing
- Temporary volumes for intermediate data

## Next Steps

This lab covered Docker storage fundamentals. In Lab 5, you'll combine networking (Lab 3) and storage (Lab 4) concepts when building multi-container applications with Docker Compose. Understanding these storage patterns is crucial for creating stateful applications that persist data correctly.

## Resources

- [Docker Volumes Documentation](https://docs.docker.com/storage/volumes/)
- [Bind Mounts Guide](https://docs.docker.com/storage/bind-mounts/)
- [Storage Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Volume Backup Strategies](https://docs.docker.com/storage/volumes/#backup-restore-or-migrate-data-volumes)
