# Lab: Advanced Workload Management - StatefulSets and Operations

## Scenario

Your organization needs to deploy a highly available MongoDB database cluster for a critical internal application.
The database must support automatic failover, persistent storage, and be manageable through a web interface.

**Business Requirements:**

- High availability through MongoDB replica set (min. 2 nodes)
- Persistent storage that survives pod restarts
- Stable network identities for database cluster members
- Web-based administration interface
- Ability to scale storage as data grows

**Technical Constraints:**

- Use Longhorn distributed storage for data persistence
- Deploy in `mongo-lab` namespace
- Expose Mongo Express via Ingress
- MongoDB replica set name: `rs0`

---

## Prerequisites

- k3s cluster running
- Longhorn storage system installed and operational
- NGINX Ingress Controller deployed
- kubectl configured and operational
- Completion of Modules 1-7

---

## Your Tasks

### Phase 1: StatefulSet Deployment (30-40 minutes)

**Objective:** Deploy a 2-node MongoDB cluster using StatefulSet with persistent storage.

**Requirements:**

- Create `mongo-lab` namespace
- Deploy MongoDB configuration via ConfigMap
- Create headless Service for StatefulSet
- Deploy MongoDB StatefulSet with 2 replicas
- Use Longhorn storage class with 2Gi PVCs per pod
- Verify stable pod naming and DNS records

**Challenge Questions:**

- How does StatefulSet naming differ from Deployment pod names?
- What happens to PVCs when you scale down a StatefulSet?
- What is the purpose of the headless Service?
- Why does MongoDB need stable network identities?

**Success Criteria:**

- [ ] Namespace created and configured
- [ ] MongoDB ConfigMap deployed with replica set configuration
- [ ] Headless Service created (clusterIP: None)
- [ ] StatefulSet running with 2 healthy pods (mongodb-0, mongodb-1)
- [ ] Each pod has its own PVC (mongodb-pvc-mongodb-0, mongodb-pvc-mongodb-1)
- [ ] Stable DNS records accessible for each pod

---

### Phase 2: MongoDB Replica Set Initialization (15-20 minutes)

**Objective:** Initialize MongoDB replica set to enable automatic failover and data replication.

**Requirements:**

- Connect to primary MongoDB pod (mongodb-0)
- Initialize replica set with both members
- Configure stable DNS names for cluster members
- Verify replica set status shows one PRIMARY and one SECONDARY
- Test data replication between nodes

**Challenge Questions:**

- What is the difference between PRIMARY and SECONDARY roles?
- How does MongoDB discover other replica set members?
- What happens if the PRIMARY node fails?
- Why use fully qualified domain names (FQDN) in replica set configuration?

**Success Criteria:**

- [ ] Replica set initialized with name "rs0"
- [ ] Both nodes joined to replica set
- [ ] One node elected as PRIMARY
- [ ] One node serving as SECONDARY
- [ ] Replica set health verified

---

### Phase 3: Mongo Express Deployment (15-20 minutes)

**Objective:** Deploy web-based MongoDB administration interface with replica set support.

**Requirements:**

- Deploy Mongo Express connecting to MongoDB replica set
- Configure replica set connection string
- Enable basic authentication for web interface
- Verify connectivity to MongoDB cluster
- Expose via Ingress

**Challenge Questions:**

- How does the connection string differ for replica sets vs single instances?

**Success Criteria:**

- [ ] Mongo Express deployed and running
- [ ] Connected to MongoDB replica set (both nodes)
- [ ] Basic authentication working
- [ ] Ingress configured and accessible via browser
- [ ] Can view databases and collections through UI

---

### Phase 4: PVC Resize Operation (20-25 minutes)

**Objective:** Increase MongoDB storage capacity without data loss using production-safe procedures.

**Requirements:**

- Document current PVC sizes (2Gi)
- Use `--cascade=orphan` to delete StatefulSet while keeping pods
- Resize PVCs from 2Gi to 5Gi
- Update StatefulSet volumeClaimTemplates
- Perform rolling restart of pods
- Verify resized storage and data integrity

**Challenge Questions:**

- What does `--cascade=orphan` do and why is it useful?
- Why can't you directly edit PVC size in StatefulSet?
- What happens to data during PVC resize?
- How does Longhorn handle volume expansion?

**Success Criteria:**

- [ ] Original PVC sizes documented
- [ ] StatefulSet deleted with orphan cascade (pods still running)
- [ ] All PVCs resized to 5Gi
- [ ] StatefulSet reapplied with updated volumeClaimTemplates
- [ ] Pods restarted one at a time
- [ ] Filesystem reflects new 5Gi size in all pods
- [ ] MongoDB replica set remains healthy throughout
- [ ] All data preserved and accessible

---

## Validation Checklist

**Infrastructure:**

- [ ] `mongo-lab` namespace exists
- [ ] Longhorn storage class available
- [ ] NGINX Ingress Controller operational

**MongoDB Cluster:**

- [ ] 2 MongoDB pods running (mongodb-0, mongodb-1)
- [ ] Each pod has dedicated PVC
- [ ] Replica set initialized and healthy
- [ ] One PRIMARY, one SECONDARY
- [ ] Data replication working

**Application Access:**

- [ ] Mongo Express accessible via Ingress
- [ ] Basic authentication working
- [ ] Can manage databases through UI
- [ ] Can view replica set status

**Storage Operations:**

- [ ] PVCs resized to 5Gi
- [ ] Filesystem shows increased capacity
- [ ] No data loss during resize
- [ ] StatefulSet volumeClaimTemplates updated

---

## Key Learning Outcomes

After completing this lab, you should be able to:

**StatefulSet Concepts:**

- Explain when to use StatefulSet vs Deployment
- Describe how stable network identities work
- Predict StatefulSet scaling behavior
- Understand volumeClaimTemplates functionality

**MongoDB Operations:**

- Initialize and manage replica sets
- Configure stable DNS for cluster members
- Understand PRIMARY/SECONDARY roles
- Test data replication and failover

**Production Operations:**

- Perform safe PVC resize operations
- Use cascade orphan for minimal downtime
- Update StatefulSet configurations
- Validate storage changes without data loss

**Troubleshooting Skills:**

- Debug StatefulSet pod issues
- Verify replica set health
- Diagnose PVC binding problems
- Validate DNS resolution for StatefulSets

---

## Reference Information

**MongoDB Connection Strings:**

```
Single node: mongodb://mongodb-0.mongodb-headless:27017/
Replica set: mongodb://mongodb-0.mongodb-headless:27017,mongodb-1.mongodb-headless:27017/?replicaSet=rs0
```

**Useful Commands:**

```bash
# Check StatefulSet status
kubectl get statefulset -n mongo-lab

# Check PVCs
kubectl get pvc -n mongo-lab

# View pod logs
kubectl logs -n mongo-lab mongodb-0

# Execute commands in pod
kubectl exec -it -n mongo-lab mongodb-0 -- mongosh

# Check replica set status
kubectl exec -n mongo-lab mongodb-0 -- mongosh --eval "rs.status()"
```

**DNS Resolution:**

```
Pod: mongodb-0.mongodb-headless.mongo-lab.svc.cluster.local
Service: mongodb-headless.mongo-lab.svc.cluster.local
```

---

## Time Estimates

- **Phase 1:** 30-40 minutes
- **Phase 2:** 15-20 minutes
- **Phase 3:** 15-20 minutes
- **Phase 4:** 20-25 minutes

**Total:** 80-105 minutes

---

## Notes

- Take time to understand each concept before moving forward
- Document your observations and learnings
- Don't hesitate to explore beyond the requirements
- Use `kubectl describe` and `kubectl logs` extensively
- Test failure scenarios to understand behavior

Good luck with your StatefulSet journey!
