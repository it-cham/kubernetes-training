# Lab 1: Docker Installation & Verification

## Objective

Install Docker on your local machine and verify the installation is working correctly.

## Prerequisites

- Administrative/sudo privileges on your machine
- Stable internet connection
- Meeting system requirements for your operating system

## System Requirements

### Windows 10/11

- Windows 10/11 64-bit: Pro, Enterprise (Build 1903 or higher)
- BIOS-level hardware virtualization support enabled
- WSL 2 feature enabled
- 4GB system RAM minimum

### Linux (Ubuntu/Debian)

- Ubuntu 22.04+
- Debian 12+

## Installation Steps

### Windows Installation

1. **Download Docker Desktop**
   - Visit <https://www.docker.com/products/docker-desktop>
   - Download Docker Desktop for Windows
   - Run the installer with administrator privileges

2. **Enable WSL 2 (if not already enabled)**

   ```powershell
   # Run in PowerShell as Administrator
   dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
   dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
   ```

3. **Restart your computer**

4. **Start Docker Desktop**
   - Launch Docker Desktop from Start Menu
   - Wait for Docker to start (may take a few minutes on first run)

### macOS Installation

1. **Download Docker Desktop**
   - Visit <https://www.docker.com/products/docker-desktop>
   - Choose the correct version for your chip (Intel or Apple Silicon)
   - Open the downloaded DMG file

2. **Install Docker Desktop**
   - Drag Docker to Applications folder
   - Launch Docker from Applications
   - Follow the setup wizard

3. **Grant Permissions**
   - Enter your password when prompted for privileged access

### Linux Installation (Ubuntu)

1. **Update package index**

   ```bash
   sudo apt-get update
   ```

2. **Install required packages**

   ```bash
   sudo apt-get install \
       ca-certificates \
       curl \
       gnupg \
       lsb-release
   ```

3. **Clean up old installations**

   ```bash
   for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
   ```

4. **Add Docker's official GPG key**

   ```bash
   # Add Docker's official GPG key:
   sudo apt-get update
   sudo apt-get install ca-certificates curl
   sudo install -m 0755 -d /etc/apt/keyrings
   sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
   sudo chmod a+r /etc/apt/keyrings/docker.asc

   # Add the repository to Apt sources:
   echo \
   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
   $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   sudo apt-get update
   ```

5. **Install Docker Engine**

   ```bash
   sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   ```

6. **Add user to docker group**

   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   ```

## Verification Steps

### 1. Check Docker Version

```bash
docker --version
```

Expected output similar to:

```
Docker version 28.0.x, build xxxxxxx
```

### 2. Check Docker Compose Version

```bash
docker compose version
```

Expected output similar to:

```
Docker Compose version v2.x.x
```

### 3. Verify Docker Daemon is Running

```bash
docker system info
```

This should display system-wide information about Docker installation.

### 4. Run Hello World Container

```bash
docker run hello-world
```

Expected output should include:

```plaintext
Hello from Docker!
This message shows that your installation appears to be working correctly.
...
```

### 5. List Docker Images

```bash
docker image ls
```

You should see the hello-world image listed.

### 6. Check Running Containers

```bash
docker ps
```

Should show no running containers (hello-world exits immediately).

### 7. Check All Containers (including stopped)

```bash
docker ps -a
```

Should show the hello-world container in "Exited" status.

## Troubleshooting Common Issues

### Windows Issues

**WSL 2 not enabled:**

- Enable Windows Subsystem for Linux
- Install WSL 2 kernel update
- Set WSL 2 as default version

**Hyper-V conflicts:**

- Disable VirtualBox or VMware if running
- Enable Hyper-V in Windows Features

**Permission errors:**

- Ensure you're running as Administrator
- Check Docker Desktop is running

### macOS Issues

**Permission denied errors:**

- Ensure Docker Desktop has necessary permissions
- Try restarting Docker Desktop

**Resource allocation:**

- Increase Docker Desktop resource limits in preferences
- Ensure sufficient disk space

### Linux Issues

**Permission denied errors:**

```bash
sudo usermod -aG docker $USER
newgrp docker
# Or restart your session
```

**Docker daemon not running:**

```bash
sudo systemctl start docker
sudo systemctl enable docker
```

**Network connectivity:**

```bash
# Check if Docker daemon is accessible
docker version
# If client can connect to daemon
```

### Corporate Network Issues

**Proxy configuration:**

- Configure Docker Desktop proxy settings
- Set HTTP_PROXY and HTTPS_PROXY environment variables

**Firewall restrictions:**

- Whitelist Docker Hub (registry-1.docker.io)
- Allow Docker daemon ports (2375, 2376)

## Clean Up (Optional)

If you want to remove the hello-world container and image:

```bash
# Remove container
docker rm $(docker ps -aq -f "ancestor=hello-world")

# Remove image
docker rmi hello-world
```

## Success Criteria

You have successfully completed this lab when:

- [ ] Docker version command returns version information
- [ ] Docker-compose version command works
- [ ] Hello-world container runs successfully
- [ ] You can list Docker images and containers
- [ ] No permission errors when running Docker commands

## Next Steps

Once your Docker installation is verified, you're ready to proceed to Lab 2: Basic Container Operations.

## Additional Resources

- [Docker Desktop Documentation](https://docs.docker.com/desktop/)
- [Docker Engine Installation](https://docs.docker.com/engine/install/)
- [Docker Get Started Guide](https://docs.docker.com/get-started/)
- [WSL 2 Installation Guide](https://docs.microsoft.com/en-us/windows/wsl/install)
