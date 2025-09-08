# Lab: Docker Compose to Kubernetes Migration

## Objective

Convert an existing Docker Compose application (WordPress + MySQL) to Kubernetes using manifest files and kubectl commands.
Learn the migration process, differences in operational models, and Kubernetes-native approaches to application deployment.

## Prerequisites

- Completed k3s setup
- k3s cluster running
- Basic understanding of Kubernetes objects (Pods, Deployments, Services)

## Application Overview

We'll migrate a two-tier WordPress application:

- **WordPress**: PHP web application (frontend)
- **MySQL**: Database backend
- **Dependencies**: WordPress connects to MySQL via service name
- **Storage**: MySQL requires persistent data storage
- **Networking**: WordPress needs external access, MySQL internal only

---

## Phase 1: Analyze Docker Compose Application (15 minutes)

### Examine the Original Docker Compose File

**Starting point (`docker-compose.yml`):**

### Identify Migration Requirements

**Service Analysis:**

1. **MySQL Service (`db`)**:
   - Needs persistent storage
   - Requires environment variables for configuration
   - Internal access only (no ports exposed)
   - Service name used for hostname resolution

2. **WordPress Service**:
   - Depends on MySQL being available
   - Needs external access (port 8000)
   - Connects to MySQL using service name `db`
   - Requires database configuration via environment variables

**Kubernetes Translation Needs:**

- 2 Deployments (one per service)
- 2 Services (for networking and discovery)
- 1 PersistentVolumeClaim (for MySQL data)
- Environment variable migration
- Service name mapping (`db` → `mysql-service`)

---

## Phase 2: Generate Kubernetes Manifests (25 minutes)

### Step 1: Create MySQL Deployment

**Generate base manifest:**

```bash
kubectl create deployment mysql --image=mysql:8.4.6 --dry-run=client -o yaml > mysql-deployment.yaml
```

**Edit `mysql-deployment.yaml` to add configuration:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: mysql
  name: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - image: mysql:8.4.6
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: somewordpress
        - name: MYSQL_DATABASE
          value: wordpress
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc
```

### Step 2: Create MySQL PersistentVolumeClaim

**Generate PVC manifest:**

```bash
# Create PVC manifest manually (no kubectl generator for PVC)
cat > mysql-pvc.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

### Step 3: Create MySQL Service

**Generate Service manifest:**

```bash
kubectl create service clusterip mysql --tcp=3306:3306 --dry-run=client -o yaml > mysql-service.yaml
```

**Edit `mysql-service.yaml` to match deployment labels:**

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: mysql
  name: mysql
spec:
  ports:
  - name: "3306"
    port: 3306
    protocol: TCP
    targetPort: 3306
  selector:
    app: mysql
  type: ClusterIP
```

### Step 4: Create WordPress Deployment

**Generate base manifest:**

```bash
kubectl create deployment wordpress --image=wordpress:latest --dry-run=client -o yaml > wordpress-deployment.yaml
```

**Edit `wordpress-deployment.yaml` to add configuration:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: wordpress
  name: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - image: wordpress:latest
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql  # Service name for discovery
        - name: WORDPRESS_DB_USER
          value: root
        - name: WORDPRESS_DB_PASSWORD
          value: somewordpress
        - name: WORDPRESS_DB_NAME
          value: wordpress
        ports:
        - containerPort: 80
```

### Step 5: Create WordPress Service

**Generate NodePort Service for external access:**

```bash
kubectl create service nodeport wordpress --tcp=80:80 --dry-run=client -o yaml > wordpress-service.yaml
```

**Edit `wordpress-service.yaml`:**

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: wordpress
  name: wordpress
spec:
  ports:
  - name: "80"
    port: 80
    protocol: TCP
    targetPort: 80
    nodePort: 30000  # Fixed port for consistency
  selector:
    app: wordpress
  type: NodePort
```

---

## Phase 3: Deploy to Kubernetes (20 minutes)

### Step 1: Deploy MySQL Components

**Apply MySQL resources in dependency order:**

```bash
# Create storage first
kubectl apply -f mysql-pvc.yaml

# Create MySQL deployment
kubectl apply -f mysql-deployment.yaml

# Create MySQL service
kubectl apply -f mysql-service.yaml

# Verify MySQL deployment
kubectl get pods -l app=mysql
kubectl get pvc mysql-pvc
```

**Wait for MySQL to be ready:**

```bash
kubectl wait --for=condition=ready pod -l app=mysql --timeout=300s
```

### Step 2: Deploy WordPress Components

**Apply WordPress resources:**

```bash
# Create WordPress deployment
kubectl apply -f wordpress-deployment.yaml

# Create WordPress service
kubectl apply -f wordpress-service.yaml

# Verify WordPress deployment
kubectl get pods -l app=wordpress
kubectl get services wordpress
```

### Step 3: Verify Complete Deployment

**Check all resources:**

```bash
# View all deployments
kubectl get deployments

# View all services
kubectl get services

# View all pods
kubectl get pods

# Check persistent volumes
kubectl get pvc
```

**Expected output:**

```
NAME                         READY   STATUS    RESTARTS   AGE
pod/mysql-xxxx               1/1     Running   0          5m
pod/wordpress-xxxx           1/1     Running   0          3m

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/mysql        ClusterIP   10.43.x.x       <none>        3306/TCP       5m
service/wordpress    NodePort    10.43.x.x       <none>        80:30000/TCP   3m
```

---

## Phase 4: Test and Validate Application (15 minutes)

### Step 1: Access WordPress Application

**Find WordPress access URL:**

```bash
# Get node port
kubectl get service wordpress

# Access application
curl http://localhost:30000
# Or open browser to http://localhost:30000
```

### Step 2: Complete WordPress Setup

**WordPress installation:**

1. Open browser to `http://localhost:30000`
2. Select language and continue
3. Fill in site information:
   - Site Title: "Kubernetes WordPress"
   - Username: admin
   - Password: (secure password)
   - Email: <your-email@example.com>
4. Install WordPress
5. Log in and create a test post

### Step 3: Test Service Discovery

**Verify MySQL connectivity from WordPress:**

```bash
# Access WordPress pod
kubectl exec -it deployment/wordpress -- bash

# Test MySQL connection
mysql -h mysql -u root -psomewordpress wordpress
# Should connect successfully

# Test DNS resolution
nslookup mysql
# Should resolve to MySQL service IP

exit
```

### Step 4: Test Data Persistence

**Test database persistence:**

```bash
# Delete MySQL pod to simulate failure
kubectl delete pod -l app=mysql

# Watch new pod creation
kubectl get pods -w

# Verify WordPress still works and data persists
curl http://localhost:30000
```

### Step 5: Test Scaling

**Scale WordPress deployment:**

```bash
# Scale to 3 replicas
kubectl scale deployment wordpress --replicas=3

# Watch pods being created
kubectl get pods -w

# Verify load balancing
kubectl get endpoints wordpress

# Test multiple requests hit different pods
for i in {1..10}; do curl -s http://localhost:30000 | grep -o 'pod/wordpress-[^"]*' || echo "Request $i"; done
```

---

## Phase 5: Operational Comparison (10 minutes)

### Docker Compose vs Kubernetes Commands

**Application Lifecycle:**

| Operation | Docker Compose | Kubernetes |
|-----------|----------------|------------|
| **Deploy** | `docker compose up -d` | `kubectl apply -f .` |
| **View Status** | `docker compose ps` | `kubectl get pods` |
| **View Logs** | `docker compose logs wordpress` | `kubectl logs deployment/wordpress` |
| **Scale** | `docker compose up -d --scale wordpress=3` | `kubectl scale deployment wordpress --replicas=3` |
| **Stop** | `docker compose down` | `kubectl delete -f .` |
| **Restart** | `docker compose restart wordpress` | `kubectl rollout restart deployment/wordpress` |

**Networking Differences:**

| Aspect | Docker Compose | Kubernetes |
|--------|----------------|------------|
| **Service Discovery** | Service name (automatic) | Service name (DNS-based) |
| **External Access** | Port mapping (8000:80) | NodePort/LoadBalancer service |
| **Internal Communication** | Service name resolution | Service name + DNS |
| **Load Balancing** | Single container per service | Automatic across pod replicas |

**Storage Management:**

| Feature | Docker Compose | Kubernetes |
|---------|----------------|------------|
| **Volume Definition** | `volumes:` section | PersistentVolumeClaim |
| **Volume Mounting** | `volumes:` in service | `volumeMounts:` in container |
| **Persistence** | Named volumes | PVC + PV lifecycle |
| **Sharing** | Between containers | Between pods (ReadWriteMany) |

---

## Troubleshooting Common Issues

### Pod Startup Problems

**MySQL pod won't start:**

```bash
# Check pod events
kubectl describe pod -l app=mysql

# Check logs
kubectl logs -l app=mysql

# Common issues:
# - PVC not bound: kubectl get pvc
# - Environment variables incorrect: kubectl describe deployment mysql
```

**WordPress pod won't start:**

```bash
# Check if MySQL is ready first
kubectl get pods -l app=mysql

# Check WordPress pod events
kubectl describe pod -l app=wordpress

# Check logs for database connection errors
kubectl logs -l app=wordpress
```

### Service Connectivity Issues

**WordPress can't connect to MySQL:**

```bash
# Verify MySQL service exists
kubectl get service mysql

# Check service endpoints
kubectl get endpoints mysql

# Test connectivity from WordPress pod
kubectl exec -it deployment/wordpress -- ping mysql
kubectl exec -it deployment/wordpress -- telnet mysql 3306
```

### External Access Problems

**Can't access WordPress from browser:**

```bash
# Verify NodePort service
kubectl get service wordpress

# Check if port is accessible
curl http://localhost:30000

# Alternative: Use port-forward for testing
kubectl port-forward service/wordpress 8080:80
# Then access http://localhost:8080
```

### Storage Issues

**MySQL data not persisting:**

```bash
# Check PVC status
kubectl get pvc mysql-pvc

# Verify volume mount in pod
kubectl describe pod -l app=mysql

# Check available storage in cluster
kubectl get pv
```

---

## Advanced Exercises (Optional)

### Exercise 1: Configuration Management

**Objective**: Use ConfigMaps and Secrets for configuration

**Tasks:**

1. Create a ConfigMap for WordPress configuration
2. Create a Secret for MySQL passwords
3. Update deployments to use ConfigMap and Secret
4. Redeploy and verify functionality

**ConfigMap example:**

```bash
kubectl create configmap wordpress-config \
  --from-literal=WORDPRESS_DB_NAME=wordpress \
  --from-literal=WORDPRESS_DB_USER=root
```

### Exercise 2: Health Checks

**Objective**: Add health checks to deployments

**Tasks:**

1. Add readiness probes to both deployments
2. Add liveness probes to both deployments
3. Test pod recovery during health check failures

**Health check example for WordPress:**

```yaml
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 5
```

### Exercise 3: Resource Management

**Objective**: Set resource limits and requests

**Tasks:**

1. Add resource requests and limits to both deployments
2. Monitor resource usage with `kubectl top`
3. Test scaling with resource constraints

---

## Cleanup

### Remove All Resources

**Delete application resources:**

```bash
# Delete all created resources
kubectl delete -f wordpress-service.yaml
kubectl delete -f wordpress-deployment.yaml
kubectl delete -f mysql-service.yaml
kubectl delete -f mysql-deployment.yaml
kubectl delete -f mysql-pvc.yaml

# Verify cleanup
kubectl get all
kubectl get pvc
```

**Alternative cleanup (if using single directory):**

```bash
kubectl delete -f .
```

---

## Learning Outcomes

### Technical Skills Acquired

- [ ] Generate Kubernetes manifests using `kubectl --dry-run`
- [ ] Convert Docker Compose services to Kubernetes Deployments and Services
- [ ] Handle persistent storage with PersistentVolumeClaims
- [ ] Configure environment variables in Kubernetes deployments
- [ ] Deploy multi-tier applications to Kubernetes
- [ ] Troubleshoot Kubernetes deployment issues

### Conceptual Understanding

- [ ] Differences between Docker Compose and Kubernetes operational models
- [ ] Kubernetes service discovery and networking concepts
- [ ] How Kubernetes handles scaling and load balancing
- [ ] Persistent storage management in Kubernetes
- [ ] Migration strategies from Docker Compose to Kubernetes

### Practical Experience

- [ ] Real application migration from Docker Compose to Kubernetes
- [ ] Using kubectl for application lifecycle management
- [ ] Debugging and troubleshooting Kubernetes applications
- [ ] Comparing operational procedures between platforms

---

## Next Steps

This lab demonstrated the fundamental migration process from Docker Compose to Kubernetes. Future modules will cover:

- **Advanced Configuration**: ConfigMaps, Secrets, and environment management
- **Ingress Controllers**: External access and routing instead of NodePort
- **StatefulSets**: For stateful applications like databases
- **Helm Charts**: Package management for Kubernetes applications
- **Production Patterns**: Monitoring, logging, and operational best practices

The migration skills learned here form the foundation for deploying any containerized application to Kubernetes.

---

## Additional Resources

- [Kubernetes Documentation - Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Documentation - Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Migrating Docker Compose to Kubernetes](https://kubernetes.io/docs/tasks/configure-pod-container/translate-compose-kubernetes/)
