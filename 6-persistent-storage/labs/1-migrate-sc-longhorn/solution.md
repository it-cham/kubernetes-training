
# Lab: Persistent Storage - Migrate to Longhorn Storage Class

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

## Phase 4: MySQL Storage Migration (15-20 minutes)

### Step 1: Backup Current Data

**Create backup before migration:**

```bash
# Create database backup
kubectl exec deployment/mysql -n test-lab -- mysqldump -u root -psomewordpress --all-databases > mysql-backup.sql

# Verify backup was created
ls -la mysql-backup.sql
```

### Step 2: Create New Longhorn PVC

**Create new PVC using Longhorn storage:**

```yaml
# mysql-longhorn-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-longhorn-pvc
  namespace: test-lab
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 2Gi
```

```bash
# Apply the new PVC
kubectl apply -f mysql-longhorn-pvc.yaml

# Verify PVC creation and binding
kubectl get pvc -n test-lab
kubectl describe pvc mysql-longhorn-pvc -n test-lab
```

### Step 3: Update MySQL Deployment

**Method 1: In-place migration (if data loss is acceptable):**

```bash
# Scale down MySQL
kubectl scale deployment mysql --replicas=0 -n test-lab

# Update deployment to use new PVC
kubectl edit deployment mysql -n test-lab
# kubectl patch deployment mysql -n test-lab -p '{"spec":{"template":{"spec":{"volumes":[{"name":"mysql-storage","persistentVolumeClaim":{"claimName":"mysql-longhorn-pvc"}}]}}}}'

# Scale back up
kubectl scale deployment mysql --replicas=1 -n test-lab

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=mysql -n test-lab --timeout=300s
```

**Method 2: Data migration (preserves data):**

```yaml
# mysql-deployment-longhorn.yaml
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
            claimName: mysql-longhorn-pvc  # Updated to use Longhorn PVC
```

**If preserving data, restore from backup:**

```bash
# If using Method 1 and need to restore data
kubectl cp mysql-backup.sql PODNAME:/tmp/

# Restore database
kubectl exec -it deployment/mysql -n test-lab -- mysql -u root -psomewordpress < /tmp/mysql-backup.sql
```

### Step 4: Verify Migration

**Test application functionality:**

```bash
# Check MySQL pod status
kubectl get pods -l app=mysql -n test-lab

# Verify WordPress connectivity
kubectl get service wordpress -n test-lab
curl -I http://localhost:30000

# Verify storage is using Longhorn
kubectl describe pvc mysql-longhorn-pvc -n test-lab
```

---

## Phase 5: Validation and Testing (10-15 minutes)

### Step 1: Test Improved Scaling

**Now test MySQL scaling with Longhorn:**

```bash
# Scale MySQL to multiple replicas (WORKS, BUT APPLICATION SUPPORT IS MANDATORY!)
kubectl scale deployment mysql --replicas=2 -n test-lab

# Monitor pod creation
kubectl get pods -l app=mysql -n test-lab -w

# Example: MySQL still needs clustering configuration for true multi-replica support
# But the storage layer no longer blocks scaling

# Scale back to single replica for now
kubectl scale deployment mysql --replicas=1 -n test-lab
```

### Step 2: Verify Longhorn Features

**Check storage replication:**

```bash
# View Longhorn volumes
kubectl get volumes.longhorn.io -n longhorn-system

# Describe the MySQL volume
kubectl describe volume.longhorn.io -n longhorn-system $(kubectl get pvc mysql-longhorn-pvc -n test-lab -o jsonpath='{.spec.volumeName}')

# Access Longhorn UI to see volume details
echo "Check Longhorn UI at http://localhost:8080 for volume replication status"
```

### Step 3: Performance Comparison

**Test I/O performance with Longhorn:**

```bash
# Test write performance with new storage
kubectl exec deployment/mysql -n test-lab -- dd if=/dev/zero of=/var/lib/mysql/longhorn-test-file bs=1M count=100

# Test read performance
kubectl exec deployment/mysql -n test-lab -- dd if=/var/lib/mysql/longhorn-test-file of=/dev/null bs=1M

# Clean up test file
kubectl exec deployment/mysql -n test-lab -- rm /var/lib/mysql/longhorn-test-file
```

### Step 4: Verify WordPress Functionality

**Complete application testing:**

```bash
# Test WordPress access
curl -s http://localhost:30000

# If WordPress setup not complete, complete it via browser
echo "Access http://localhost:30000 to complete WordPress setup if needed"

# Verify database connectivity and data persistence
kubectl exec deployment/mysql -n test-lab -- mysql -u root -psomewordpress -e "SHOW DATABASES;"
```

---

## Troubleshooting Common Issues

### Issue 1: Longhorn Pods Fail to Start

**Symptoms:**

```plaintext
longhorn-manager pods in CrashLoopBackOff or Pending state
```

**Solutions:**

```bash
# Check if iSCSI is properly configured
docker exec k3d-main-server-0 rc-service iscsid status

# If iSCSI is not running, ensure override.yaml is correct and restart Rancher Desktop

# Check Longhorn prerequisites
kubectl get nodes -o wide
kubectl describe nodes

# Verify sufficient resources
kubectl top nodes
```

### Issue 2: PVC Stuck in Pending State

**Symptoms:**

```plaintext
mysql-longhorn-pvc remains in Pending status
```

**Solutions:**

```bash
# Check PVC events
kubectl describe pvc mysql-longhorn-pvc -n test-lab

# Verify Longhorn storage class
kubectl get storageclass longhorn

# Check Longhorn system health
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager
```

### Issue 3: MySQL Pod Fails After Migration

**Symptoms:**

```
MySQL pod crashes or fails to start with new PVC
```

**Solutions:**

```bash
# Check MySQL logs
kubectl logs deployment/mysql -n test-lab

# Verify PVC is properly mounted
kubectl describe pod -l app=mysql -n test-lab

# Check file permissions in mounted volume
kubectl exec deployment/mysql -n test-lab -- ls -la /var/lib/mysql

# If needed, restore from backup
kubectl exec deployment/mysql -n test-lab -- mysql -u root -psomewordpress < mysql-backup.sql
```

### Issue 4: Longhorn UI Not Accessible

**Symptoms:**

```plaintext
Cannot access Longhorn UI via port-forward
```

**Solutions:**

```bash
# Check if longhorn-frontend service exists
kubectl get svc -n longhorn-system longhorn-frontend

# Verify port-forward is running
ps aux | grep port-forward

# Try different port
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8081:80
```

---

## Storage Architecture Comparison

### Before Migration (local-path)

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
│ Single Node     │
└─────────────────┘
```

**Limitations:**

- Single point of failure
- No replication
- Node-dependent storage
- No disaster recovery

### After Migration (Longhorn)

```plaintext
┌─────────────────┐
│ MySQL Pod       │
│ (scalable)      │
└─────────┬───────┘
          │
┌─────────▼───────┐
│ mysql-longhorn  │
│     PVC         │
└─────────┬───────┘
          │
┌─────────▼───────┐
│ Longhorn Volume │
│ (replicated)    │
└─────────┬───────┘
          │
┌─────────▼───────┐
│ Distributed     │
│ Storage Engine  │
└─────────────────┘
```

**Improvements:**

- Distributed storage engine
- Built-in replication
- Snapshot capabilities
- Backup and restore features
- Volume expansion support

---

## Performance and Feature Comparison

| Feature | local-path | Longhorn |
|---------|------------|----------|
| **Replication** | None | Configurable |
| **Snapshots** | None | Built-in |
| **Backup** | Manual | Automated |
| **Expansion** | Limited | Dynamic |
| **Multi-attach** | No | Limited |
| **Monitoring** | Basic | Advanced UI |
| **Disaster Recovery** | None | Built-in |

---

## Cleanup and Maintenance

### Remove Old local-path PVC

```bash
# After confirming Longhorn migration is successful
kubectl delete pvc mysql-pvc -n test-lab

# Verify old PV cleanup
kubectl get pv | grep local-path
```

### Regular Maintenance Tasks

```bash
# Check Longhorn system health
kubectl get pods -n longhorn-system

# Monitor volume usage
kubectl get volumes.longhorn.io -n longhorn-system

# Check node storage capacity
kubectl describe nodes.longhorn.io -n longhorn-system
```

---

## Learning Outcomes

### Technical Skills Acquired

- [ ] Understand practical differences between local and distributed storage
- [ ] Deploy and configure Longhorn distributed storage system
- [ ] Migrate applications from local-path to distributed storage
- [ ] Configure storage classes for different use cases
- [ ] Validate storage improvements through testing

### Storage Concepts Mastered

- [ ] PersistentVolume vs PersistentVolumeClaim relationships
- [ ] Storage class capabilities and limitations
- [ ] Distributed storage architecture and benefits
- [ ] Storage migration strategies and best practices
- [ ] Storage monitoring and troubleshooting

### Operational Benefits Achieved

- [ ] Improved application reliability through distributed storage
- [ ] Enhanced disaster recovery capabilities
- [ ] Better scaling foundation for database workloads
- [ ] Advanced storage management and monitoring tools
- [ ] Preparation for enterprise storage integration

---

## Next Steps: Session 2 Preview

With Longhorn now deployed and operational, Session 2 will focus on advanced enterprise storage patterns:

- **Advanced backup and disaster recovery**: Automated backup schedules and recovery procedures
- **Multi-pod applications**: Deploy applications requiring ReadWriteMany access modes
- **Performance optimization**: Storage tuning and performance testing
- **Enterprise integration**: Connecting Longhorn concepts to enterprise storage systems
- **Production patterns**: Monitoring, alerting, and operational procedures

The foundation built in this session enables advanced enterprise storage scenarios in the next session.

---

**Estimated Completion Time**: 75-90 minutes
**Learning Validation**: Students should be able to explain the benefits of distributed storage over local storage and successfully migrate applications between storage classes.
