# Lab: Network Isolation with Network Policies

## Scenario

Your company is running a two-tier web application in a shared Kubernetes cluster. The security audit has revealed a critical vulnerability in the current network architecture:

**Current State:**

- Frontend pods can communicate with backend pods (expected)
- Backend pods can communicate with frontend pods (unnecessary)
- Any pod in any namespace can reach any other pod
- No network segmentation exists between application tiers
- Violates defense-in-depth security principles

**Recent Incident:**
A compromised frontend pod was able to scan the entire cluster network and detected additional tenants.

**Management Mandate:**
Implement network segmentation using Kubernetes NetworkPolicies to enforce the principle of least privilege at the network layer.

The frontend should only be able to reach the backend, while the backend should not be able to initiate connections to frontend.

Your tasks: Implement namespace isolation and traffic control using NetworkPolicies while maintaining application functionality.

---

## Prerequisites

- k3s cluster with NetworkPolicy support (default CNI with network policy support)
- Understanding of basic networking concepts (ports, protocols)
- Completed Module 7 (Kubernetes Networking basics)

---

## Your Tasks

### Phase 1: Environment Setup and Default Behavior (10-15 minutes)

**Objective:** Deploy application and understand unrestricted connectivity before implementing policies

1. **Create namespace structure:**
   - Create `frontend` namespace with appropriate labels
   - Create `backend` namespace with appropriate labels
   - Verify namespace creation and labels

2. **Deploy nginx applications:**
   - Deploy nginx in frontend namespace (port 8080)
   - Deploy nginx in backend namespace (port 8081)
   - Create ClusterIP Services for both
   - Verify both deployments are running and services are available

3. **Test unrestricted connectivity:**
   - Test frontend pod → backend service (using service DNS name - service routes to pod)
   - Test frontend pod → backend pod directly (using pod IP)
   - Test backend pod → frontend service (service routes to pod)
   - Test backend pod → frontend pod directly (using pod IP)
   - **Important**: Services are just routing mechanisms - all traffic ultimately goes to pods

**Challenge Questions:**

- What's the difference between connecting via service DNS vs pod IP?
- Do NetworkPolicies control access to services or to pods?
- What is the current network security posture of your cluster?
- How would you identify pod IPs for testing direct connectivity?
- What happens if a frontend pod is compromised in this configuration?

---

### Phase 2: Understanding Network Policy Isolation (15-20 minutes)

**Objective:** Learn how applying a NetworkPolicy automatically creates isolation

1. **Apply your first NetworkPolicy:**
   - Create a simple NetworkPolicy in the backend namespace
   - Policy should select backend pods (using pod labels)
   - Specify `policyTypes: [Ingress]`
   - Leave ingress rules empty initially (`ingress: []`)
   - Apply the policy

2. **Observe automatic isolation:**
   - Test frontend → backend service again (should fail now)
   - Test frontend → backend pod directly (should also fail)
   - Understand why: the first policy selecting a pod makes it isolated
   - Default changes from "allow all" to "deny all" for selected pods

3. **Understand the isolation mechanism:**
   - When NO NetworkPolicies exist: all traffic allowed
   - When FIRST NetworkPolicy selecting a pod exists: that pod becomes isolated
   - Must explicitly define allowed traffic in ingress/egress rules
   - This is the Kubernetes approach to zero-trust networking

4. **Document the change:**
   - Before: everything works
   - After: backend is completely isolated
   - Application is broken (this is expected and intentional)

**Challenge Questions:**

- Why did applying ONE policy block ALL traffic to backend?
- What would happen if you applied a NetworkPolicy to frontend namespace now?
- What happens to existing connections when a NetworkPolicy is applied?
- Can backend pods still make outbound connections (egress)?

---

### Phase 3: Allow Required Traffic (20-25 minutes)

**Objective:** Selectively allow legitimate traffic flows while maintaining security boundaries

1. **Allow frontend → backend communication:**
   - Update backend NetworkPolicy to allow ingress traffic
   - Use `namespaceSelector` to allow from frontend namespace
   - Specify port 8081 (backend's port)
   - Apply the updated policy
   - Test that frontend can now reach backend service

2. **Handle DNS resolution:**
   - Notice that DNS resolution may not work in isolated pods
   - Create an egress NetworkPolicy allowing DNS queries
   - Target kube-system namespace where CoreDNS runs
   - Allow port 53 UDP traffic
   - Apply to both namespaces
   - Test that service name resolution works

3. **Optional - Isolate frontend namespace:**
   - Apply NetworkPolicy to frontend pods
   - Allow ingress from ingress-nginx namespace (if using Ingress)
   - Allow egress to backend namespace (port 8081)
   - Allow egress for DNS (port 53 UDP to kube-system)
   - Test that frontend isolation works correctly

**Challenge Questions:**

- Why use `namespaceSelector` instead of `podSelector` to allow frontend access?
- What's the difference between ingress and egress policies?
- Why is DNS resolution blocked without an explicit egress policy?
- **Do NetworkPolicies allow traffic to services or to pods?**
- **What port should you specify: the service port or the pod port?**
- **If service port is 80 but containerPort is 8080, which port goes in the NetworkPolicy?**
- Can you combine `namespaceSelector` and `podSelector` for more granular control?
- What happens if multiple NetworkPolicies select the same pod?

---

### Phase 4: Validation and Troubleshooting (10-15 minutes)

**Objective:** Test security boundaries and practice debugging

1. **Verify security boundaries:**
   - Frontend can reach backend service (should work)
   - Frontend can reach backend pod directly (should work - same namespace selector)
   - Backend cannot reach frontend (should fail if frontend is isolated)
   - Test DNS resolution from both namespaces (should work)
   - Document which traffic flows are allowed vs blocked

2. **Troubleshooting practice:**
   - Intentionally break a policy (change port number to wrong value)
   - Try to connect and observe failure
   - Debug using `kubectl describe networkpolicy`
   - Check pod and namespace labels
   - Fix the policy and retest

3. **Document the architecture:**
   - Create a simple diagram showing allowed traffic flows
   - List blocked traffic flows
   - Document security improvements achieved
   - Compare before/after network security posture

**Challenge Questions:**

- How do you debug when a connection is blocked by a NetworkPolicy?
- What's the difference between having no policy vs having a deny policy?
- How do NetworkPolicies combine when multiple policies match the same pod?
- What tools can help visualize NetworkPolicy rules?
- How would you test policies without disrupting production traffic?

---

## Success Criteria

- [ ] Two namespaces created with appropriate labels
- [ ] Nginx deployments running in both namespaces
- [ ] Services created for both applications
- [ ] Tested and documented default "allow all" behavior
- [ ] Applied NetworkPolicy creates automatic isolation
- [ ] Frontend can communicate with backend service
- [ ] DNS resolution works in isolated namespaces
- [ ] Backend cannot initiate connections to frontend (if implemented)
- [ ] Troubleshooting methodology practiced
- [ ] Security boundaries validated
- [ ] Architecture documented

---

## Expected Timeline

- Phase 1 (Setup & Baseline): 10-15 minutes
- Phase 2 (Understanding Isolation): 15-20 minutes
- Phase 3 (Allow Required Traffic): 20-25 minutes
- Phase 4 (Validation): 10-15 minutes

**Total:** 55-75 minutes (target ~60 minutes)

---

## Hints and Tips

### Key Concept - Automatic Isolation

**Critical Understanding:**

- Without any NetworkPolicies: all traffic allowed
- First NetworkPolicy that selects a pod: that pod becomes isolated
- Default changes from "allow all" to "deny all" for selected pods
- Must explicitly define allowed traffic in policy rules
- This is the foundation of zero-trust networking in Kubernetes

### CRITICAL: NetworkPolicies Target Pods, Not Services

**This is a common misconception that must be understood:**

NetworkPolicies control traffic **to and from pods**, not services:

- ❌ You CANNOT target a service by name in a NetworkPolicy
- âœ" You CAN target pods using labels (via podSelector)
- âœ" Services are just routing/load-balancing mechanisms
- âœ" All traffic ultimately goes to pods, which is where policies apply

**What this means:**

- When you test `curl http://backend-service.backend:8081`:
  1. DNS resolves service name to ClusterIP
  2. Service routes to a pod IP
  3. **NetworkPolicy is evaluated at the pod level**
  4. If allowed, traffic reaches the pod

**Port specification in NetworkPolicies:**

- The `port` in a NetworkPolicy refers to the **pod's containerPort**
- This may or may not match the service port
- Example:
  - Service: `port: 80` → `targetPort: 8081`
  - Pod: `containerPort: 8081`
  - NetworkPolicy: `port: 8081` (must match pod port!)

**Why this matters:**

- If service port ≠ pod port, you must use pod port in NetworkPolicy
- NetworkPolicies work with pod IPs and labels, independent of services
- You can have pods without services, and NetworkPolicies still work

### NetworkPolicy Structure

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-name
  namespace: target-namespace
spec:
  podSelector:
    matchLabels:
      app: target-app
  policyTypes:
  - Ingress  # or Egress, or both
  ingress:   # List of allowed ingress rules
  - from:
    - namespaceSelector:
        matchLabels:
          name: allowed-namespace
    ports:
    - protocol: TCP
      port: 8080
```

### Selectors Explained

**podSelector:**

- Selects pods within the NetworkPolicy's namespace
- Empty selector `{}` means "all pods in this namespace"
- Used in spec.podSelector to define which pods the policy applies to
- Used in ingress/egress rules to allow traffic from/to specific pods

**namespaceSelector:**

- Selects entire namespaces
- Allows traffic from/to all pods in matching namespaces
- Empty selector `{}` means "all namespaces"
- Namespaces must be labeled for selection to work

**Combining Selectors:**

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: frontend
    podSelector:
      matchLabels:
        app: web
```

This allows traffic from pods labeled `app=web` in namespaces labeled `name=frontend`.

### Common Issues

**DNS Not Working:**

- Egress policy needed for DNS resolution
- Must allow port 53 UDP to kube-system namespace
- CoreDNS runs in kube-system

**Policy Not Taking Effect:**

- Check that CNI supports NetworkPolicies (k3s default does)
- Verify pod labels match podSelector
- Verify namespace labels match namespaceSelector
- Use `kubectl describe networkpolicy` to check policy

**Wrong Traffic Blocked:**

- Check port numbers match
- Verify protocol (TCP vs UDP)
- Check selector labels are correct
- Remember: policies are additive (multiple policies combine)

### Testing Commands

```bash
# Get pod IP for direct testing
kubectl get pod -n backend -o wide

# Test HTTP connectivity from frontend to backend service
kubectl exec -n frontend deploy/frontend-deployment -- curl -s http://backend-service.backend:8081

# Test HTTP connectivity from frontend to backend pod IP
kubectl exec -n frontend deploy/frontend-deployment -- curl -s http://<POD-IP>:8081

# Test DNS resolution
kubectl exec -n frontend deploy/frontend-deployment -- nslookup backend-service.backend

# Check NetworkPolicy applied
kubectl get networkpolicy -n backend
kubectl describe networkpolicy <policy-name> -n backend

# Check pod labels
kubectl get pods -n backend --show-labels

# Check namespace labels
kubectl get namespace backend --show-labels
```

### Debugging Methodology

1. **Verify policy exists and is applied:**

   ```bash
   kubectl get networkpolicy -n <namespace>
   kubectl describe networkpolicy <name> -n <namespace>
   ```

2. **Check pod labels match podSelector:**

   ```bash
   kubectl get pods -n <namespace> --show-labels
   ```

3. **Check namespace labels match namespaceSelector:**

   ```bash
   kubectl get namespace <namespace> --show-labels
   ```

4. **Verify port numbers and protocols are correct**

5. **Check if multiple policies are combining**

6. **Test with simple curl/nc commands to isolate issue**

---

## Advanced Challenges (Optional)

If you complete the main tasks early and want to explore further:

1. **Egress to External Services:**
   - Allow backend to access specific external IP addresses
   - Use ipBlock with CIDR notation
   - Test external connectivity

2. **Multiple Port Access:**
   - Deploy backend with multiple ports (e.g., 8081 for HTTP, 9090 for metrics)
   - Create policy allowing different namespaces to access different ports
   - Frontend gets HTTP, monitoring gets metrics

3. **Pod-to-Pod Within Namespace:**
   - Deploy multiple pod types in backend namespace
   - Create policies that allow some pods to communicate but not others
   - Implement micro-segmentation within a namespace

4. **Policy Precedence:**
   - Create multiple NetworkPolicies selecting the same pods
   - Understand how they combine (additive)
   - Test the combined behavior

5. **Monitoring Integration:**
   - Create monitoring namespace
   - Allow monitoring to scrape metrics from both frontend and backend
   - Ensure applications cannot reach monitoring namespace

---

## Connection to Production

**What You're Learning:**

This lab teaches the foundational pattern for network security in Kubernetes:

1. **Zero-Trust Networking:** Default deny, explicitly allow needed traffic
2. **Namespace Isolation:** Teams cannot interfere with each other's networks
3. **Defense in Depth:** Network layer security complements RBAC and Pod Security
4. **Micro-segmentation:** Control traffic between application tiers

**Real-World Applications:**

- **Multi-Tenant Clusters:** Isolate customer workloads from each other
- **Compliance:** PCI-DSS, HIPAA require network segmentation
- **Security Incidents:** Limit blast radius of compromised pods
- **Microservices:** Control service-to-service communication explicitly

**Next Steps:**

After mastering NetworkPolicies, you'll combine them with:

- Pod Security Standards (Module 9 Session 2): Control what pods can do
- RBAC (Module 9 Session 3): Control who can access what
- Together: Complete security posture (Network + Workload + Access)

---

## OpenShift Considerations

The NetworkPolicy API is identical in OpenShift, but there are some differences:

**Same:**

- NetworkPolicy API and syntax
- Automatic isolation behavior
- Selector mechanisms

**OpenShift Additions:**

- OpenShift SDN or OVN-Kubernetes as CNI
- EgressNetworkPolicy (OpenShift-specific) for egress control
- Additional multi-tenancy features in some SDN modes
- Web console for NetworkPolicy visualization
- Integration with OpenShift Projects (namespaces with RBAC)

Skills learned here transfer directly to OpenShift environments.

---

**Note:** This lab teaches production-ready network security patterns. Focus on understanding the automatic isolation mechanism and how NetworkPolicies combine. These concepts are fundamental to securing Kubernetes clusters in any environment.
