# Lab Solution: Cluster Lifecycle Management

## Overview

This solution provides step-by-step guidance for mastering essential cluster operations: node maintenance, taints and tolerations, node affinity, and pod anti-affinity.

**Total Duration:** 30 minutes

---

## Phase 1: Safe Node Maintenance (8-10 minutes)

### Step 1: Deploy Sample Application

**Create namespace and deployment:**

```bash
# Create namespace
kubectl create namespace maintenance-lab

# Create deployment with 4 replicas and resource requests
kubectl create deployment nginx-app \
  --image=nginx:alpine \
  --replicas=4 \
  -n maintenance-lab

# Add resource requests to ensure predictable scheduling
kubectl set resources deployment nginx-app \
  -n maintenance-lab \
  --requests=cpu=50m,memory=64Mi \
  --limits=cpu=100m,memory=128Mi

# Wait for deployment to be ready
kubectl wait --for=condition=available deployment/nginx-app \
  -n maintenance-lab --timeout=60s

# Verify pods are running
kubectl get pods -n maintenance-lab -o wide

# Expected output: 4 pods running across available nodes
# NAME                        READY   STATUS    NODE
# nginx-app-xxxx-xxxxx        1/1     Running   node-1
# nginx-app-xxxx-xxxxx        1/1     Running   node-2
# nginx-app-xxxx-xxxxx        1/1     Running   node-1
# nginx-app-xxxx-xxxxx        1/1     Running   node-2
```

---

### Step 2: Identify Cluster Nodes

**List all nodes:**

```bash
# Get all nodes with their status
kubectl get nodes -o wide

# Example output:
# NAME      STATUS   ROLES                  AGE   VERSION
# node-1    Ready    control-plane,master   10d   v1.28.5+k3s1
# node-2    Ready    <none>                 10d   v1.28.5+k3s1
# node-3    Ready    <none>                 10d   v1.28.5+k3s1

# Check which node has the most pods
kubectl get pods -n maintenance-lab -o wide

# Choose a worker node for maintenance (not control-plane)
# For this example, we'll use node-2
```

**Set variable for convenience:**

```bash
# Replace with your actual node name
NODE_TO_MAINTAIN="node-2"
```

---

### Step 3: Cordon the Node

**Mark node as unschedulable:**

```bash
# Cordon the node
kubectl cordon $NODE_TO_MAINTAIN

# Verify node status
kubectl get nodes

# Expected output shows SchedulingDisabled:
# NAME      STATUS                     ROLES    AGE
# node-2    Ready,SchedulingDisabled   <none>   10d

# Check node details
kubectl describe node $NODE_TO_MAINTAIN | grep -A 5 Taints

# Expected output:
# Taints: node.kubernetes.io/unschedulable:NoSchedule
```

**Test that new pods avoid cordoned node:**

```bash
# Scale deployment to create new pods
kubectl scale deployment nginx-app --replicas=6 -n maintenance-lab

# Watch pods being created
kubectl get pods -n maintenance-lab -o wide --watch

# Expected: New pods schedule only to non-cordoned nodes
# Press Ctrl+C to stop watching

# Verify pod distribution
kubectl get pods -n maintenance-lab -o wide | grep $NODE_TO_MAINTAIN | wc -l
# Should show same count as before scaling (pods didn't increase on cordoned node)
```

---

### Step 4: Drain the Node

**Safely evict all pods from the node:**

```bash
# Drain the node
kubectl drain $NODE_TO_MAINTAIN \
  --ignore-daemonsets \
  --delete-emptydir-data

# Expected output:
# node/node-2 cordoned
# WARNING: ignoring DaemonSet-managed Pods: kube-system/...
# evicting pod maintenance-lab/nginx-app-xxxx-xxxxx
# evicting pod maintenance-lab/nginx-app-xxxx-xxxxx
# pod/nginx-app-xxxx-xxxxx evicted
# pod/nginx-app-xxxx-xxxxx evicted
# node/node-2 drained

# Verify node is empty of regular pods
kubectl get pods -n maintenance-lab -o wide | grep $NODE_TO_MAINTAIN

# Expected: No output (no pods on this node)

# Verify pods rescheduled to other nodes
kubectl get pods -n maintenance-lab -o wide

# Expected: All 6 pods running on non-drained nodes
```

**Check what's still running on drained node:**

```bash
# DaemonSets are still present (they tolerate the cordon taint)
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE_TO_MAINTAIN

# Expected output: Only DaemonSet pods (kube-proxy, etc.)
```

---

### Step 5: Simulate Maintenance

**In production, you would now perform maintenance:**

```bash
# Example maintenance commands (DO NOT RUN in shared lab):
# ssh $NODE_TO_MAINTAIN
# sudo apt update && sudo apt upgrade -y
# sudo reboot

# For this lab, we'll just simulate with a wait
echo "Simulating 10 seconds of maintenance..."
sleep 10
echo "Maintenance complete!"
```

---

### Step 6: Return Node to Service

**Uncordon the node:**

```bash
# Mark node as schedulable again
kubectl uncordon $NODE_TO_MAINTAIN

# Verify node status returns to normal
kubectl get nodes

# Expected output:
# NAME      STATUS   ROLES    AGE
# node-2    Ready    <none>   10d

# Check taints are removed
kubectl describe node $NODE_TO_MAINTAIN | grep Taints

# Expected output:
# Taints: <none>
```

**Test new pods can schedule to uncordoned node:**

```bash
# Scale deployment up
kubectl scale deployment nginx-app --replicas=8 -n maintenance-lab

# Watch where new pods schedule
kubectl get pods -n maintenance-lab -o wide

# Expected: New pods can now schedule to previously drained node

# Scale back to original
kubectl scale deployment nginx-app --replicas=4 -n maintenance-lab
```

---

### Phase 1 Summary

**What you learned:**

```plaintext
Cordon:
✓ Prevents NEW pods from scheduling to node
✓ Existing pods continue running
✓ Use before maintenance to stop new workloads

Drain:
✓ Cordons the node
✓ Evicts ALL pods (except DaemonSets)
✓ Pods reschedule to other nodes
✓ Node is empty and ready for maintenance

Uncordon:
✓ Removes scheduling restriction
✓ Node can accept new pods again
✓ Existing pods DON'T automatically move back

Real-world: This enables zero-downtime node maintenance
```

---

## Phase 2: Taints and Tolerations (8-10 minutes)

### Step 1: Label and Taint Node for Production

**Choose a node to reserve for production workloads:**

```bash
# Use a worker node (not control-plane)
PROD_NODE="node-2"

# Label the node
kubectl label nodes $PROD_NODE environment=production

# Verify label
kubectl get nodes --show-labels | grep $PROD_NODE

# Apply taint to reserve this node
kubectl taint nodes $PROD_NODE environment=production:NoSchedule

# Verify taint
kubectl describe node $PROD_NODE | grep -A 3 Taints

# Expected output:
# Taints: environment=production:NoSchedule
```

---

### Step 2: Deploy Workload Without Toleration

**Create pod that cannot tolerate the taint:**

```bash
# Create simple nginx pod (no toleration)
kubectl run nginx-no-toleration \
  --image=nginx:alpine \
  -n maintenance-lab

# Check pod status
kubectl get pods nginx-no-toleration -n maintenance-lab

# Expected: Running (but NOT on tainted node)

# Verify pod is NOT on tainted node
kubectl get pod nginx-no-toleration -n maintenance-lab -o wide | grep $PROD_NODE

# Expected: No output (pod avoided tainted node)

# Check where pod scheduled
kubectl get pod nginx-no-toleration -n maintenance-lab -o wide

# Expected: Pod is on a non-tainted node
```

**See scheduling decisions in events:**

```bash
# View pod events
kubectl describe pod nginx-no-toleration -n maintenance-lab | grep -A 10 Events

# You may see scheduler chose a non-tainted node
```

---

### Step 3: Deploy Production Workload With Toleration

**Create deployment that tolerates the production taint:**

```yaml
# Create file: production-app.yaml
cat <<EOF > production-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-app
  namespace: maintenance-lab
  labels:
    app: production-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: production-app
  template:
    metadata:
      labels:
        app: production-app
    spec:
      tolerations:
      - key: "environment"
        operator: "Equal"
        value: "production"
        effect: "NoSchedule"
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF
```

**Deploy the production application:**

```bash
# Apply the deployment
kubectl apply -f production-app.yaml

# Wait for deployment
kubectl wait --for=condition=available deployment/production-app \
  -n maintenance-lab --timeout=60s

# Check where pods scheduled
kubectl get pods -n maintenance-lab -l app=production-app -o wide

# Expected: Pods CAN schedule on tainted node (and likely do)
```

**Verify toleration allows scheduling to tainted node:**

```bash
# Count pods on tainted node
kubectl get pods -n maintenance-lab -l app=production-app -o wide | grep $PROD_NODE | wc -l

# Should show pods running on the production node

# Verify regular pods still cannot
kubectl get pods -n maintenance-lab -o wide | grep nginx-no-toleration | grep $PROD_NODE

# Expected: No output (regular pod not on tainted node)
```

---

### Step 4: Test Capacity Limits

**Try to overload untainted nodes:**

```bash
# Get number of untainted nodes
UNTAINTED_COUNT=$(kubectl get nodes --no-headers | grep -v $PROD_NODE | grep -v "SchedulingDisabled" | wc -l)

echo "Untainted nodes: $UNTAINTED_COUNT"

# Create deployment without toleration
cat <<EOF > development-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: development-app
  namespace: maintenance-lab
spec:
  replicas: $UNTAINTED_COUNT
  selector:
    matchLabels:
      app: development-app
  template:
    metadata:
      labels:
        app: development-app
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
EOF

kubectl apply -f development-app.yaml

# Verify distribution
kubectl get pods -n maintenance-lab -l app=development-app -o wide

# All pods on untainted nodes only
```

**Scale beyond untainted capacity:**

```bash
# Scale to more replicas than untainted nodes can hold
# Adjust based on your cluster capacity
kubectl scale deployment development-app --replicas=10 -n maintenance-lab

# Check pod status
kubectl get pods -n maintenance-lab -l app=development-app

# Some pods may be Pending if cluster capacity reached

# Check pending pod details
kubectl describe pod -n maintenance-lab -l app=development-app | grep -A 5 "FailedScheduling"

# Expected: Logs about taint not being tolerated
```

---

### Step 5: Remove Taint

**Clean up the taint:**

```bash
# Remove taint from node
kubectl taint nodes $PROD_NODE environment=production:NoSchedule-

# Note the minus (-) at the end removes the taint

# Verify taint is gone
kubectl describe node $PROD_NODE | grep Taints

# Expected output:
# Taints: <none>

# Observe pending pods now schedule
kubectl get pods -n maintenance-lab -l app=development-app -o wide

# Previously pending pods should now be Running
```

---

### Phase 2 Summary

**What you learned:**

```plaintext
Taints (on nodes):
✓ Repel pods unless they have matching tolerations
✓ Three effects: NoSchedule, PreferNoSchedule, NoExecute
✓ Format: key=value:effect

Tolerations (on pods):
✓ Allow pods to schedule on tainted nodes
✓ Match taint key, value, and effect
✓ Operator: Equal (exact match) or Exists (any value)

Use cases:
✓ Reserve expensive/specialized nodes
✓ Separate production from development
✓ Isolate workloads by team or purpose
✓ Gracefully decommission nodes (NoExecute)

Real-world: Prevents accidental resource consumption on special nodes
```

---

## Phase 3: Node Affinity (6-8 minutes)

### Step 1: Label Nodes with Characteristics

**Verify cluster has sufficient worker nodes:**

```bash
# Check worker node count
WORKER_COUNT=$(kubectl get nodes --no-headers | grep -v "control-plane" | wc -l)
echo "Worker nodes available: $WORKER_COUNT"

if [ $WORKER_COUNT -lt 2 ]; then
  echo "⚠️  Warning: This phase works best with 2+ worker nodes."
  echo "You can still complete it, but you'll need to use the same node for different labels."
fi
```

**Apply labels to simulate different node types:**

```bash
# Get list of worker nodes (not control-plane)
kubectl get nodes --no-headers | grep -v "control-plane" | awk '{print $1}'

# Label first worker node as SSD
NODE_SSD=$(kubectl get nodes --no-headers | grep -v "control-plane" | awk '{print $1}' | head -n 1)
kubectl label nodes $NODE_SSD disktype=ssd

# Label second worker node as HDD
NODE_HDD=$(kubectl get nodes --no-headers | grep -v "control-plane" | awk '{print $1}' | head -n 2 | tail -n 1)
kubectl label nodes $NODE_HDD disktype=hdd

# Label one node with high memory
kubectl label nodes $NODE_SSD memory=high

# Verify labels
kubectl get nodes --show-labels | grep -E "disktype|memory"

echo "SSD Node: $NODE_SSD"
echo "HDD Node: $NODE_HDD"
```

---

### Step 2: Deploy with Required Node Affinity

**Create deployment that REQUIRES SSD node:**

```yaml
# Create file: database-app.yaml
cat <<EOF > database-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database-app
  namespace: maintenance-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: disktype
                operator: In
                values:
                - ssd
      containers:
      - name: postgres
        image: postgres:alpine
        env:
        - name: POSTGRES_PASSWORD
          value: "example"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF
```

**Deploy and verify:**

```bash
# Apply deployment
kubectl apply -f database-app.yaml

# Check pod placement
kubectl get pods -n maintenance-lab -l app=database -o wide

# Expected: ALL pods on the SSD node only

# Verify with grep
kubectl get pods -n maintenance-lab -l app=database -o wide | grep $NODE_SSD | wc -l
# Should match replica count (2)

kubectl get pods -n maintenance-lab -l app=database -o wide | grep $NODE_HDD | wc -l
# Should be 0 (no pods on HDD node)
```

**Test scaling beyond node capacity:**

```bash
# Scale to more pods than node can handle
kubectl scale deployment database-app --replicas=20 -n maintenance-lab

# Check pod status
kubectl get pods -n maintenance-lab -l app=database

# Some pods may be Pending if node capacity reached

# Check why pending
kubectl describe pod -n maintenance-lab -l app=database | grep -A 5 "Warning"

# Expected: Insufficient CPU/memory on nodes matching affinity

# Scale back
kubectl scale deployment database-app --replicas=2 -n maintenance-lab
```

---

### Step 3: Deploy with Preferred Node Affinity

**Create deployment that PREFERS high-memory nodes:**

```yaml
# Create file: cache-app.yaml
cat <<EOF > cache-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache-app
  namespace: maintenance-lab
spec:
  replicas: 3
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: memory
                operator: In
                values:
                - high
      containers:
      - name: redis
        image: redis:alpine
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
EOF
```

**Deploy and observe scheduling preference:**

```bash
# Apply deployment
kubectl apply -f cache-app.yaml

# Check pod placement
kubectl get pods -n maintenance-lab -l app=cache -o wide

# Expected: Scheduler PREFERS high-memory node but will use others

# Count pods on preferred node
kubectl get pods -n maintenance-lab -l app=cache -o wide | grep $NODE_SSD | wc -l

# Should show preference for high-memory node
# But if scaled beyond capacity, pods overflow to other nodes

# Scale to see overflow
kubectl scale deployment cache-app --replicas=8 -n maintenance-lab

kubectl get pods -n maintenance-lab -l app=cache -o wide

# Expected: Multiple pods on preferred node, others on different nodes
```

---

### Step 4: Combine Required and Preferred

**Create deployment with both affinity types:**

```yaml
# Create file: analytics-app.yaml
cat <<EOF > analytics-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics-app
  namespace: maintenance-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: analytics
  template:
    metadata:
      labels:
        app: analytics
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: disktype
                operator: In
                values:
                - ssd
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 80
            preference:
              matchExpressions:
              - key: memory
                operator: In
                values:
                - high
      containers:
      - name: analytics
        image: nginx:alpine
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
EOF
```

**Deploy and verify combined behavior:**

```bash
# Apply deployment
kubectl apply -f analytics-app.yaml

# Check placement
kubectl get pods -n maintenance-lab -l app=analytics -o wide

# Expected: Pods MUST be on SSD node (required)
# AND scheduler PREFERS it to be the high-memory node
# Since NODE_SSD has both labels, all pods go there

# Verify
kubectl get pods -n maintenance-lab -l app=analytics -o wide | grep $NODE_SSD
# All analytics pods should be on this node
```

---

### Phase 3 Summary

**What you learned:**

```plaintext
Required Affinity:
✓ Hard constraint (pod won't schedule without it)
✓ requiredDuringSchedulingIgnoredDuringExecution
✓ Pod will be Pending if no matching node exists

Preferred Affinity:
✓ Soft preference (scheduler tries to satisfy)
✓ preferredDuringSchedulingIgnoredDuringExecution
✓ Weight determines priority (1-100)
✓ Pod will schedule even if preference not met

Operators:
✓ In: Value in list
✓ NotIn: Value not in list
✓ Exists: Key exists (any value)
✓ DoesNotExist: Key doesn't exist
✓ Gt/Lt: Numeric comparisons

Use cases:
✓ Target specific hardware characteristics
✓ Data locality (same zone/region)
✓ Separate prod/dev environments
✓ Cost optimization

Real-world: Ensures workloads run on appropriate infrastructure
```

---

## Phase 4: Pod Anti-Affinity for High Availability (6-8 minutes)

### Step 1: Deploy Without Anti-Affinity (Baseline)

**Create basic deployment:**

```bash
# Create simple deployment
kubectl create deployment frontend-basic \
  --image=nginx:alpine \
  --replicas=3 \
  -n maintenance-lab

# Check distribution
kubectl get pods -n maintenance-lab -l app=frontend-basic -o wide

# Note: Pods may cluster on same node (no anti-affinity)
# Count per node
for node in $(kubectl get nodes --no-headers | awk '{print $1}'); do
  echo -n "$node: "
  kubectl get pods -n maintenance-lab -l app=frontend-basic -o wide | grep $node | wc -l
done
```

---

### Step 2: Deploy With Pod Anti-Affinity

**Create deployment with anti-affinity for high availability:**

```yaml
# Create file: frontend-ha.yaml
cat <<EOF > frontend-ha.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-ha
  namespace: maintenance-lab
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend-ha
  template:
    metadata:
      labels:
        app: frontend-ha
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - frontend-ha
            topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
EOF
```

**Deploy and verify spread:**

```bash
# Apply deployment
kubectl apply -f frontend-ha.yaml

# Check pod distribution
kubectl get pods -n maintenance-lab -l app=frontend-ha -o wide

# Expected: Each pod on DIFFERENT node

# Verify distribution
for node in $(kubectl get nodes --no-headers | awk '{print $1}'); do
  count=$(kubectl get pods -n maintenance-lab -l app=frontend-ha -o wide | grep $node | wc -l)
  echo "$node: $count pods"
done

# Expected: Max 1 pod per node
```

---

### Step 3: Test High Availability During Node Maintenance

**Simulate node failure/maintenance:**

```bash
# Choose node with an anti-affinity pod
HA_POD_NODE=$(kubectl get pods -n maintenance-lab -l app=frontend-ha -o wide | tail -n 1 | awk '{print $7}')

echo "Draining node: $HA_POD_NODE"

# Cordon and drain
kubectl cordon $HA_POD_NODE
kubectl drain $HA_POD_NODE --ignore-daemonsets --delete-emptydir-data

# Watch pod rescheduling
kubectl get pods -n maintenance-lab -l app=frontend-ha -o wide

# Expected: Evicted pod reschedules to different node
# All pods remain on separate nodes

# Verify spread is maintained
for node in $(kubectl get nodes --no-headers | grep -v "SchedulingDisabled" | awk '{print $1}'); do
  count=$(kubectl get pods -n maintenance-lab -l app=frontend-ha -o wide | grep $node | wc -l)
  echo "$node: $count pods"
done

# Uncordon node
kubectl uncordon $HA_POD_NODE
```

---

### Step 4: Scale Beyond Node Count

**Test anti-affinity limits:**

```bash
# Get number of nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)

echo "Cluster has $NODE_COUNT nodes"

# Scale to more replicas than nodes
kubectl scale deployment frontend-ha --replicas=$((NODE_COUNT + 2)) -n maintenance-lab

# Check pod status
kubectl get pods -n maintenance-lab -l app=frontend-ha

# Expected: Some pods in Pending state

# Check why pods are pending
kubectl describe pod -n maintenance-lab -l app=frontend-ha | grep -A 10 "Warning.*FailedScheduling"

# Expected: No nodes satisfy pod anti-affinity requirements

# View specific error
kubectl get events -n maintenance-lab --sort-by='.lastTimestamp' | grep -i "didn't match pod anti-affinity"

# Scale back to achievable replicas
kubectl scale deployment frontend-ha --replicas=3 -n maintenance-lab
```

---

### Step 5: Compare Preferred vs Required Anti-Affinity

**Create deployment with preferred anti-affinity:**

```yaml
# Create file: frontend-preferred.yaml
cat <<EOF > frontend-preferred.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-preferred
  namespace: maintenance-lab
spec:
  replicas: 5
  selector:
    matchLabels:
      app: frontend-preferred
  template:
    metadata:
      labels:
        app: frontend-preferred
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - frontend-preferred
              topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
EOF
```

**Deploy and observe difference:**

```bash
# Apply deployment
kubectl apply -f frontend-preferred.yaml

# Check distribution
kubectl get pods -n maintenance-lab -l app=frontend-preferred -o wide

# Expected: Scheduler TRIES to spread, but allows multiple per node if needed

# Count per node
for node in $(kubectl get nodes --no-headers | awk '{print $1}'); do
  count=$(kubectl get pods -n maintenance-lab -l app=frontend-preferred -o wide | grep $node | wc -l)
  echo "$node: $count pods"
done

# Expected: Spread is attempted, but some nodes may have multiple pods
```

---

### Phase 4 Summary

**What you learned:**

```plaintext
Pod Anti-Affinity:
✓ Spreads pods across topology domains (nodes, zones, regions)
✓ Essential for high availability
✓ Uses labelSelector to identify pods to avoid

TopologyKey:
✓ kubernetes.io/hostname = different nodes
✓ topology.kubernetes.io/zone = different availability zones
✓ topology.kubernetes.io/region = different regions

Required vs Preferred:
✓ Required: Strict enforcement (pods may remain Pending)
✓ Preferred: Best effort (always schedules, even if not spread)

Pod Affinity (opposite):
✓ Co-locates pods (e.g., cache near application)
✓ Same configuration, opposite intent

Use cases:
✓ High availability (spread replicas)
✓ Avoid noisy neighbor issues
✓ Disaster recovery (zone/region spread)

Trade-offs:
✓ Limits scalability (can't scale beyond topology count)
✓ May waste resources (empty capacity on some nodes)
✓ Balance availability vs efficiency

Real-world: Critical for production resilience
```

---

## Complete Lab Summary

### Skills Acquired

**Node Management:**

- Safely cordon nodes before maintenance
- Drain nodes to evacuate workloads gracefully
- Return nodes to service with uncordon
- Handle DaemonSets and local storage during drain

**Taints and Tolerations:**

- Reserve nodes for specific workloads
- Create tolerations to overcome taints
- Understand NoSchedule, PreferNoSchedule, NoExecute effects
- Protect expensive or specialized nodes

**Node Affinity:**

- Target nodes with specific characteristics
- Use required affinity for hard constraints
- Use preferred affinity for soft preferences
- Combine multiple affinity rules

**Pod Anti-Affinity:**

- Spread replicas for high availability
- Use topologyKey to define separation domains
- Balance availability and scalability
- Choose between required and preferred enforcement

---

## Production Readiness Checklist

- [ ] Documented node maintenance procedures
- [ ] PodDisruptionBudgets configured for critical applications
- [ ] Node labels standardized across cluster
- [ ] Taints applied to specialized nodes
- [ ] Critical workloads use anti-affinity for HA
- [ ] Resource requests/limits defined (prevents oversubscription)
- [ ] Monitoring alerts for pending pods
- [ ] Runbooks for common drain issues

---

## Troubleshooting Reference

### Drain Won't Complete

**Problem:** `kubectl drain` hangs or fails

**Common Causes:**

1. **PodDisruptionBudget preventing eviction:**

```bash
kubectl get pdb -A
kubectl describe pdb <pdb-name> -n <namespace>
# Temporarily delete or adjust PDB if safe
```

2. **Standalone pods (not managed by controller):**

```bash
kubectl get pods -A --field-selector spec.nodeName=<node> -o json | \
  jq '.items[] | select(.metadata.ownerReferences == null) | .metadata.name'
# Use --force flag to delete standalone pods
```

3. **Pods with local data (emptyDir):**

```bash
# Use --delete-emptydir-data flag (data will be lost)
kubectl drain <node> --delete-emptydir-data --ignore-daemonsets
```

### Pods Pending After Creating Affinity/Anti-Affinity

**Problem:** Pods stuck in Pending state

**Debug Steps:**

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check available nodes
kubectl get nodes

# Verify node labels
kubectl get nodes --show-labels

# Check if affinity requirements can be satisfied
kubectl get nodes -l <your-affinity-label>

# For anti-affinity, check if enough nodes exist
kubectl get nodes --no-headers | wc -l
```

### Tolerations Not Working

**Problem:** Pods still can't schedule to tainted node

**Debug Steps:**

```bash
# Verify taint exists
kubectl describe node <node> | grep Taints

# Check pod toleration
kubectl get pod <pod> -o yaml | grep -A 10 tolerations

# Common mistakes:
# 1. Typo in key/value
# 2. Wrong operator (Equal vs Exists)
# 3. Wrong effect (NoSchedule vs NoExecute)
# 4. Missing effect field
```

---

## Cleanup

**Remove all lab resources:**

```bash
# Delete namespace (removes all deployments, pods)
kubectl delete namespace maintenance-lab

# Remove node labels
kubectl label nodes --all environment- disktype- memory-

# Remove taints (if any remain)
kubectl taint nodes --all environment-

# Uncordon any cordoned nodes
kubectl uncordon --all

# Verify cleanup
kubectl get nodes --show-labels
kubectl describe nodes | grep Taints
```

---

## Next Steps

**Advanced Topics to Explore:**

1. **PodDisruptionBudgets (PDB):**
   - Control how many pods can be disrupted simultaneously
   - Essential for production workloads
   - Example: `maxUnavailable: 1` ensures at least n-1 replicas always running

2. **Topology Spread Constraints:**
   - More flexible than anti-affinity
   - Can spread across multiple topology domains
   - Fine-grained control over distribution

3. **Descheduler:**
   - Automatically rebalances pods across nodes
   - Fixes imbalanced clusters after maintenance
   - Can be configured with various strategies

4. **Custom Schedulers:**
   - Implement custom scheduling logic
   - Integrate with external systems
   - Advanced placement strategies

**Real-World Scenarios:**

- Multi-zone deployments for disaster recovery
- Mixed workload clusters (batch + interactive)
- Cost optimization (prefer cheaper node types)
- GPU/specialized hardware management
- Compliance and data residency requirements

---

**Estimated Completion Time:** 30 minutes
**Difficulty:** Intermediate
**Learning Validation:** Students can safely maintain nodes and control workload placement with precision
