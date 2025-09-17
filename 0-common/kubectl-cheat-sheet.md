# kubectl Cheat Sheet

## Cluster Information & Health

```shell
# Check cluster status
kubectl cluster-info

# Verify node is ready
kubectl get nodes

# Confirm kubectl configuration
kubectl config current-context

# Detailed node information
kubectl describe node <NODE_NAME>

# Component readiness
kubectl get --raw='/readyz?verbose'

# System resource usage
kubectl top nodes
kubectl top pods -n kube-system
```

## Namespaces

```shell
# View all namespaces
kubectl get namespaces

# List system pods
kubectl get pods --all-namespaces

# Focus on control plane components
kubectl get pods -n kube-system
```

## Pods

```shell
# List pods
kubectl get pods

# List pods with additional details
kubectl get pods -o wide

# Watch pods being created/updated
kubectl get pods -w

# Get pod details and events
kubectl describe pod <POD_NAME>

# View pod logs
kubectl logs <POD_NAME>

# Delete specific pod
kubectl delete pod <POD_NAME>
```

## Deployments

```shell
# Create deployment
kubectl create deployment <NAME> --image=<IMAGE>

# Get deployments
kubectl get deployments

# View deployment details
kubectl describe deployment <DEPLOYMENT_NAME>

# Scale deployment
kubectl scale deployment <DEPLOYMENT_NAME> --replicas=<NUMBER>

# Delete deployment
kubectl delete deployment <DEPLOYMENT_NAME>

# Set environment variables
kubectl set env deployment/<DEPLOYMENT_NAME> KEY=value

# Update deployment image
kubectl set image deployment/<DEPLOYMENT_NAME> <CONTAINER>=<NEW_IMAGE>

# Edit deployment interactively
kubectl edit deployment <DEPLOYMENT_NAME>

# Patch deployment (e.g., resource limits)
kubectl patch deployment <DEPLOYMENT_NAME> -p '{"spec":{"template":{"spec":{"containers":[{"name":"<CONTAINER>","resources":{"limits":{"cpu":"100m","memory":"128Mi"}}}]}}}}'
```

## Services

```shell
# Expose deployment as NodePort service
kubectl expose deployment <DEPLOYMENT_NAME> --port=<PORT> --type=NodePort

# Get services
kubectl get services

# Check service details
kubectl describe service <SERVICE_NAME>

# List service endpoints
kubectl get endpoints <SERVICE_NAME>

# Get endpoint slices
kubectl get endpointslices

# Delete service
kubectl delete service <SERVICE_NAME>
```

## Rolling Updates & Rollbacks

```shell
# Monitor rollout status
kubectl rollout status deployment/<DEPLOYMENT_NAME>

# View rollout history
kubectl rollout history deployment/<DEPLOYMENT_NAME>

# Rollback deployment
kubectl rollout undo deployment/<DEPLOYMENT_NAME>
```

## Resource Management

```shell
# Pod resource consumption
kubectl top pods

# Namespace resource usage
kubectl top pods --all-namespaces

# Resource usage for specific namespace
kubectl top pods -n <NAMESPACE>
```

## Troubleshooting Commands

### Pod Issues

```shell
# Check pod events and status
kubectl describe pod <POD_NAME>

# View pod logs
kubectl logs <POD_NAME>

# Check cluster events (sorted by time)
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Service Connectivity

```shell
# Verify service configuration
kubectl get services
kubectl describe service <SERVICE_NAME>

# Check service endpoints (internal)
kubectl get endpointslices

# Test connectivity from temporary pod
kubectl run test-pod --image=busybox -it --rm -- /bin/sh
# Inside pod: wget -qO- http://<service-name>

# Debug existing pod
kubectl debug -it <TARGET_POD> --image=busybox --target=<TARGET_CONTAINER>
```

### General Debugging

| Issue | Command | Purpose |
|-------|---------|---------|
| Pod not starting | `kubectl describe pod <POD_NAME>` | Check events and configuration |
| Application errors | `kubectl logs <POD_NAME>` | View application output |
| Service not accessible | `kubectl describe service <SERVICE_NAME>` | Verify service configuration |
| Resource constraints | `kubectl top pods` | Check resource usage |
| Network connectivity | `kubectl get endpointslices` | Verify service endpoints |

## Cleanup Commands

```shell
# Remove specific deployments
kubectl delete deployment <DEPLOYMENT_NAME>

# Remove associated services
kubectl delete service <SERVICE_NAME>

# Verify cleanup
kubectl get deployments
kubectl get services
kubectl get pods
```

## Quick Reference: Docker to Kubernetes

| Task | Docker | kubectl |
|------|--------|---------|
| List containers | `docker ps` | `kubectl get pods` |
| Run container | `docker run -d --name <name> -p <port>:<port> <image>` | `kubectl create deployment <name> --image=<image>` |
| View logs | `docker logs <container>` | `kubectl logs <pod>` |
| Stop/Remove | `docker stop <container> && docker rm <container>` | `kubectl delete deployment <name>` |

## Common Image Tags for Testing

```shell
# Nginx web server
kubectl create deployment nginx --image=nginx:latest

# Apache HTTP server
kubectl create deployment httpd --image=httpd:latest

# Busybox for debugging
kubectl run test-pod --image=busybox -it --rm -- /bin/sh
```
