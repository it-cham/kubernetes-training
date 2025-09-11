# Lab: Configuration Management

## Objective

Transform your existing WordPress + MySQL deployment into a production-ready application with proper configuration management and resource optimization.
Learn to externalize configuration using ConfigMaps and Secrets while implementing resource best practices.

## Prerequisites

- Completed WordPress/MySQL migration
- Working WordPress deployment test namespace
- Basic understanding of your current application architecture

## Application Overview

We'll improve your existing WordPress application by addressing these configuration management issues:

- **Security**: Remove hardcoded passwords from deployment manifests
- **Maintainability**: Externalize configuration to ConfigMaps and Secrets
- **Performance**: Add resource requests and limits for predictable behavior
- **Operations**: Enable configuration updates without deployment changes (requires application support)

---

## Phase 1: Audit Current Configuration (15 minutes)

### Step 1: Examine Your existing Deployment

**Review your current setup:**

```bash
# Verify current deployment status
kubectl get all

# Review current deployment configurations
kubectl get deployment wordpress -o yaml
kubectl get deployment mysql -o yaml
```

### Step 2: Identify Configuration Issues

**Identify hardcoded configuration:**

Looking at your `deployment-wordpress.yaml`, you should see:

```yaml
env:
  - name: WORDPRESS_DB_HOST
    value: "mysql.test-lab.svc.cluster.local"  # Non-sensitive
  - name: WORDPRESS_DB_USER
    value: "root"                              # Non-sensitive
  - name: WORDPRESS_DB_NAME
    value: "wordpress"                         # Non-sensitive
  - name: WORDPRESS_DB_PASSWORD
    value: "somewordpress"                     # ❌ SECURITY ISSUE
```

And in `deployment-mysql.yaml`:

```yaml
env:
  - name: MYSQL_DATABASE
    value: wordpress           # Non-sensitive
  - name: MYSQL_ROOT_PASSWORD
    value: somewordpress      # ❌ SECURITY ISSUE
```

**Configuration categorization:**

| Configuration           | Type          | Target Storage |
| ----------------------- | ------------- | -------------- |
| `WORDPRESS_DB_HOST`     | Non-sensitive | ConfigMap      |
| `WORDPRESS_DB_USER`     | Non-sensitive | ConfigMap      |
| `WORDPRESS_DB_NAME`     | Non-sensitive | ConfigMap      |
| `WORDPRESS_DB_PASSWORD` | **Sensitive** | Secret         |
| -                     | -           | -           |
| `MYSQL_DATABASE`        | Non-sensitive | ConfigMap      |
| `MYSQL_ROOT_PASSWORD`   | **Sensitive** | Secret         |

---

## Phase 2: Create and Implement Secrets (25 minutes)

### Step 1: Create Secrets for Sensitive Data

**Method 1: Using kubectl (Imperative):**

```bash
# Create secret for MySQL credentials
kubectl create secret generic mysql-credentials --from-literal=MYSQL_ROOT_PASSWORD=somewordpress


# Create secret for WordPress database credentials
kubectl create secret generic wordpress-db-secret --from-literal=WORDPRESS_DB_PASSWORD=somewordpress


# Verify secrets creation
kubectl get secrets
kubectl describe secret mysql-credentials

# Show secret content (b64 encoded)
kubectl get secret mysql-credentials -o yaml
```

**Method 2: Using YAML (Declarative):**

```bash
kubectl create secret generic mysql-credentials --dry-run=client -o yaml > secrets.yaml

# Create b64 encoded value
echo "somewordpress" | base64
```

```yaml
# secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-credentials
  namespace: test-lab
  labels:
    app: mysql
type: Opaque
data:
  MYSQL_ROOT_PASSWORD: c29tZXdvcmRwcmVzcw==  # base64: somewordpress
---
apiVersion: v1
kind: Secret
metadata:
  name: wordpress-db-secret
  namespace: test-lab
  labels:
    app: wordpress
type: Opaque
data:
  WORDPRESS_DB_PASSWORD: c29tZXdvcmRwcmVzcw==  # base64: somewordpress
```

```bash
# Apply declarative secrets
kubectl apply -f secrets.yaml
```

**Verify secrets:**

```bash
# List all secrets
kubectl get secrets

# Show secret content (b64 encoded)
kubectl get secret mysql-credentials -o yaml
```

### Step 2: Update MySQL Deployment with Secrets

**Create updated MySQL deployment:**

```yaml
# deployment-mysql-with-secrets.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: test-lab
  labels:
    app: mysql
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
            # Non-sensitive: database name (will move to ConfigMap later)
            - name: MYSQL_DATABASE
              value: wordpress
            # Sensitive: password from Secret
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-credentials
                  key: MYSQL_ROOT_PASSWORD
          ports:
            - containerPort: 3306
          volumeMounts:
            - name: mysql-storage
              mountPath: "/var/lib/mysql"
      volumes:
        - name: mysql-storage
          persistentVolumeClaim:
            claimName: mysql-pvc
```

### Step 3: Update Deployment with Secrets

**Create updated WordPress deployment:**

```yaml
# deployment-wordpress-with-secrets.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: test-lab
  labels:
    app: wordpress
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
        - image: wordpress:php8.4
          name: wordpress
          env:
            # Non-sensitive configuration (will move to ConfigMap later)
            - name: WORDPRESS_DB_HOST
              value: "mysql.test-lab.svc.cluster.local"
            - name: WORDPRESS_DB_USER
              value: "root"
            - name: WORDPRESS_DB_NAME
              value: "wordpress"
            # Sensitive: password from Secret
            - name: WORDPRESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: wordpress-db-secret
                  key: WORDPRESS_DB_PASSWORD
          ports:
            - containerPort: 80
```

### Step 4: Deploy Secret-Based Configuration

**Apply updated deployments:**

```bash
# Apply MySQL deployment with secrets
kubectl apply -f deployment-mysql-with-secrets.yaml

# Apply WordPress deployment with secrets
kubectl apply -f deployment-wordpress-with-secrets.yaml

# Monitor rollout progress
kubectl rollout status deployment/mysql
kubectl rollout status deployment/wordpress

# Verify pods are running
kubectl get pods
```

**Test application functionality:**

```bash
# Check WordPress service
kubectl get service wordpress

# Test WordPress access (should work exactly like Module 4)
curl -I http://localhost:30000

# Test database connectivity from WordPress pod
kubectl exec deployment/wordpress -- wp db check
```

**Verify secret security:**

```bash
# Verify passwords are no longer in deployment manifests
kubectl get deployment mysql -o yaml | grep -i password
kubectl get deployment wordpress -o yaml | grep -i password
# Should show secretKeyRef references, not plain text passwords

# Check that secrets are properly consumed
kubectl describe pod -l app=mysql
kubectl describe pod -l app=wordpress
```

---

## Phase 3: Create and Implement ConfigMaps (20 minutes)

### Step 1: Create ConfigMaps for Non-Sensitive Data

**Method 1: Using kubectl (Imperative):**

```bash
# Create ConfigMap for WordPress configuration
kubectl create configmap wordpress-config \
  --from-literal=WORDPRESS_DB_HOST=mysql.test-lab.svc.cluster.local \
  --from-literal=WORDPRESS_DB_USER=root \
  --from-literal=WORDPRESS_DB_NAME=wordpress \


# Create ConfigMap for MySQL configuration
kubectl create configmap mysql-config \
  --from-literal=MYSQL_DATABASE=wordpress \


# Verify ConfigMaps
kubectl get configmaps
kubectl describe configmap wordpress-config
```

**Method 2: Using YAML (Declarative):**

```yaml
# configmaps.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: wordpress-config
  namespace: test-lab
  labels:
    app: wordpress
data:
  WORDPRESS_DB_HOST: "mysql.test-lab.svc.cluster.local"
  WORDPRESS_DB_USER: "root"
  WORDPRESS_DB_NAME: "wordpress"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-config
  namespace: test-lab
  labels:
    app: mysql
data:
  MYSQL_DATABASE: "wordpress"
```

```bash
# Apply ConfigMaps
kubectl apply -f configmaps.yaml
```

### Step 2: Update Deployments to Use ConfigMaps

**MySQL deployment with ConfigMaps:**

```yaml
# deployment-mysql-with-configmap.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: test-lab
  labels:
    app: mysql
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
            # Non-sensitive configuration from ConfigMap
            - name: MYSQL_DATABASE
              valueFrom:
                configMapKeyRef:
                  name: mysql-config
                  key: MYSQL_DATABASE
            # Sensitive configuration from Secret
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-credentials
                  key: MYSQL_ROOT_PASSWORD
          ports:
            - containerPort: 3306
          volumeMounts:
            - name: mysql-storage
              mountPath: "/var/lib/mysql"
      volumes:
        - name: mysql-storage
          persistentVolumeClaim:
            claimName: mysql-pvc
```

**WordPress deployment with ConfigMaps:**

```yaml
# deployment-wordpress-with-configmap.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: test-lab
  labels:
    app: wordpress
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
        - image: wordpress:php8.4
          name: wordpress
          # Load all non-sensitive config from ConfigMap
          envFrom:
            - configMapRef:
                name: wordpress-config
          env:
            # Override with sensitive data from Secret
            - name: WORDPRESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: wordpress-db-secret
                  key: WORDPRESS_DB_PASSWORD
          ports:
            - containerPort: 80
```

### Step 3: Deploy ConfigMap-Based Configuration

```bash
# Apply updated deployments
kubectl apply -f deployment-mysql-with-configmap.yaml
kubectl apply -f deployment-wordpress-with-configmap.yaml

# Monitor rollout
kubectl rollout status deployment/mysql
kubectl rollout status deployment/wordpress

```

### Step 4: Test Configuration Updates

**Test updating configuration without changing deployments:**

```bash
# Add new configuration to WordPress
kubectl patch configmap wordpress-config --patch '{"data":{"WORDPRESS_DEBUG":"true"}}'

# Restart deployment to pick up changes
kubectl rollout restart deployment/wordpress

# Test that application still works
# -I only prints header
curl -I http://localhost:30000
```

---

## Phase 4: Implement Resource Management (20 minutes)

### Step 1: Analyze Current Resource Usage

**Monitor current resource consumption:**

```bash
# Check current resource usage
kubectl top pods

# Check node capacity
kubectl top nodes
```

### Step 2: Determine Resource Requirements

**Based on typical WordPress/MySQL workloads:**

**MySQL Resource Requirements:**

- Requests: 200m CPU, 256Mi memory (guaranteed minimum)
- Limits: 500m CPU, 512Mi memory (maximum allowed)

**WordPress Resource Requirements:**

- Requests: 100m CPU, 128Mi memory (guaranteed minimum)
- Limits: 200m CPU, 256Mi memory (maximum allowed)

### Step 3: Add Resource Management to Deployments

**MySQL with resource management:**

```yaml
# deployment-mysql-final.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: test-lab
  labels:
    app: mysql
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
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          env:
            - name: MYSQL_DATABASE
              valueFrom:
                configMapKeyRef:
                  name: mysql-config
                  key: MYSQL_DATABASE
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-credentials
                  key: MYSQL_ROOT_PASSWORD
          ports:
            - containerPort: 3306
          volumeMounts:
            - name: mysql-storage
              mountPath: "/var/lib/mysql"
      volumes:
        - name: mysql-storage
          persistentVolumeClaim:
            claimName: mysql-pvc
```

**WordPress with resource management:**

```yaml
# deployment-wordpress-final.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: test-lab
  labels:
    app: wordpress
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
        - image: wordpress:php8.4
          name: wordpress
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
          envFrom:
            - configMapRef:
                name: wordpress-config
          env:
            - name: WORDPRESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: wordpress-db-secret
                  key: WORDPRESS_DB_PASSWORD
          ports:
            - containerPort: 80
```

### Step 4: Deploy Resource-Managed Applications

```bash
# Apply final deployments with resource management
kubectl apply -f deployment-mysql-final.yaml
kubectl apply -f deployment-wordpress-final.yaml

# Monitor deployment rollout
kubectl rollout status deployment/mysql
kubectl rollout status deployment/wordpress

# Verify resource allocation
kubectl describe pod -l app=mysql | grep -A 5 "Requests:"
kubectl describe pod -l app=wordpress | grep -A 5 "Requests:"
```

### Step 5: Verify Quality of Service Classes

```bash
# Check QoS classes assigned to pods
kubectl get pods -o custom-columns=NAME:.metadata.name,QoS:.status.qosClass

# Expected output:
# mysql-xxx: Burstable (requests < limits)
# wordpress-xxx: Burstable (requests < limits)
```

---

## Phase 5: Testing and Validation (15 minutes)

### Step 1: Functional Testing

**Verify WordPress functionality:**

```bash
# Test WordPress access
curl -I http://localhost:30000

# Complete WordPress setup if not done
# Open browser to http://localhost:30000 and complete installation

# Test database connectivity
kubectl exec deployment/wordpress -- wp db check
```

### Step 2: Configuration Management Testing

**Test configuration updates:**

```bash
# Update WordPress configuration

kubectl edit configmap wordpress-config
# kubectl patch configmap wordpress-config --patch '{"data":{"WORDPRESS_DEBUG_LOG":"true"}}'

# Restart to pick up changes
kubectl rollout restart deployment/wordpress

# Verify configuration update
kubectl exec deployment/wordpress -- env | grep WORDPRESS_DEBUG
```

**Test secret rotation:**

```bash
# Simulate password rotation (use same password for simplicity)
kubectl patch secret mysql-credentials --patch '{"data":{"MYSQL_ROOT_PASSWORD":"bmV3LXBhc3N3b3Jk"}}'
kubectl patch secret wordpress-db-secret --patch '{"data":{"WORDPRESS_DB_PASSWORD":"bmV3LXBhc3N3b3Jk"}}'

# Restart deployments
kubectl rollout restart deployment/mysql
kubectl rollout restart deployment/wordpress

# Verify application still works
curl -I http://localhost:30000
```

### Step 3: Resource Management Testing

**Test scaling with resource constraints:**

```bash
# Scale WordPress to multiple replicas
kubectl scale deployment wordpress --replicas=3

# Monitor resource usage
kubectl top pods

# Verify all pods scheduled successfully
kubectl get pods

# Scale back to single replica
kubectl scale deployment wordpress --replicas=1
```

### Step 4: Security Validation

**Verify security improvements:**

```bash
# Check that no passwords appear in deployment manifests
kubectl get deployment mysql -o yaml | grep -i "somewordpress"
kubectl get deployment wordpress -o yaml | grep -i "somewordpress"
# Should return no results

# Verify secrets are properly referenced
kubectl describe deployment mysql | grep -A 5 "Environment:"
kubectl describe deployment wordpress | grep -A 5 "Environment:"
```

---

## Troubleshooting Common Issues

### Issue 1: Pods Fail to Start After Adding Secrets

**Symptoms:**

```plaintext
Error: Secret "mysql-credentials" not found
```

**Solutions:**

```bash
# Check if secret exists in correct namespace
kubectl get secrets

# Verify secret has correct keys
kubectl describe secret mysql-credentials

# Recreate secret if necessary
kubectl delete secret mysql-credentials
kubectl create secret generic mysql-credentials \
  --from-literal=MYSQL_ROOT_PASSWORD=somewordpress \

```

### Issue 2: Configuration Not Updating

**Symptoms:**

- ConfigMap updated but application uses old values

**Solutions:**

```bash
# ConfigMaps require pod restart to take effect
kubectl rollout restart deployment/wordpress

# Verify ConfigMap was updated
kubectl get configmap wordpress-config -o yaml

# Check environment variables in running pod
 deployment/wordpress -- env | sort
```

### Issue 3: Resource Constraints Too Restrictive

**Symptoms:**

```plaintext
Status: Failed
Reason: Evicted
Message: Pod was evicted due to memory pressure
```

**Solutions:**

```bash
# Check current resource usage
kubectl top pods

# Increase resource limits (Interactive)
kubectl edit deployment mysql

# Declarative
# kubectl patch deployment mysql -p '{"spec":{"template":{"spec":{"containers":[{"name":"mysql","resources":{"limits":{"memory":"1Gi"}}}]}}}}'

# Monitor pod status
kubectl get pods -w
```

### Issue 4: Database Connection Issues

**Symptoms:**

- WordPress can't connect to MySQL

**Solutions:**

```bash
# Verify MySQL is running
kubectl get pods -l app=mysql

# Check MySQL logs
kubectl logs deployment/mysql

# Verify secrets contain correct passwords
kubectl exec deployment/wordpress -- env | grep WORDPRESS_DB

kubectl get secret mysql-credentials -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d
kubectl get secret wordpress-db-secret -o jsonpath='{.data.WORDPRESS_DB_PASSWORD}' | base64 -d
```

---

## Comparison: Before vs After

### Before

```yaml
# Security Issues
env:
  - name: MYSQL_ROOT_PASSWORD
    value: "somewordpress"      # ❌ Plain text password
  - name: WORDPRESS_DB_PASSWORD
    value: "somewordpress"      # ❌ Plain text password

# No resource management
# resources: {}                # ❌ Unlimited resource usage

# Configuration mixed with deployment
# All config hardcoded in deployment manifest
```

### After

```yaml
# Secure configuration
envFrom:
  - configMapRef:
      name: wordpress-config    # ✅ Non-sensitive config externalized
env:
  - name: WORDPRESS_DB_PASSWORD
    valueFrom:
      secretKeyRef:             # ✅ Sensitive data in secrets
        name: wordpress-db-secret
        key: WORDPRESS_DB_PASSWORD

# Predictable resource management
resources:                      # ✅ Resource requests and limits
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

---

## Alternative Approaches

### Alternative 1: File-Based Configuration

For applications that read configuration files:

```yaml
# configmap-files.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: wordpress-file-config
  namespace: test-lab
data:
  wp-config.php: |
    <?php
    define('DB_HOST', 'mysql.test-lab.svc.cluster.local');
    define('DB_USER', 'root');
    define('DB_NAME', 'wordpress');
    // DB_PASSWORD will be loaded from secret file
```

Mount as volume:

```yaml
volumeMounts:
  - name: config-volume
    mountPath: /var/www/html/wp-config.php
    subPath: wp-config.php
volumes:
  - name: config-volume
    configMap:
      name: wordpress-file-config
```

### Alternative 2: Using envFrom

Load entire ConfigMaps as environment variables:

```yaml
envFrom:
  - configMapRef:
      name: wordpress-config
  - secretRef:
      name: wordpress-db-secret
# No individual env entries needed
```

---

## Cleanup

### Remove Test Resources

```bash
kubectl delete -f manifests
```

---

## Learning Outcomes

### Technical Skills Acquired

- [ ] Use ConfigMaps for non-sensitive application configuration
- [ ] Create and manage Kubernetes Secrets for sensitive data
- [ ] Update existing deployments to use externalized configuration
- [ ] Implement resource requests and limits for containers
- [ ] Troubleshoot configuration-related issues

### Security Improvements Achieved

- [ ] Eliminated hardcoded passwords from deployment manifests
- [ ] Implemented proper separation of sensitive and non-sensitive configuration
- [ ] Applied Kubernetes security best practices for secret management
- [ ] Reduced risk of credential exposure in Git repositories
- [ ] Provided foundation for understanding external secret management

### Operational Benefits Gained

- [ ] Configuration can be updated independently of deployments
- [ ] Different environments can use same deployments with different configs
- [ ] Resource usage is predictable and constrained
- [ ] Application is ready for production deployment
- [ ] Improved maintainability and operational flexibility

---

## Next Steps

This lab has transformed your WordPress application from a basic Kubernetes deployment to a more production-ready application with proper configuration management.

Future modules will cover:

- **Ingress Controllers**: Better external access management instead of NodePort
- **Storage**: Automatic provisioning of persistent data using StorageClasses, PVCs and PVs
- **StatefulSets**: For stateful applications requiring ordered deployment

The configuration management patterns learned here apply to any application you deploy to Kubernetes.
