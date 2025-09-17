
# Lab: Persistent Storage

## Objective

Transform the WordPress application from Module 5 to use distributed storage with Longhorn, replacing the local-path storage class.
Learn the practical differences between local and distributed storage while maintaining application functionality.

## Prerequisites

- Rancher Desktop with k3s cluster
- Working WordPress + MySQL application in `test-lab` namespace
- At least 2GB available RAM for Longhorn components

## Application Overview

We'll improve the existing WordPress storage architecture by:

- **Evaluating**: Current local-path storage implementation and limitations
- **Deploying**: Longhorn distributed storage system
- **Migrating**: MySQL from local-path to Longhorn storage
- **Validating**: Improved reliability and scaling capabilities

---

## Phase 1: Storage Configuration Audit (10-15 minutes)

### Step 1: Examine Current Storage Setup

**Verify current deployment status:**

```bash
# Check current deployment state
kubectl get all -n test-lab

# Examine current storage resources
kubectl get storageclass

kubectl get pvc -n test-lab
kubectl get pv -n test-lab

# Check MySQL deployment storage configuration
kubectl describe deployment mysql -n test-lab
```

### Step 2: Investigate Storage Implementation

**Examine PersistentVolume details:**

```bash
# Get detailed PV information
kubectl get pv -o wide

# Check local-path storage class details
kubectl describe storageclass local-path

# Describe the MySQL PV to see actual storage location
kubectl describe pv $(kubectl get pvc mysql-pvc -n test-lab -o jsonpath='{.spec.volumeName}')
```

### Step 3: Document Current Architecture

**Current storage architecture:**

```plaintext
┌─────────────────┐
│ MySQL Pod       │
│ (single replica)│
└─────────┬───────┘
          │
┌─────────▼───────┐
│ mysql-pvc       │
│ (local-path)    │
└─────────┬───────┘
          │
┌─────────▼───────┐
│ Local Directory │
│ /var/lib/ranch..│
└─────────────────┘
```

---

## Phase 2: Limitation Validation (15-20 minutes)

### Step 1: Test Scaling Limitations

**Attempt to scale MySQL:**

```bash
# Try to scale MySQL to multiple replicas
kubectl scale deployment mysql --replicas=2 -n test-lab

# Monitor pod status
kubectl get pods -n test-lab -w

# Check events for scheduling issues
kubectl get events -n test-lab --sort-by='.lastTimestamp' | grep mysql

# Expected result: Second pod will remain in Pending state
# Reason: RWO (ReadWriteOnce(Pod)) volume can only be mounted by one pod
```

**Examine the failure:**

```bash

# Look for volume mounting errors
kubectl get events -n test-lab

# Scale back to single replica
kubectl scale deployment mysql --replicas=1 -n test-lab
```

### Step 2: Test Node Dependency

Note: This is only applicable in a multi-node setup.

**Simulate node failure scenario:**

```bash
# Check which node MySQL pod is running on
kubectl get pods -l app=mysql -n test-lab -o wide

# In a multi-node setup, you would cordon the node:
# kubectl cordon <node-name>
# kubectl delete pod -l app=mysql -n test-lab

# For single-node k3s, we'll demonstrate the concept:
echo "In production, if this node fails, MySQL data becomes inaccessible until node recovery"
```

### Step 3: Performance Baseline

**Establish current I/O performance:**

```bash
# Test write performance in MySQL pod
kubectl exec deployment/mysql -n test-lab -- dd if=/dev/zero of=/var/lib/mysql/test-file bs=1M count=100

# Test read performance
kubectl exec deployment/mysql -n test-lab -- dd if=/var/lib/mysql/test-file of=/dev/null bs=1M

# Clean up test file
kubectl exec deployment/mysql -n test-lab -- rm /var/lib/mysql/test-file
```

---

## Phase 3: Longhorn Implementation (30-40 minutes)

### Step 1: Prepare Rancher Desktop for Longhorn

**Important:** Longhorn requires iSCSI support which needs to be configured in Rancher Desktop.

**For macOS users:**

```bash
# Create override configuration directory
mkdir -p "~/Library/Application Support/rancher-desktop/lima/_config"

# Create override.yaml file
cat > "~/Library/Application Support/rancher-desktop/lima/_config/override.yaml" << 'EOF'
provision:
  - mode: system
    script: |
      #!/bin/sh
      apk add open-iscsi
      rc-update add iscsid
      rc-service iscsid start
EOF
```

**For Linux users:**

```bash
# Create override configuration directory
mkdir -p ~/.local/share/rancher-desktop/lima/_config

# Create override.yaml file
cat > ~/.local/share/rancher-desktop/lima/_config/override.yaml << 'EOF'
provision:
  - mode: system
    script: |
      #!/bin/sh
      apk add open-iscsi
      rc-update add iscsid
      rc-service iscsid start
EOF
```

**Restart Rancher Desktop after creating the override file:**

1. Quit Rancher Desktop completely
2. Restart Rancher Desktop
3. Wait for k3s cluster to be ready

**Verify iSCSI is available:**

```bash
# Check if iSCSI initiator is running in the k3s node
docker exec k3d-main-server-0 rc-service iscsid status
```

### Step 2: Deploy Longhorn

**Deploy Longhorn using kubectl:**

```bash
# Apply Longhorn manifests
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# Monitor Longhorn deployment
kubectl get pods -n longhorn-system -w

# Wait for all Longhorn pods to be ready (this may take 5-10 minutes)
kubectl wait --for=condition=ready pod --all -n longhorn-system --timeout=600s
```

**Verify Longhorn installation:**

```bash
# Check Longhorn system pods
kubectl get pods -n longhorn-system

# Verify Longhorn storage class was created
kubectl get storageclass

# Check Longhorn nodes
kubectl get nodes.longhorn.io -n longhorn-system
```

### Step 3: Access Longhorn UI (Optional)

**Set up port forwarding to access Longhorn dashboard:**

```bash
# Forward Longhorn UI port
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 &

# Access UI at http://localhost:8080
echo "Longhorn UI available at: http://localhost:8080"
```
