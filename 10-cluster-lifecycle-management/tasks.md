# Lab: Cluster Lifecycle Management - Tasks

## Overview

**Difficulty:** Intermediate

In this lab, you'll learn essential cluster operations skills that every Kubernetes administrator needs:

- Safe node maintenance procedures
- Controlling workload placement with taints and tolerations
- Targeting specific nodes with affinity rules
- Implementing high availability with pod anti-affinity

**Scenario:** You manage a small Kubernetes cluster with limited resources. You need to perform routine maintenance while ensuring workloads are placed optimally and services remain highly available.

---

## Prerequisites

- k3s or equivalent Kubernetes cluster with at least 2 nodes
- cluster-admin access

---

## Phase 1: Safe Node Maintenance (8-10 minutes)

**Objective:** Learn to safely evacuate workloads from a node for maintenance

### Your Tasks

1. **Deploy a sample application with multiple replicas**
   - Create namespace `maintenance-lab`
   - Deploy nginx with 4 replicas
   - Verify pods are distributed across nodes

2. **Identify nodes in your cluster**
   - List all nodes
   - Note which nodes are running your application pods
   - Choose one worker node for "maintenance"

3. **Cordon the node**
   - Mark your chosen node as unschedulable
   - Verify the node status changes
   - Scale your deployment to 6 replicas
   - Observe that new pods avoid the cordoned node

4. **Drain the node**
   - Safely evict all pods from the cordoned node
   - Watch pods relocate to other nodes
   - Verify the node is empty (except DaemonSets)

5. **Return node to service**
   - Uncordon the node
   - Scale deployment back to 4 replicas
   - Observe new pods can now schedule to the node

### Challenge Questions

- What happens to pods on a cordoned node?
- Why doesn't uncordon automatically move pods back?
- What flags are commonly needed with `kubectl drain`?
- How would you handle a node that won't drain?

---

## Phase 2: Taints and Tolerations (8-10 minutes)

**Objective:** Reserve specific nodes for specific workloads using taints and tolerations

### Your Tasks

1. **Label and taint a node for "production" workloads**
   - Label one node with `environment=production`
   - Apply a taint: `environment=production:NoSchedule`
   - Verify the taint is applied

2. **Deploy a workload without toleration**
   - Deploy a simple nginx pod (without any tolerations)
   - Observe it cannot schedule to the tainted node
   - Check pod events to see the scheduling failure reason

3. **Deploy a "production" workload with toleration**
   - Create a deployment with toleration for `environment=production`
   - Verify these pods CAN schedule to the tainted node
   - Confirm regular pods still cannot

4. **Test taint effects**
   - Create another deployment without toleration
   - Scale it to match the number of available (untainted) nodes
   - Observe all pods schedule successfully on untainted nodes
   - Try to scale beyond capacity - pods should be Pending

5. **Clean up taints**
   - Remove the taint from the node
   - Observe pending pods now schedule successfully

### Challenge Questions

- What's the difference between NoSchedule and PreferNoSchedule?
- When would you use NoExecute effect?
- Can you taint all nodes in a cluster?
- How do DaemonSets work with taints?

---

## Phase 3: Node Affinity (6-8 minutes)

**Objective:** Use node affinity to target workloads to specific node types

### Your Tasks

1. **Label nodes with characteristics**
   - Label one node with `disktype=ssd`
   - Label another node with `disktype=hdd`
   - Label one node with `memory=high`
   - Verify labels are applied

2. **Deploy with required node affinity**
   - Create a deployment that REQUIRES `disktype=ssd`
   - Verify pods only schedule to the SSD-labeled node
   - Try to scale beyond the node's capacity
   - Observe pods remain Pending (no suitable node)

3. **Deploy with preferred node affinity**
   - Create a deployment that PREFERS `memory=high` nodes
   - Scale to more replicas than the high-memory node can hold
   - Observe scheduler places pods on preferred node first
   - Additional pods overflow to other nodes

4. **Combine multiple affinity rules**
   - Create a deployment that REQUIRES `disktype=ssd` AND PREFERS `memory=high`
   - Observe scheduling behavior
   - Understand how required and preferred rules interact

### Challenge Questions

- What happens if no nodes match required affinity?
- How does preferred affinity weight affect scheduling?
- Can you use multiple required affinity terms?
- How is node affinity different from nodeSelector?

---

## Phase 4: Pod Anti-Affinity for High Availability (6-8 minutes)

**Objective:** Use pod anti-affinity to spread replicas across nodes for resilience

### Your Tasks

1. **Deploy without anti-affinity (baseline)**
   - Create a deployment with 3 replicas (no affinity rules)
   - Observe pod distribution across nodes
   - Note: Pods may cluster on same node

2. **Deploy with pod anti-affinity**
   - Create a deployment with 3 replicas
   - Add podAntiAffinity rule to avoid pods with same app label
   - Use `kubernetes.io/hostname` as topologyKey
   - Verify each replica is on a different node

3. **Test high availability**
   - Cordon one node running an anti-affinity pod
   - Drain that node
   - Observe the evicted pod reschedules to a different node
   - Verify replicas remain spread across nodes

4. **Scale and observe limits**
   - Scale anti-affinity deployment to more replicas than you have nodes
   - Observe some pods remain Pending (anti-affinity cannot be satisfied)
   - Understand the trade-off between availability and capacity

### Challenge Questions

- What's the difference between required and preferred anti-affinity?
- When would you use pod affinity (co-location)?
- What is topologyKey and why is it important?
- How does anti-affinity affect deployment scalability?

---

## Success Criteria

- [ ] Successfully cordoned, drained, and uncordoned a node
- [ ] Observed pod rescheduling during drain operation
- [ ] Applied taints to reserve nodes for specific workloads
- [ ] Created pods with tolerations that can schedule to tainted nodes
- [ ] Used required node affinity to target specific node labels
- [ ] Used preferred node affinity for soft scheduling preferences
- [ ] Implemented pod anti-affinity for high availability
- [ ] Verified replicas spread across different nodes
- [ ] Understand when to use each scheduling mechanism

---

## Cleanup

```bash
# Delete namespace (removes all resources)
kubectl delete namespace maintenance-lab

# Remove node labels
kubectl label nodes <node-name> environment- disktype- memory-

# Remove node taints
kubectl taint nodes <node-name> environment-

# Uncordon any cordoned nodes
kubectl uncordon --all
```

---

## Key Takeaways

**Node Management:**

- Cordon prevents new pods, drain removes existing pods
- Always drain before maintenance to avoid disruption
- Uncordon doesn't automatically rebalance workloads

**Taints and Tolerations:**

- Taints repel pods unless they have matching tolerations
- Use taints to reserve nodes for specific purposes
- NoSchedule, PreferNoSchedule, and NoExecute effects serve different purposes

**Node Affinity:**

- Required affinity = hard constraint (pod won't schedule without it)
- Preferred affinity = soft preference (scheduler tries to satisfy)
- Use for targeting nodes with specific characteristics

**Pod Anti-Affinity:**

- Spreads replicas across topology domains (nodes, zones, regions)
- Critical for high availability
- Can limit scalability if strictly enforced

**When to Use What:**

- Node maintenance → Cordon and drain
- Reserve expensive/specialized nodes → Taints + tolerations
- Target specific hardware → Node affinity
- High availability → Pod anti-affinity
- Co-location for performance → Pod affinity

---

## Next Steps

After mastering these basics, explore:

- Pod Disruption Budgets (PDB) for controlled disruption
- Descheduler for automatic workload rebalancing
- Topology Spread Constraints for even distribution
- Combining multiple scheduling constraints for complex requirements
