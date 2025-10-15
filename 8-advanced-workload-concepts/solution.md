# Lab: Advanced Workload Management - StatefulSets and Operations - Solution

## Objective

Deploy a highly available MongoDB cluster using StatefulSet, initialize a replica set for automatic failover, and perform production-safe storage resize operations.

## Prerequisites

- Rancher Desktop with k3s cluster
- Longhorn storage installed and operational
- NGINX Ingress Controller deployed
- kubectl configured
- At least 4GB RAM available for cluster

---

## Phase 1: StatefulSet Deployment (30-40 minutes)

### Step 1: Create Namespace

```bash
# Create dedicated namespace
kubectl create namespace mongo-lab

# Verify namespace created
kubectl get namespace mongo-lab
```

---

### Step 2: Deploy MongoDB Configuration

**Create ConfigMap:**

```yaml
# configmap-mongodb.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-config
  namespace: mongo-lab
data:
  mongod.conf: |
    # mongod.conf
    # for documentation of all options, see:
    #   http://docs.mongodb.org/manual/reference/configuration-options/

    # Where and how to store data.
    storage:
      dbPath: /data/db

    replication:
      replSetName: "rs0"

    net:
      port: 27017
      bindIp: 0.0.0.0
      bindIpAll: true
```

```bash
# Apply ConfigMap
kubectl apply -f configmap-mongodb.yaml

# Verify ConfigMap created
kubectl get configmap -n mongo-lab
kubectl describe configmap mongodb-config -n mongo-lab
```

---

### Step 3: Create Headless Service

**Headless Service for StatefulSet:**

```yaml
# service-headless-mongodb.yaml
apiVersion: v1
kind: Service
metadata:
  name: mongodb-headless
  namespace: mongo-lab
  labels:
    app: mongodb
spec:
  type: ClusterIP
  clusterIP: "None"  # Headless - no load balancing
  selector:
    app: mongodb
  ports:
    - port: 27017
      targetPort: 27017
      protocol: TCP
      name: mongodb
```

```bash
# Apply headless service
kubectl apply -f service-headless-mongodb.yaml

# Verify service created
kubectl get svc -n mongo-lab
# Should show: mongodb-headless with ClusterIP: None

# Describe service
kubectl describe svc mongodb-headless -n mongo-lab
```

**Understanding Headless Services:**

A headless Service (clusterIP: None) returns individual pod IPs instead of a single virtual IP, enabling:

- Direct pod-to-pod communication
- Stable DNS records per pod: `mongodb-0.mongodb-headless.mongo-lab.svc.cluster.local`
- Required for StatefulSet networking

---

### Step 4: Deploy MongoDB StatefulSet

**MongoDB StatefulSet with 2 replicas:**

```yaml
# statefulset-mongodb.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: mongo-lab
spec:
  replicas: 2
  serviceName: mongodb-headless
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
        - name: mongodb
          image: mongo:8.0.15-noble
          command:
            - "mongod"
            - "--config"
            - "/etc/mongod.conf"
          env:
            # In production, use Secrets!
            - name: MONGO_INITDB_ROOT_USERNAME
              value: "root"
            - name: MONGO_INITDB_ROOT_PASSWORD
              value: "example"
          ports:
            - containerPort: 27017
              name: mongodb
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          livenessProbe:
            exec:
              command:
                - mongosh
                - --eval
                - "db.adminCommand('ping')"
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
          readinessProbe:
            exec:
              command:
                - mongosh
                - --eval
                - "db.adminCommand('ping')"
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3
          volumeMounts:
            - name: mongodb-pvc
              mountPath: /data/db
            - name: mongodb-config
              mountPath: /etc/mongod.conf
              subPath: mongod.conf
      volumes:
        - name: mongodb-config
          configMap:
            name: mongodb-config

  volumeClaimTemplates:
    - metadata:
        name: mongodb-pvc
      spec:
        storageClassName: "longhorn"
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 2Gi
```

```bash
# Deploy StatefulSet
kubectl apply -f statefulset-mongodb.yaml

# Watch pods being created (ordered: mongodb-0 then mongodb-1)
kubectl get pods -w

# Verify StatefulSet created
kubectl get statefulset -n mongo-lab
```

---

### Step 5: Verify StatefulSet Architecture

**Check Pod Naming:**

```bash
# View pods - should see predictable names
kubectl get pods -n mongo-lab -o wide

# Expected output:
# NAME        READY   STATUS    RESTARTS   AGE
# mongodb-0   1/1     Running   0          2m
# mongodb-1   1/1     Running   0          1m30s
```

**Check PVC Creation:**

```bash
# View PVCs - one per pod
kubectl get pvc -n mongo-lab

# Expected output:
# NAME                    STATUS   VOLUME                                    CAPACITY   STORAGECLASS
# mongodb-pvc-mongodb-0   Bound    pvc-xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx     2Gi        longhorn
# mongodb-pvc-mongodb-1   Bound    pvc-yyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy     2Gi        longhorn

# Describe PVCs to see binding details
kubectl describe pvc -n mongo-lab
```

**Test MongoDB Connectivity:**

```bash
# Connect to mongodb-0
kubectl exec -it -n mongo-lab mongodb-0 -- mongosh

# Inside mongosh, test basic commands:
show dbs
exit
```

---

### Step 6: Understand StatefulSet Behavior

**Ordered Pod Creation:**

```bash
# View pod creation timestamps
kubectl get pods -n mongo-lab -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp

# mongodb-0 is always created first, mongodb-1 second
# This is guaranteed by StatefulSet controller
```

**Stable Network Identity:**

```bash
# Get pod IPs
kubectl get pods -n mongo-lab -o wide

# Even if you delete a pod, it gets the same name and DNS record
kubectl delete pod mongodb-1 -n mongo-lab

# Watch it recreate with same name
kubectl get pods -n mongo-lab -w

# DNS record remains stable: mongodb-1.mongodb-headless...
```

**PVC Persistence:**

```bash
# Delete a pod
kubectl delete pod mongodb-0 -n mongo-lab

# PVC remains bound
kubectl get pvc -n mongo-lab

# New pod reattaches to same PVC - data persists
```

---

## Phase 2: MongoDB Replica Set Initialization (15-20 minutes)

### Step 1: Prepare Replica Set Initialization

**Understanding Replica Sets:**

A MongoDB replica set provides:

- **Automatic failover:** If PRIMARY fails, SECONDARY is elected
- **Data replication:** Changes on PRIMARY replicate to SECONDARY
- **Read scaling:** Read from SECONDARY nodes (optional)

**DNS Names Required:**

```plaintext
mongodb-0.mongodb-headless.mongo-lab.svc.cluster.local:27017
mongodb-1.mongodb-headless.mongo-lab.svc.cluster.local:27017
```

---

### Step 2: Initialize Replica Set

**Connect to mongodb-0 (will become PRIMARY):**

```bash
# Connect to first pod
kubectl exec -it -n mongo-lab mongodb-0 -- mongosh
```

**Inside mongosh shell, initialize replica set:**

```javascript
// Initialize replica set with 2 members
rs.initiate({
  _id: "rs0",
  members: [
    {
      _id: 0,
      host: "mongodb-0.mongodb-headless.mongo-lab.svc.cluster.local:27017"
    },
    {
      _id: 1,
      host: "mongodb-1.mongodb-headless.mongo-lab.svc.cluster.local:27017"
    }
  ]
})

// Expected output:
// { ok: 1 }
```

**Wait for election (10-30 seconds):**

```shell
# Check replica set status
rs.status()

# Look for:
# - members[0].stateStr: "PRIMARY"
# - members[1].stateStr: "SECONDARY"
#
# Check replica set configuration
rs.conf()

# Exit mongosh
exit
```

---

### Step 3: Verify Replica Set Health

**Check replica set status from outside pod:**

```bash
# Quick status check
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.status().ok"

# Should return: 1 (healthy)

# Detailed status
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.status()" | head -50
```

**Check which node is PRIMARY:**

```bash
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.isMaster().primary"

# Returns: mongodb-0.mongodb-headless.mongo-lab.svc.cluster.local:27017
```

---

### Step 4: Test Data Replication

**Write data to PRIMARY:**

```bash
# Connect to PRIMARY (mongodb-0)
kubectl exec -it -n mongo-lab mongodb-0 -- mongosh

# Create test database and collection
use testdb

db.replication_test.insertOne({
  message: "Testing replication",
  timestamp: new Date(),
  node: "mongodb-0"
})

// Verify write
db.replication_test.find()

exit
```

**Read data from SECONDARY:**

```bash
# Connect to SECONDARY (mongodb-1)
kubectl exec -it -n mongo-lab mongodb-1 -- mongosh

# Enable reading from secondary
db.getMongo().setReadPref("secondary")

// Switch to test database
use testdb

// Read replicated data
db.replication_test.find()

// Should see the document written to PRIMARY

exit
```

---

### Step 5: Test Failover (Optional)

**Simulate PRIMARY failure:**

```bash
# Delete PRIMARY pod
kubectl delete pod mongodb-0 -n mongo-lab

# Watch mongodb-1 become PRIMARY (takes 10-30 seconds)
kubectl exec -n mongo-lab mongodb-1 -- mongosh \
  --eval "rs.isMaster().ismaster"

# Should return: true (mongodb-1 is now PRIMARY)

# Wait for mongodb-0 to restart and rejoin as SECONDARY
kubectl wait --for=condition=ready pod mongodb-0 -n mongo-lab --timeout=180s

# Verify both nodes healthy
kubectl exec -n mongo-lab mongodb-1 -- mongosh \
  --eval "rs.status().members.length"

# Should return: 2
```

---

## Phase 3: Mongo Express Deployment (15-20 minutes)

### Step 1: Deploy Mongo Express

**Mongo Express Deployment:**

```yaml
# deployment-mongo-express.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongo-express
  namespace: mongo-lab
  labels:
    app: mongo-express
    tier: frontend
spec:
  replicas: 1
  strategy:
    type: Recreate  # Ensure clean restart
  selector:
    matchLabels:
      app: mongo-express
  template:
    metadata:
      labels:
        app: mongo-express
        tier: frontend
    spec:
      containers:
        - name: mongo-express
          image: mongo-express:1.0-20-alpine3.19
          env:
            - name: ME_CONFIG_BASICAUTH_ENABLED
              value: "true"
            - name: ME_CONFIG_BASICAUTH_USERNAME
              value: "mongoexpressuser"
            - name: ME_CONFIG_BASICAUTH_PASSWORD
              value: "mongoexpresspass"
            # Replica set connection string
            - name: ME_CONFIG_MONGODB_URL
              value: "mongodb://mongodb-0.mongodb-headless:27017,mongodb-1.mongodb-headless:27017/?replicaSet=rs0"
            - name: ME_CONFIG_MONGODB_ADMINUSERNAME
              value: "root"
            - name: ME_CONFIG_MONGODB_ADMINPASSWORD
              value: "example"
            - name: ME_CONFIG_MONGODB_ENABLE_ADMIN
              value: "true"
            - name: ME_CONFIG_SITE_SSL_ENABLED
              value: "false"
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
```

```bash
# Deploy Mongo Express
kubectl apply -f deployment-mongo-express.yaml

# Wait for pod to be running
kubectl wait --for=condition=ready pod -l app=mongo-express -n mongo-lab --timeout=180s

# Check logs to verify connection
kubectl logs -n mongo-lab deployment/mongo-express --tail=20
```

**Understanding the Connection String:**

```
mongodb://mongodb-0.mongodb-headless:27017,mongodb-1.mongodb-headless:27017/?replicaSet=rs0
```

- Lists both replica set members
- `?replicaSet=rs0` enables automatic failover
- Mongo Express connects to PRIMARY for writes
- If PRIMARY fails, automatically switches to new PRIMARY

---

### Step 2: Create Mongo Express Service

**ClusterIP Service:**

```yaml
# service-mongo-express.yaml
apiVersion: v1
kind: Service
metadata:
  name: mongo-express
  namespace: mongo-lab
  labels:
    app: mongo-express
spec:
  selector:
    app: mongo-express
  type: ClusterIP
  ports:
    - port: 8081
      targetPort: 8081
      protocol: TCP
      name: http
```

```bash
# Apply service
kubectl apply -f service-mongo-express.yaml

# Verify service
kubectl get svc -n mongo-lab mongo-express
```

---

### Step 3: Create Ingress

**Ingress for external access:**

```yaml
# ingress-mongo-express.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mongo-express
  namespace: mongo-lab
spec:
  ingressClassName: nginx
  rules:
    - host: mongoexpress.k3s.test.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mongo-express
                port:
                  number: 8081
```

```bash
# Apply Ingress
kubectl apply -f ingress-mongo-express.yaml

# Verify Ingress created
kubectl get ingress -n mongo-lab
kubectl describe ingress mongo-express -n mongo-lab
```

**Add hostname to /etc/hosts:**

```bash
# Add entry for local access
echo "127.0.0.1 mongoexpress.k3s.test.local" | sudo tee -a /etc/hosts

# Verify entry
grep mongoexpress /etc/hosts
```

---

### Step 4: Access Mongo Express

**Via Browser:**

1. Open: <http://mongoexpress.k3s.test.local>
2. Login with basic auth:
   - Username: `mongoexpressuser`
   - Password: `mongoexpresspass`
3. Should see MongoDB databases

**Via curl:**

```bash
# Test connectivity
curl -u mongoexpressuser:mongoexpresspass http://mongoexpress.k3s.test.local | head -20

# Should return HTML of Mongo Express interface
```

---

### Step 5: Test Database Operations via Mongo Express

**Create test data through UI:**

1. Click "Create Database"
2. Database name: `labtest`
3. Click "Create Collection"
4. Collection name: `items`
5. Insert document:

```json
{
  "name": "Test Item",
  "category": "lab",
  "timestamp": "2025-01-15"
}
```

**Verify replication:**

```bash
# Check data exists in PRIMARY
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "use labtest; db.items.find()"

# Check data replicated to SECONDARY
kubectl exec -n mongo-lab mongodb-1 -- mongosh \
  --eval "db.getMongo().setReadPref('secondary'); use labtest; db.items.find()"
```

---

## Phase 4: PVC Resize Operation (20-25 minutes)

### Step 1: Document Current State

**Check current PVC sizes:**

```bash
# View PVC sizes
kubectl get pvc -n mongo-lab

# Check actual disk usage in pods
echo "=== MongoDB-0 Storage ==="
kubectl exec -n mongo-lab mongodb-0 -- df -h /data/db

echo "=== MongoDB-1 Storage ==="
kubectl exec -n mongo-lab mongodb-1 -- df -h /data/db

# Should show ~2Gi total capacity
```

**Backup StatefulSet configuration:**

```bash
# Save current configuration
kubectl get statefulset mongodb -n mongo-lab -o yaml > statefulset-backup.yaml

# Save current PVC state
kubectl get pvc -n mongo-lab -o yaml > pvc-backup.yaml
```

---

### Step 2: Delete StatefulSet with Cascade Orphan

**Critical concept: `--cascade=orphan` keeps pods running!**

```bash
# Delete StatefulSet but keep pods and PVCs
kubectl delete statefulset mongodb -n mongo-lab --cascade=orphan

# Verify StatefulSet deleted
kubectl get statefulset -n mongo-lab
# Should show: No resources found

# Verify pods still running
kubectl get pods -n mongo-lab
# mongodb-0 and mongodb-1 should still be Running!

# Verify PVCs still bound
kubectl get pvc -n mongo-lab
# Both PVCs should still be Bound

# Test MongoDB still works
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.status().ok"
# Should return: 1 (replica set still healthy)
```

**Why cascade orphan?**

- Pods continue running → no downtime
- PVCs remain attached → no data loss
- StatefulSet controller removed → can modify PVCs
- Allows infrastructure changes without service interruption

---

### Step 3: Resize PVCs

**Patch each PVC to increase size:**

```bash
# Resize mongodb-0 PVC
kubectl patch pvc mongodb-pvc-mongodb-0 -n mongo-lab \
  -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'

# Resize mongodb-1 PVC
kubectl patch pvc mongodb-pvc-mongodb-1 -n mongo-lab \
  -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'

# Check PVC status
kubectl get pvc -n mongo-lab

# Should show CAPACITY: 5Gi or STATUS: Resizing/FileSystemResizePending
```

**Monitor resize progress:**

```bash
# Watch PVC status
kubectl get pvc -n mongo-lab -w

# Check PVC conditions
kubectl describe pvc mongodb-pvc-mongodb-0 -n mongo-lab | grep -A 5 Conditions

# Longhorn may take a few moments to resize volumes
```

---

### Step 4: Update StatefulSet Manifest

**Update volumeClaimTemplates in StatefulSet:**

Edit your `statefulset-mongodb.yaml` and change:

```yaml
volumeClaimTemplates:
  - metadata:
      name: mongodb-pvc
    spec:
      storageClassName: "longhorn"
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 5Gi  # Changed from 2Gi
```

**Reapply StatefulSet:**

```bash
# Apply updated StatefulSet
kubectl apply -f statefulset-mongodb.yaml

# Verify StatefulSet recreated
kubectl get statefulset -n mongo-lab

# StatefulSet controller now manages pods again
# Pods are still the original ones (not restarted yet)
```

---

### Step 5: Rolling Restart Pods

**Restart pods to mount resized filesystems:**

Pods must be restarted for the filesystem to reflect the new size.

```bash
# Delete mongodb-1 (highest ordinal first)
kubectl delete pod mongodb-1 -n mongo-lab

# Wait for mongodb-1 to be ready
kubectl wait --for=condition=ready pod mongodb-1 -n mongo-lab --timeout=180s

# Verify replica set still healthy
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.status().members[1].stateStr"
# Should show: SECONDARY

# Delete mongodb-0 (current PRIMARY)
kubectl delete pod mongodb-0 -n mongo-lab

# Wait for mongodb-0 to be ready
kubectl wait --for=condition=ready pod mongodb-0 -n mongo-lab --timeout=180s

# Verify both nodes healthy
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.status().members.length"
# Should return: 2
```

---

### Step 6: Verify Resize Success

**Check PVC sizes:**

```bash
# Verify PVC capacity
kubectl get pvc -n mongo-lab

# Both should show: CAPACITY: 5Gi
```

**Check filesystem size in pods:**

```bash
# Check mongodb-0 filesystem
echo "=== MongoDB-0 Storage ==="
kubectl exec -n mongo-lab mongodb-0 -- df -h /data/db

# Check mongodb-1 filesystem
echo "=== MongoDB-1 Storage ==="
kubectl exec -n mongo-lab mongodb-1 -- df -h /data/db

# Both should show ~5Gi available
```

**Verify data integrity:**

```bash
# List databases
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "db.adminCommand('listDatabases')"

# Check test data still exists
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "use labtest; db.items.count()"

# Should return: 1 (or however many documents you created)
```

**Verify replica set health:**

```bash
# Full replica set status
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.status()" | grep -E "(stateStr|health)"

# Should show both members healthy
```

**Verify Mongo Express still works:**

```bash
# Test web access
curl -u mongoexpressuser:mongoexpresspass http://mongoexpress.k3s.test.local | grep -i mongo

# Or open in browser: http://mongoexpress.k3s.test.local
```

---

## Troubleshooting Common Issues

### Replica Set Initialization Fails

**Symptoms:**

`rs.initiate()` returns error or `rs.status()` shows issues

**Solutions:**

```bash
# Check MongoDB logs
kubectl logs -n mongo-lab mongodb-0 | tail -50

# Verify replica set configuration uses correct FQDNs
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.conf()"

# If needed, reconfigure replica set
kubectl exec -it -n mongo-lab mongodb-0 -- mongosh
# Inside mongosh:
rs.reconfig(rs.config(),{force:true})
```

---

### Issue 3: Mongo Express Can't Connect

**Symptoms:**

Mongo Express pod logs show connection errors

**Solutions:**

```bash
# Check Mongo Express logs
kubectl logs -n mongo-lab deployment/mongo-express

# Verify MongoDB replica set is healthy
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.status().ok"

# Check Mongo Express environment variables
kubectl get deployment mongo-express -n mongo-lab -o yaml | grep -A 20 "env:"

# Verify connection string format
# Should be: mongodb://mongodb-0.mongodb-headless:27017,mongodb-1.mongodb-headless:27017/?replicaSet=rs0

# Test connection manually from Mongo Express pod
kubectl exec -n mongo-lab deployment/mongo-express -- \
  wget -O- --timeout=5 mongodb-0.mongodb-headless:27017 2>&1 | head -5
```

---

### Issue 4: PVC Resize Not Taking Effect

**Symptoms:**

```
PVC shows 5Gi but filesystem in pod still shows 2Gi
```

**Solutions:**

```bash
# Check PVC conditions
kubectl describe pvc mongodb-pvc-mongodb-0 -n mongo-lab

# If status shows "FileSystemResizePending", pod restart required
kubectl delete pod mongodb-0 -n mongo-lab

# Wait for pod to restart
kubectl wait --for=condition=ready pod mongodb-0 -n mongo-lab --timeout=180s

# Check filesystem again
kubectl exec -n mongo-lab mongodb-0 -- df -h /data/db

# For Longhorn volumes, resize should happen automatically
# If still not showing new size, check Longhorn dashboard
```

---

### Issue 5: Replica Set Unhealthy After Resize

**Symptoms:**

```
rs.status() shows members as UNKNOWN or DOWN
```

**Solutions:**

```bash
# Check pod network connectivity
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "db.adminCommand({ ping: 1 })"

# Verify both pods running
kubectl get pods -n mongo-lab

# Check replica set configuration
kubectl exec -n mongo-lab mongodb-0 -- mongosh \
  --eval "rs.conf()"

# Force reconfiguration if needed
kubectl exec -it -n mongo-lab mongodb-0 -- mongosh
# Inside mongosh:
var config = rs.conf()
rs.reconfig(config, {force: true})

# Wait for election
sleep(10000)
rs.status()
```

---

## Architecture Diagrams

### StatefulSet Architecture

```
┌──────────────────────────────────────────────────────┐
│                 Headless Service                     │
│            mongodb-headless (ClusterIP: None)        │
└────────────────────┬─────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
    ┌────▼──────┐          ┌────▼──────┐
    │ mongodb-0 │          │ mongodb-1 │
    │ (PRIMARY) │◄────────►│(SECONDARY)│
    │   Pod     │ Replica  │   Pod     │
    │           │   Set    │           │
    └────┬──────┘          └────┬──────┘
         │                      │
    ┌────▼──────┐          ┌────▼──────┐
    │ mongodb-  │          │ mongodb-  │
    │ pvc-      │          │ pvc-      │
    │ mongodb-0 │          │ mongodb-1 │
    │  (5Gi)    │          │  (5Gi)    │
    └───────────┘          └───────────┘
         │                      │
    ┌────▼──────────────────────▼──────┐
    │      Longhorn Storage Backend     │
    └───────────────────────────────────┘

Stable DNS:
- mongodb-0.mongodb-headless.mongo-lab.svc.cluster.local
- mongodb-1.mongodb-headless.mongo-lab.svc.cluster.local
```

### Application Access

```
Browser
   │
   ▼
http://mongoexpress.k3s.test.local
   │
   ▼
┌──────────────────┐
│ NGINX Ingress    │
└────────┬─────────┘
         │
    ┌────▼──────┐
    │   Mongo   │
    │  Express  │
    │   Pod     │
    └────┬──────┘
         │
    ┌────▼──────────────────┐
    │  MongoDB Replica Set  │
    │  (both nodes)         │
    │  - Reads from PRIMARY │
    │  - Auto-failover      │
    └───────────────────────┘
```

---

## Cleanup

### Remove Lab Resources

```bash
# Delete namespace (removes everything)
kubectl delete namespace mongo-lab

# Remove /etc/hosts entry
sudo sed -i.bak '/mongoexpress.k3s.test.local/d' /etc/hosts
```

### Selective Cleanup (Keep Some Resources)

```bash
# Remove just Mongo Express
kubectl delete deployment mongo-express -n mongo-lab
kubectl delete svc mongo-express -n mongo-lab
kubectl delete ingress mongo-express -n mongo-lab

# Remove MongoDB (PVCs remain)
kubectl delete statefulset mongodb -n mongo-lab

# Check PVCs
kubectl get pvc -n mongo-lab

# Delete PVCs if done with data
kubectl delete pvc --all -n mongo-lab
```

---

## Learning Outcomes Validation

### StatefulSet Understanding

You should now be able to:

- [ ] Explain when StatefulSet is required vs Deployment
- [ ] Describe how stable network identities work
- [ ] Predict StatefulSet pod naming and creation order
- [ ] Understand volumeClaimTemplates and PVC lifecycle
- [ ] Configure headless Services for StatefulSets

### MongoDB Operations

You should now be able to:

- [ ] Initialize MongoDB replica sets
- [ ] Configure replica set members with stable DNS
- [ ] Understand PRIMARY/SECONDARY roles
- [ ] Test data replication and failover
- [ ] Connect applications to replica sets

### Production Operations

You should now be able to:

- [ ] Perform PVC resize using cascade orphan
- [ ] Update StatefulSet configurations safely
- [ ] Execute rolling restarts of StatefulSet pods
- [ ] Verify data integrity after infrastructure changes
- [ ] Troubleshoot StatefulSet and storage issues

### Kubernetes Patterns

You should now be able to:

- [ ] Use ConfigMaps for application configuration
- [ ] Implement health checks for stateful applications
- [ ] Configure Ingress for internal applications
- [ ] Manage persistent storage in Kubernetes
- [ ] Apply production-safe operational procedures

---

## Key Takeaways

**StatefulSets provide:**

- Stable, predictable pod names (mongodb-0, mongodb-1)
- Ordered, graceful deployment and scaling
- Stable network identities via headless Service
- Persistent storage via volumeClaimTemplates

**Production operations require:**

- Proper health checks (readiness/liveness)
- Configuration management (ConfigMaps)
- Safe update procedures (cascade orphan)
- Validation at every step
- Data backup before changes

**MongoDB replica sets offer:**

- Automatic failover for high availability
- Data replication across nodes
- Read scaling from SECONDARY nodes
- Network partition tolerance

---

**Estimated Completion Time:** 80-105 minutes

**Congratulations!** You've successfully deployed and managed a production-ready MongoDB cluster using Kubernetes StatefulSets, including complex operations like PVC resizing with minimal downtime.
