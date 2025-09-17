# Lab: Software Token Management

## Objective

Implement a production-ready pattern for managing writable software tokens in Kubernetes.
Learn to handle tokens that need to be initially loaded from configuration management but modified by applications at runtime, requiring persistent storage and read/write access.

## Prerequisites

- Working Kubernetes cluster with storage provisioner
- Basic understanding of ConfigMaps, Secrets, and PersistentVolumes
- Familiarity with InitContainers and volume mounting

## Application Overview

Many enterprise applications require software tokens or license files that need to be:

- **Initially loaded** from configuration management (ConfigMaps/Secrets)
- **Modified at runtime** by the application (license updates, token refreshes)
- **Persisted** across pod restarts
- **Accessible** with read/write permissions

**The Challenge:** ConfigMaps and Secrets are read-only when mounted as volumes. Applications that need to modify license files or tokens cannot write to these mounted configurations.

**The Solution:** Use an InitContainer to copy the initial token from a ConfigMap to a writable PVC, then share that PVC with the main application container.

---

## Phase 1: Create Initial Token Configuration (10 minutes)

### Step 1: Create the Software Token Secret

**Create the initial token configuration:**

```yaml
# secret-software-token.yaml
apiVersion: v1
kind: Secret
metadata:
  name: software-token
  namespace: test-lab
type: Opaque
stringData:
  license.token: |
    SOFTWARE_LICENSE_V1
    ===============================
    Product: Enterprise Application
    Version: 2024.1
    License Type: Development
    Expiry: 2024-12-31
    Counter: 3
    ===============================
```

**Apply the Secret:**

```bash
# Apply the Secret
kubectl apply -f secret-software-token.yaml

# Verify Secret creation
kubectl get secret software-token
kubectl describe secret software-token
```

### Step 2: Create PersistentVolumeClaim for Writable Storage

**Create storage for the writable token:**

```yaml
# pvc-token-storage.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: token-storage-pvc
  namespace: test-lab
  labels:
    app: token-app
spec:
  resources:
    requests:
      storage: 500Mi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
```

**Apply the PVC:**

```bash
# Apply the PVC
kubectl apply -f pvc-token-storage.yaml

# Verify PVC is bound
kubectl get pvc token-storage-pvc
kubectl describe pvc token-storage-pvc
```

---

## Phase 2: Implement InitContainer Pattern (25 minutes)

### Step 1: Create Deployment with InitContainer

**Create the application deployment:**

```yaml
# deployment-token-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: token-app
  namespace: test-lab
  labels:
    app: token-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: token-app
  template:
    metadata:
      labels:
        app: token-app
    spec:
      # InitContainer copies token from Secret to writable PVC
      initContainers:
      - name: token-initializer
        image: busybox:1.37.0
        command: ['sh', '-c']
        args:
        - |
          echo "Initializing software token..."

          # Create token directory if it doesn't exist
          mkdir -p /writable-tokens

          # Copy token from Secret to writable location
          cp /readonly-tokens/license.token /writable-tokens/license.token

          # Set proper permissions
          chmod 664 /writable-tokens/license.token

          # Verify token was copied
          echo "Token initialized:"
          cat /writable-tokens/license.token

          echo "Token initialization complete."
        volumeMounts:
        - name: readonly-token-volume
          mountPath: /readonly-tokens
          readOnly: true
        - name: writable-token-volume
          mountPath: /writable-tokens
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"

      # Main application container
      containers:
      - name: token-app
        image: busybox:1.37.0
        command: ['sh', '-c']
        args:
        - |
          echo "Starting licensed application..."

          # Verify token exists and is writable
          if [ -f /writable-tokens/license.token ]; then
            echo "License token found:"
            cat /writable-tokens/license.token
          else
            echo "ERROR: License token not found!"
            exit 1
          fi

          # Simulate application runtime
          while true; do
            echo "$(date): Application running with license..."

            # Simulate token modification (e.g., usage tracking)
            echo "# Last access: $(date)" >> /writable-tokens/license.token

            # Show that we can read and write the token
            echo "Token file permissions:"
            ls -la /writable-tokens/license.token

            sleep 30
          done
        volumeMounts:
        - name: writable-token-volume
          mountPath: /writable-tokens
        env:
        - name: LICENSE_PATH
          value: "/writable-tokens/license.token"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"

      # Shared volumes
      volumes:
      - name: readonly-token-volume
        secret:
          secretName: software-token
      - name: writable-token-volume
        persistentVolumeClaim:
          claimName: token-storage-pvc
```

### Step 2: Deploy the Application

**Apply the deployment:**

```bash
# Apply the deployment
kubectl apply -f deployment-token-app.yaml

# Monitor deployment progress
kubectl get pods -w

# Check deployment status
kubectl rollout status deployment/token-app
```

### Step 3: Verify Token Initialization

**Check InitContainer execution:**

```bash
# Check initContainer logs
kubectl logs deployment/token-app -c token-initializer

# Expected output should show:
# Initializing software token...
# Token initialized:
# SOFTWARE_LICENSE_V1
# ===============================
# ...
# Token initialization complete.
```

**Verify main container is running:**

```bash
# Verify main container logs
kubectl logs deployment/token-app -c token-app

# Check that token is accessible and writable
kubectl exec deployment/token-app -c token-app -- ls -la /writable-tokens/
```

---

## Phase 3: Test Token Modification and Persistence (15 minutes)

### Step 1: Test Token Modification

**Modify the token from within the application:**

```bash
# Add a custom modification to the token
kubectl exec deployment/token-app -c token-app -- sh -c "echo 'MODIFIED_BY_APP: $(date)' >> /writable-tokens/license.token"

# Verify the modification was applied
kubectl exec deployment/token-app -c token-app -- cat /writable-tokens/license.token
```

### Step 2: Test Persistence Across Pod Restarts

**Restart the pod and verify data persistence:**

```bash
# Delete the pod to trigger restart
kubectl delete pod -l app=token-app

# Wait for pod to be ready again
kubectl wait --for=condition=ready pod -l app=token-app --timeout=300s

# Check that modifications survived the restart
kubectl exec deployment/token-app -c token-app -- cat /writable-tokens/license.token

# Verify the custom modification is still there
kubectl exec deployment/token-app -c token-app -- grep "MODIFIED_BY_APP" /writable-tokens/license.token
```

### Step 3: Test Multiple Modifications

**Simulate ongoing application usage:**

```bash
# Add multiple modifications
kubectl exec deployment/token-app -c token-app -- sh -c "echo 'Feature accessed: advanced' >> /writable-tokens/license.token"
kubectl exec deployment/token-app -c token-app -- sh -c "echo 'Usage count: 42' >> /writable-tokens/license.token"

# Verify all modifications are present
kubectl exec deployment/token-app -c token-app -- cat /writable-tokens/license.token
```

---

## Phase 4: Testing and Validation (10 minutes)

### Step 1: Comprehensive Functionality Testing

**Test the complete workflow:**

```bash
# Verify deployment is running
kubectl get deployments

# Check pod status
kubectl get pods -l app=token-app

# Test token modifications persist across restarts
kubectl delete pod -l app=token-app
kubectl wait --for=condition=ready pod -l app=token-app --timeout=300s

# Verify persistence worked
kubectl exec deployment/token-app -c token-app -- cat /writable-tokens/license.token | grep "Access"
```

### Step 2: Volume and Storage Validation

**Verify storage configuration:**

```bash
# Check PVC status
kubectl get pvc token-storage-pvc

# Verify volume mounts
kubectl describe pod -l app=token-app | grep -A 5 "Mounts:"

# Check storage usage
kubectl exec deployment/token-app -c token-app -- df -h /writable-tokens
```

### Step 3: Security and Permission Testing

**Verify proper permissions:**

```bash
# Check file permissions
kubectl exec deployment/token-app -c token-app -- ls -la /writable-tokens/

# Test write permissions
kubectl exec deployment/token-app -c token-app -- touch /writable-tokens/test-write

# Verify write worked
kubectl exec deployment/token-app -c token-app -- ls -la /writable-tokens/test-write
```

---

## Troubleshooting Common Issues

### Issue 1: InitContainer Fails to Copy Files

**Symptoms:**

```plaintext
Error: cp: can't create '/writable-tokens/license.token': Permission denied
```

**Solutions:**

```bash
# Check volume mounts
kubectl describe pod -l app=token-app | grep -A 10 "Mounts:"

# Verify PVC is bound
kubectl get pvc token-storage-pvc

# Check storage class
kubectl get storageclass
```

### Issue 2: Token Not Persisting Across Restarts

**Symptoms:**

- Token modifications disappear after pod restart

**Solutions:**

```bash
# Verify PVC is properly mounted
kubectl describe pod -l app=token-app | grep -A 5 "Volumes:"

# Check if PVC has persistent storage
kubectl describe pvc token-storage-pvc

# Verify volume is writable
kubectl exec deployment/token-app -c token-app -- touch /writable-tokens/test-persistence
```

### Issue 3: Secret Changes Not Reflected

**Symptoms:**

- Updates to Secret don't appear in application

**Solutions:**

```bash
# Secret changes require pod restart for InitContainer pattern
kubectl rollout restart deployment/token-app

# Verify Secret was updated
kubectl get secret software-token -o yaml

# Check InitContainer logs after restart
kubectl logs deployment/token-app -c token-initializer
```

---

## Comparison: Pattern Benefits

### Before (Read-Only ConfigMap)

```yaml
# Limited functionality
volumeMounts:
- name: token-volume
  mountPath: /writable-tokens
  readOnly: true    # ❌ Cannot modify tokens
volumes:
- name: token-volume
  configMap:
    name: token-config
# No persistence, no runtime modification
```

### After (InitContainer + PVC Pattern)

```yaml
# Full functionality
initContainers:
- name: token-initializer
  # ✅ Copies from ConfigMap to writable storage
volumeMounts:
- name: writable-token-volume
  mountPath: /writable-tokens    # ✅ Read/write access
volumes:
- name: writable-token-volume
  persistentVolumeClaim:    # ✅ Persistent across restarts
    claimName: token-storage-pvc
```

---

## Alternative Approaches

### Alternative 1: Secret-Based Tokens

For sensitive tokens, use Secrets instead of ConfigMaps:

```yaml
# secret-software-tokens.yaml
apiVersion: v1
kind: Secret
metadata:
  name: software-token-secret
  namespace: test-lab
type: Opaque
stringData:
  license.token: |
    SENSITIVE_LICENSE_TOKEN
    Product: Enterprise Application
    API_KEY: supersecret123
```

### Alternative 2: Conditional Initialization

Only initialize if token doesn't exist:

```yaml
# In InitContainer
args:
- |
  if [ ! -f /writable-tokens/license.token ]; then
    echo "Initializing new token..."
    cp /readonly-tokens/license.token /writable-tokens/license.token
  else
    echo "Existing token found, skipping initialization"
    echo "Current token:"
    cat /writable-tokens/license.token
  fi
```

### Alternative 3: Token Validation

Add token format validation:

```yaml
args:
- |
  # Copy token
  cp /readonly-tokens/license.token /writable-tokens/license.token

  # Validate token format
  if ! grep -q "SOFTWARE_LICENSE_V1" /writable-tokens/license.token; then
    echo "ERROR: Invalid license token format"
    exit 1
  fi

  echo "Token validation passed"
```

---

## Cleanup

### Remove Test Resources

```bash
# Remove deployment
kubectl delete deployment token-app

# Remove storage
kubectl delete pvc token-storage-pvc

# Remove configuration
kubectl delete secret software-token
```

---

## Learning Outcomes

### Technical Skills Acquired

- [ ] Implement InitContainer pattern for data initialization
- [ ] Create writable storage from read-only configuration sources
- [ ] Manage persistent application state using PVCs
- [ ] Handle complex volume mounting scenarios
- [ ] Troubleshoot storage and initialization issues

### Patterns and Best Practices Learned

- [ ] InitContainer data flow: ConfigMap → InitContainer → PVC → Main Container
- [ ] Separation of initialization logic from application logic
- [ ] Proper resource management for init and main containers
- [ ] Volume sharing between containers in the same pod
- [ ] Persistent storage for application runtime state

### Real-World Applications

- [ ] Software license management that tracks usage
- [ ] OAuth token refresh and persistence
- [ ] Configuration migration from static to dynamic
- [ ] Cache pre-loading and persistent state management
- [ ] Certificate and key management for applications

---

## Next Steps

This lab demonstrated a critical pattern for enterprise Kubernetes deployments where applications need to modify their configuration at runtime while maintaining persistence.

Future modules will cover:

- **StatefulSets**: For applications requiring ordered deployment and persistent identity
- **Storage Classes**: Advanced storage provisioning and management
- **Volume Snapshots**: Backup and restore strategies for persistent data

The InitContainer + PVC pattern learned here is widely applicable across many enterprise scenarios requiring writable configuration management.
