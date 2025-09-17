
# Lab 3: Container Networking & Communication

## Objective

Understand Docker networking fundamentals, including container-to-container communication, network isolation, and custom network creation.

## Prerequisites

- Completed Lab 2: Basic Container Operations
- Understanding of basic networking concepts (IP addresses, ports)
- Docker installed and running

## Learning Goals

By the end of this lab, you will:

- Understand Docker's default networking behavior
- Create and manage custom Docker networks
- Enable container-to-container communication
- Implement network isolation for security
- Use container names for service discovery

## Docker Networking Overview

Docker provides several network drivers:

- **bridge**: Default network driver for containers on single host
- **host**: Remove network isolation between container and host
- **none**: Disable all networking
- **overlay**: Enable swarm services to communicate across nodes
- **macvlan**: Assign MAC address to container

This lab focuses on bridge networks, the most common scenario.

## Lab Exercises

### Exercise 1: Explore Default Network Behavior

1. **List existing networks:**

   ```bash
   docker network ls
   ```

   **Expected output:**

   ```plaintext
   NETWORK ID     NAME      DRIVER    SCOPE
   xxxxxxxxxxxx   bridge    bridge    local
   xxxxxxxxxxxx   host      host      local
   xxxxxxxxxxxx   none      null      local
   ```

2. **Inspect the default bridge network:**

   ```bash
   docker network inspect bridge
   ```

   Note the subnet range (typically 172.17.0.0/16) and gateway.

3. **Run two containers on default network:**

   ```bash
   # Start first container
   docker run -d --name web1 nginx:stable

   # Start second container
   docker run -d --name web2 nginx:stable
   ```

4. **Check container IP addresses:**

   ```bash
   # Get web1 IP address
   docker inspect web1 --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

   # Get web2 IP address
   docker inspect web2 --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
   ```

5. **Test connectivity using IP addresses:**

   ```bash
   # From web1, ping web2 using IP address
   docker exec web1 ping -c 3 [WEB2_IP_ADDRESS]

   # From web2, ping web1 using IP address
   docker exec web2 ping -c 3 [WEB1_IP_ADDRESS]
   ```

6. **Test name resolution (this will fail):**

   ```bash
   # Try to ping by container name (default bridge doesn't support this)
   docker exec web1 ping -c 3 web2
   # Expected: ping: web2: Name or service not known
   ```

7. **Clean up:**

   ```bash
   docker stop web1 web2
   docker rm web1 web2
   ```

### Exercise 2: Create Custom Bridge Network

1. **Create custom network:**

   ```bash
   docker network create --driver bridge my-app-network
   ```

2. **Inspect custom network:**

   ```bash
   docker network inspect my-app-network
   ```

   Note the different subnet range (typically 172.18.x.x or higher).

3. **Run containers on custom network:**

   ```bash
   # Start containers on custom network
   docker run -d --name app1 --network my-app-network nginx:stable
   docker run -d --name app2 --network my-app-network nginx:stable
   ```

4. **Test name-based communication:**

   ```bash
   # Test ping by container name (this works on custom networks)
   docker exec app1 /bin/sh -c 'apt-get update && apt-get install -y iputils-ping && ping -c 3 app2'
   ```

5. **Test HTTP communication:**

   ```bash
   # Install curl in one container and test HTTP communication
   docker exec app1 /bin/sh -c 'apt-get update && apt-get install -y curl && curl http://app2'
   ```

### Exercise 3: Network Isolation Demonstration

1. **Create two isolated networks:**

   ```bash
   docker network create frontend-net
   docker network create backend-net
   ```

2. **Deploy containers on different networks:**

   ```bash
   # Frontend containers
   docker run -d --name frontend1 --network frontend-net nginx:stable
   docker run -d --name frontend2 --network frontend-net nginx:stable

   # Backend containers
   docker run -d --name backend1 --network backend-net nginx:stable
   docker run -d --name backend2 --network backend-net nginx:stable
   ```

3. **Test within-network communication:**

   ```bash
   # Frontend containers can communicate
   docker exec frontend1 ping -c 3 frontend2

   # Backend containers can communicate
   docker exec backend1 ping -c 3 backend2
   ```

4. **Test cross-network isolation:**

   ```bash
   # Frontend cannot reach backend (should fail)
   docker exec frontend1 ping -c 3 backend1
   # Expected: ping: backend1: Name or service not known
   ```

### Exercise 4: Multi-Network Container (Gateway Pattern) - Optional

1. **Create a gateway container connected to both networks:**

   ```bash
   # Start container on frontend network
   docker run -d --name gateway --network frontend-net nginx:stable

   # Connect same container to backend network
   docker network connect backend-net gateway
   ```

2. **Verify gateway has access to both networks:**

   ```bash
   # Gateway can reach frontend
   docker exec gateway ping -c 3 frontend1

   # Gateway can reach backend
   docker exec gateway ping -c 3 backend1
   ```

3. **Inspect gateway network configuration:**

   ```bash
   docker inspect gateway --format='{{json .NetworkSettings.Networks}}' | jq
   ```

   The gateway container should have IP addresses in both networks.

### Exercise 5: Port Mapping and External Access

1. **Create web application with database simulation:**

   ```bash
   # Create application network
   docker network create app-tier

   # Database (no external port needed)
   docker run -d --name database --network app-tier \
     -e POSTGRES_DB=myapp \
     -e POSTGRES_USER=user \
     -e POSTGRES_PASSWORD=password \
     postgres:16-alpine

   # Web application (external port mapped)
   docker run -d --name webapp --network app-tier -p 8080:80 nginx:stable
   ```

2. **Test internal communication:**

   ```bash
   # Web app can reach database internally
   docker exec webapp ping -c 3 database
   ```

3. **Test external access:**

   ```bash
   # External access to web app
   curl http://localhost:8080

   # Database is NOT externally accessible (no port mapping)
   # curl http://localhost:5432  # This would fail
   ```

### Exercise 6: Network Troubleshooting and Inspection

1. **Install network utilities in container:**

   ```bash
   # Create debugging container with network tools
   docker run -it --name netdebug --network app-tier ubuntu bash

   # Inside container, install tools:
   apt-get update
   apt-get install -y iputils-ping curl dnsutils netcat
   ```

2. **Network diagnostic commands:**

   ```bash
   # Inside netdebug container:

   # Check network interface
   ip addr show

   # Check routing table
   ip route show

   # Test DNS resolution
   nslookup webapp
   nslookup database

   # Test port connectivity
   nc -zv webapp 80
   nc -zv database 5432

   # Exit container
   exit
   ```

3. **External network inspection:**

   ```bash
   # List all networks
   docker network ls

   # Show containers on specific network
   docker network inspect app-tier --format='{{json .Containers}}' | jq

   # Show network connectivity
   docker inspect webapp --format='{{json .NetworkSettings.Networks}}'
   ```

## Practical Scenarios

### Scenario 1: Multi-Tier Application Architecture

```bash
# Create networks for different tiers
docker network create frontend-tier
docker network create backend-tier
docker network create database-tier

# Database (most isolated)
docker run -d --name db --network database-tier postgres:17-alpine

# API Server (backend and database access)
docker run -d --name api --network backend-tier nginx:stable
docker network connect database-tier api

# Web Server (frontend and backend access)
docker run -d --name web --network frontend-tier -p 80:80 nginx:stable
docker network connect backend-tier web

# Test connectivity
docker exec web ping api      # Should work
docker exec api ping db       # Should work
docker exec web ping db       # Should fail (isolated)
```

### Scenario 2: Load Balancer Setup

```bash
# Create network for load balancer scenario
docker network create lb-network

# Start multiple backend servers
docker run -d --name backend1 --network lb-network nginx:stable
docker run -d --name backend2 --network lb-network nginx:stable
docker run -d --name backend3 --network lb-network nginx:stable

# Load balancer can reach all backends
docker run -d --name loadbalancer --network lb-network -p 8080:80 nginx:stable

# Test connectivity from load balancer
docker exec loadbalancer ping backend1
docker exec loadbalancer ping backend2
docker exec loadbalancer ping backend3
```

## Network Configuration Options

### Custom Network with Specific Subnet

```bash
# Create network with custom subnet
docker network create --subnet=192.168.100.0/24 \
  --gateway=192.168.100.1 \
  custom-subnet-net

# Run container with specific IP
docker run -d --name static-ip --network custom-subnet-net \
  --ip=192.168.100.10 nginx:stable
```

### Network with DNS Options

```bash
# Create network with custom DNS
docker network create --dns=8.8.8.8 --dns=8.8.4.4 dns-net

# Container will use specified DNS servers
docker run -d --name dns-test --network dns-net nginx:stable
```

## Command Reference

### Network Management Commands

| Command                     | Purpose                      | Example                                      |
| --------------------------- | ---------------------------- | -------------------------------------------- |
| `docker network ls`         | List networks                | `docker network ls`                          |
| `docker network create`     | Create network               | `docker network create mynet`                |
| `docker network rm`         | Remove network               | `docker network rm mynet`                    |
| `docker network inspect`    | Network details              | `docker network inspect bridge`              |
| `docker network connect`    | Connect container to network | `docker network connect mynet container1`    |
| `docker network disconnect` | Disconnect container         | `docker network disconnect mynet container1` |

### Container Network Commands

| Command                | Purpose                | Example                                     |
| ---------------------- | ---------------------- | ------------------------------------------- |
| `docker run --network` | Specify network        | `docker run --network mynet nginx:stable`   |
| `docker run --ip`      | Set static IP          | `docker run --ip 192.168.1.10 nginx:stable` |
| `docker inspect`       | Container network info | `docker inspect container1`                 |

## Troubleshooting

### Common Issues

**Container cannot resolve other container names:**

- Ensure containers are on same custom network (not default bridge)
- Check network connectivity with `docker network inspect`

**Port conflicts:**

- Use different host ports: `-p 8081:80` instead of `-p 8080:80`
- Check which ports are in use: `docker ps` or `netstat -tlnp`

**Network isolation not working:**

- Verify containers are on different networks
- Check for multi-network connections with `docker inspect`

**DNS resolution failures:**

- Custom networks provide automatic DNS resolution
- Default bridge network only supports IP-based communication

### Diagnostic Commands

```bash
# Check container network configuration
docker inspect <container> --format='{{json .NetworkSettings}}'

# List containers on specific network
docker network inspect <network> --format='{{json .Containers}}'

# Check port mappings
docker port <container>

# Monitor network traffic (requires privileged mode)
docker run --rm --net container:<container> nicolaka/netshoot tcpdump -i eth0
```

## Clean Up

### Remove All Lab Containers and Networks

```bash
# Stop and remove all containers
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)

# Remove custom networks
docker network rm my-app-network frontend-net backend-net app-tier \
  frontend-tier backend-tier database-tier lb-network

# Verify cleanup
docker network ls
docker ps -a
```

## Learning Outcomes Checklist

By completing this lab, you should understand:

- [ ] Default Docker bridge network behavior
- [ ] Difference between default bridge and custom networks
- [ ] Container name resolution in custom networks
- [ ] Network isolation for security
- [ ] Multi-network container connections
- [ ] Port mapping for external access
- [ ] Network troubleshooting techniques
- [ ] Common networking patterns (gateway, load balancer)

## Best Practices

1. **Use custom networks** instead of default bridge for multi-container apps
2. **Implement network segmentation** for security (frontend/backend/database tiers)
3. **Minimize external port exposure** - only map ports that need external access
4. **Use meaningful network names** that reflect their purpose
5. **Document network architecture** for complex multi-tier applications
6. **Test network connectivity** during development and deployment

## Next Steps

This lab covered Docker networking fundamentals. In Lab 4, you'll learn about persistent storage with Docker volumes, which complements networking to create stateful, communicating applications. Together, these concepts form the foundation for understanding Docker Compose in Labs 5-6.

## Resources

- [Docker Networking Overview](https://docs.docker.com/network/)
- [Bridge Network Driver](https://docs.docker.com/network/bridge/)
- [Network Troubleshooting](https://docs.docker.com/network/troubleshooting/)
- [Container Networking Best Practices](https://docs.docker.com/network/bridge/#best-practices)
