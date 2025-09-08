## Lab: Docker Compose to Kubernetes Migration

### Your Tasks

1. **Analyze the existing Docker Compose application** and understand service dependencies
2. **Generate Kubernetes Deployment manifests** using kubectl --dry-run commands
3. **Create Service manifests** to enable inter-pod communication
4. **Migrate environment variables and configuration** from Docker Compose to Kubernetes
5. **Deploy the application to your k3s cluster** and verify functionality
6. **Test application connectivity** and data persistence
7. **Compare operational differences** between Docker Compose and Kubernetes

### Challenge Questions

- How do you convert Docker Compose service names to Kubernetes Service discovery?
- What's the difference between Docker Compose volumes and Kubernetes storage?
- How does scaling work differently in Kubernetes compared to Docker Compose?
- What kubectl commands replace common docker compose operations?

### Success Criteria

- [ ] WordPress deployment running successfully in Kubernetes
- [ ] MySQL database accessible from WordPress pods
- [ ] WordPress installation wizard completes successfully
- [ ] Application data persists when pods are restarted
- [ ] Can scale WordPress deployment and observe load balancing
- [ ] Understand the differences between Docker Compose and Kubernetes approaches
