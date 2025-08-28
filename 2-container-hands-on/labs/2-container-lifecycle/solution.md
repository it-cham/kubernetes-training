# Lab 2: Basic Container Operations

## Objective

Master fundamental Docker container operations including running, managing, and interacting with containers using the nginx web server as a practical example.

## Prerequisites

- Completed Lab 1: Docker Installation & Verification
- Docker running and accessible via command line
- Basic command line knowledge

## Learning Goals

By the end of this lab, you will:

- Run containers in foreground and background modes
- Map container ports to host ports
- Execute commands inside running containers
- Manage container lifecycle (start, stop, remove)
- View container logs and processes
- Understand container naming and identification

## Container Lifecycle Overview

Understanding the container lifecycle is essential for effective Docker usage:

1. **Pull**: Download image from registry
2. **Create**: Create container from image
3. **Start**: Start the container process
4. **Run**: Create and start in one command
5. **Stop**: Gracefully stop the container
6. **Kill**: Forcefully terminate the container
7. **Remove**: Delete the container

## Lab Exercises

### Exercise 1: Image Management and Basic Container Execution

1. **List current images:**

   ```bash
   docker images
   ```

   This shows locally available images.

2. **Pull the nginx image:**

   ```bash
   docker pull nginx:latest
   ```

   Downloads the official nginx web server image.

3. **Verify the image was downloaded:**

   ```bash
   docker images
   ```

   You should see `nginx:latest` in the list.

4. **Run nginx in foreground mode:**

   ```bash
   docker run nginx
   ```

   **Observations:**
   - Container starts and runs in foreground
   - Logs appear directly in terminal
   - Press `Ctrl+C` to stop the container
   - Container exits when you interrupt it

5. **Check container status:**

   ```bash
   # View running containers
   docker ps

   # View all containers (including stopped)
   docker ps -a
   ```

### Exercise 2: Background Execution

1. **Run nginx in background (detached mode):**

   ```bash
   docker run -d nginx
   ```

   **Key Concepts:**
   - `-d` flag runs container in background (detached)
   - Returns container ID immediately
   - Container continues running in background

2. **Check running containers:**

   ```bash
   docker ps
   ```

   **Output explanation:**
   - `CONTAINER ID`: Short ID for the container
   - `IMAGE`: Image used to create container
   - `COMMAND`: Default command running in container
   - `CREATED`: When container was created
   - `STATUS`: Current status (Up/Exited)
   - `PORTS`: Port mappings (currently none)
   - `NAMES`: Auto-generated name

3. **Access the container:**

   ```bash
   curl http://localhost:80
   # This fails because port 80 isn't mapped to host
   ```

4. **Stop the container:**

   ```bash
   # Use container ID (first few characters are sufficient)
   docker stop [CONTAINER_ID]

   # Or use the auto-generated name
   docker stop [CONTAINER_NAME]
   ```

5. **Remove the stopped container:**

   ```bash
   docker rm [CONTAINER_ID]
   ```

### Exercise 3: Port Mapping and Named Containers

1. **Run nginx with port mapping and custom name:**

   ```bash
   docker run -d -p 8080:80 --name my-web-server nginx
   ```

   **Parameter explanation:**
   - `-d`: Detached/background mode
   - `-p 8080:80`: Map host port 8080 to container port 80
   - `--name my-web-server`: Give container a friendly name
   - `nginx`: Image to use

2. **Verify port mapping:**

   ```bash
   docker ps
   ```

   You should see `0.0.0.0:8080->80/tcp` in the PORTS column.

3. **Test web server access:**

   ```bash
   # Using curl
   curl http://localhost:8080

   # Or open in browser: http://localhost:8080
   ```

   You should see the nginx welcome page.

4. **View container logs:**

   ```bash
   docker logs my-web-server
   ```

   Shows nginx access logs and any error messages.

5. **Follow logs in real-time:**

   ```bash
   docker logs -f my-web-server
   ```

   Use `Ctrl+C` to stop following logs.

### Exercise 4: Container Interaction and File System

1. **Execute commands inside running container:**

   ```bash
   docker exec my-web-server ls /usr/share/nginx/html
   ```

   Lists files in nginx's web document root.

2. **Start interactive shell in container:**

   ```bash
   docker exec -it my-web-server bash
   ```

   **Parameter explanation:**
   - `-i`: Interactive mode (keep STDIN open)
   - `-t`: Allocate pseudo-TTY (terminal)
   - `bash`: Command to run (bash shell)

3. **Explore container file system (inside container):**

   ```bash
   # Check current directory
   pwd

   # List nginx configuration files
   ls -la /etc/nginx/

   # View nginx configuration
   cat /etc/nginx/nginx.conf

   # Check web document root
   ls -la /usr/share/nginx/html/

   # View default web page
   cat /usr/share/nginx/html/index.html
   ```

4. **Modify web content (inside container):**

   ```bash
   # Create custom page
   echo "<h1>Hello from Docker!</h1>" > /usr/share/nginx/html/hello.html

   # Exit container shell
   exit
   ```

5. **Test custom content:**

   ```bash
   curl http://localhost:8080/hello.html
   ```

   Should display your custom HTML.

### Exercise 5: Container Process Management

1. **View running processes in container:**

   ```bash
   docker exec my-web-server ps aux
   ```

   Shows processes running inside the container.

2. **Check container resource usage:**

   ```bash
   docker stats my-web-server
   ```

   **Metrics displayed:**
   - CPU usage percentage
   - Memory usage and limit
   - Network I/O
   - Block I/O (disk)

   Press `Ctrl+C` to exit stats view.

3. **Inspect container configuration:**

   ```bash
   docker inspect my-web-server
   ```

   This shows comprehensive container information:
   - Network settings
   - Volume mounts
   - Environment variables
   - Process configuration

4. **View container's port mappings:**

   ```bash
   docker port my-web-server
   ```

### Exercise 6: Multiple Container Management

1. **Start a second nginx container:**

   ```bash
   docker run -d -p 8081:80 --name my-second-server nginx
   ```

2. **View all running containers:**

   ```bash
   docker ps
   ```

3. **Test both servers:**

   ```bash
   curl http://localhost:8080
   curl http://localhost:8081
   ```

4. **Compare container differences:**

   ```bash
   # Check different container IDs and names
   docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Ports}}"
   ```

5. **Stop all nginx containers:**

   ```bash
   docker stop my-web-server my-second-server
   ```

6. **Remove all containers:**

   ```bash
   docker rm my-web-server my-second-server
   ```

### Exercise 7: Container Lifecycle Operations

1. **Create container without starting:**

   ```bash
   docker create -p 8080:80 --name lifecycle-demo nginx
   ```

2. **Check container status:**

   ```bash
   docker ps -a
   ```

   Container shows as "Created" status.

3. **Start the created container:**

   ```bash
   docker start lifecycle-demo
   ```

4. **Stop the container gracefully:**

   ```bash
   docker stop lifecycle-demo
   ```

   **Note**: `stop` sends SIGTERM, allows graceful shutdown.

5. **Force kill container (if needed):**

   ```bash
   docker kill lifecycle-demo
   ```

   **Note**: `kill` sends SIGKILL, immediate termination.

6. **Restart container:**

   ```bash
   docker restart lifecycle-demo
   ```

7. **Clean up:**

   ```bash
   docker stop lifecycle-demo
   docker rm lifecycle-demo
   ```

## Command Reference

### Essential Container Commands

| Command          | Purpose                      | Example                               |
| ---------------- | ---------------------------- | ------------------------------------- |
| `docker run`     | Create and start container   | `docker run -d -p 8080:80 nginx`      |
| `docker ps`      | List running containers      | `docker ps`                           |
| `docker ps -a`   | List all containers          | `docker ps -a`                        |
| `docker stop`    | Stop container gracefully    | `docker stop container_name`          |
| `docker start`   | Start stopped container      | `docker start container_name`         |
| `docker restart` | Restart container            | `docker restart container_name`       |
| `docker rm`      | Remove container             | `docker rm container_name`            |
| `docker exec`    | Execute command in container | `docker exec -it container_name bash` |
| `docker logs`    | View container logs          | `docker logs container_name`          |
| `docker inspect` | Detailed container info      | `docker inspect container_name`       |

### Common Flags

| Flag     | Purpose              | Usage                            |
| -------- | -------------------- | -------------------------------- |
| `-d`     | Detached mode        | `docker run -d nginx`            |
| `-p`     | Port mapping         | `docker run -p 8080:80 nginx`    |
| `--name` | Container name       | `docker run --name myapp nginx`  |
| `-it`    | Interactive terminal | `docker exec -it container bash` |
| `-f`     | Follow logs          | `docker logs -f container`       |

## Troubleshooting

### Common Issues and Solutions

**Port already in use:**

```bash
Error: bind: address already in use
```

Solution: Use different host port or stop conflicting service.

**Container name already exists:**

```bash
Error: container name "myapp" already in use
```

Solution: Remove existing container or use different name.

**Cannot connect to Docker daemon:**

```bash
Cannot connect to the Docker daemon. Is the docker daemon running?
```

Solution: Start Docker service or Docker Desktop.

**Permission denied (Linux):**

```bash
permission denied while trying to connect to Docker daemon
```

Solution: Add user to docker group or use sudo.

### Diagnostic Commands

```bash
# Check Docker daemon status
docker system info

# Check Docker version
docker version

# View system-wide Docker information
docker system df

# Clean up unused resources
docker system prune
```

## Best Practices

1. **Always name your containers** for easier management
2. **Use specific image tags** instead of `latest` in production
3. **Stop containers gracefully** with `docker stop` before removing
4. **Clean up unused containers** regularly to save space
5. **Use port mapping** to avoid conflicts
6. **Check logs** when troubleshooting container issues

## Security Considerations

- Containers run as root by default (security implication)
- Port mappings expose services to host network
- Container processes are isolated but share kernel
- File system changes are lost when container is removed

## Learning Outcomes Checklist

By completing this lab, you should be able to:

- [ ] Run containers in foreground and background modes
- [ ] Map container ports to host system
- [ ] Execute commands inside running containers
- [ ] View and follow container logs
- [ ] Manage container lifecycle (start, stop, remove)
- [ ] Name containers for easier reference
- [ ] Understand container isolation and resource usage
- [ ] Troubleshoot common container issues

## Next Steps

This lab covered basic container operations with a single container. In Lab 3, you'll learn about container networking and communication between multiple containers, followed by persistent storage in Lab 4.

## Additional Practice

Try these challenges to reinforce your learning:

1. **Multi-port Application**: Run nginx with multiple port mappings
2. **Custom Configuration**: Mount custom nginx.conf into container
3. **Process Monitoring**: Use `docker stats` to monitor resource usage
4. **Log Analysis**: Generate traffic and analyze nginx access logs
5. **Container Comparison**: Compare resource usage of different web servers (nginx, apache, lighttpd)

## Resources

- [Docker Run Command Reference](https://docs.docker.com/engine/reference/commandline/run/)
- [Docker Exec Command Reference](https://docs.docker.com/engine/reference/commandline/exec/)
- [Nginx Docker Image Documentation](https://hub.docker.com/_/nginx)
- [Docker Container Networking](https://docs.docker.com/network/)
